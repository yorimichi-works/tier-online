import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {randomUUID} from "node:crypto";

import {
  CustomTag,
  customTagsFromUnknown,
  searchTagsFor,
} from "../customTags";
import {topicSearchTokens} from "../searchTokens";
import {DEFAULT_DICTIONARY_VERSION} from "./phase1d";
import {
  DEFAULT_PROMPT_VERSION,
  DEFAULT_TRANSLATION_PROVIDER,
  DEFAULT_TRANSLATION_VERSION,
  SourceBatch,
  SourceBatchItem,
  TranslatedBatch,
  TranslationLanguage,
  aggregateTranslationStatus,
  buildSourceContent,
  contentVersionOf,
  isTranslationCandidate,
  pendingTranslationsAfterStaleBatch,
  sourceLanguageOf,
  targetLanguagesFor,
  translationStatusesForTopic,
  translationsOf,
  validateTranslatedBatch,
} from "./translationBatch";

export type ImportReport = {
  batchId: string;
  dryRun: boolean;
  startedAt: string;
  finishedAt: string;
  updated: Array<{documentId: string; status: string}>;
  idempotent: string[];
  versionMismatches: string[];
  ineligible: string[];
  missing: string[];
  batchMismatches: string[];
  skippedManual: Array<{documentId: string; language: string}>;
  statusCounts: Record<string, number>;
  translationStats: {
    total: number;
    cacheHits: number;
    codexTranslations: number;
    manualSkipped: number;
    failed: number;
    reviewRequired: number;
  };
};

export const createBatchId = (now = new Date()): string => {
  const timestamp = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
  const suffix = randomUUID().slice(0, 8);
  return `tr_${timestamp}_${suffix}`;
};

export const initializeTranslationFirestore = (projectId: string): Firestore => {
  if (getApps().length === 0) initializeApp({projectId});
  return getFirestore();
};

export const fetchAndClaimPending = async (
  firestore: Firestore,
  options: {
    batchId: string;
    batchSize: number;
    scanLimit: number;
    dryRun?: boolean;
  },
): Promise<SourceBatch> => {
  // moderationStatus未設定の古いTierも対象にしたいので、クエリではisPublic
  // だけで絞り込み、承認判定はisTranslationCandidate側に任せる。
  const snapshot = await firestore.collection("topics")
    .where("isPublic", "==", true)
    .limit(options.scanLimit)
    .get();
  const claimed: Array<{
    documentId: string;
    data: Record<string, unknown>;
    targets: TranslationLanguage[];
  }> = [];

  for (const candidate of snapshot.docs) {
    if (claimed.length >= options.batchSize) break;
    const result = await firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(candidate.ref);
      if (!current.exists) return null;
      const data = current.data() as Record<string, unknown>;
      if (!isTranslationCandidate(data)) return null;
      const targets = targetLanguagesFor(data);
      if (targets.length === 0) return null;
      if (!options.dryRun) {
        const translations = translationsOf(data);
        const nextTranslations = {...translations};
        for (const language of targets) {
          nextTranslations[language] = {
            ...(translations[language] ?? {}),
            status: "processing",
            reviewRequired: false,
            sourceContentVersion: contentVersionOf(data),
            translationVersion: DEFAULT_TRANSLATION_VERSION,
            promptVersion: DEFAULT_PROMPT_VERSION,
            translationProvider: DEFAULT_TRANSLATION_PROVIDER,
            translationMode: "auto",
            batchId: options.batchId,
          };
        }
        transaction.set(candidate.ref, {
          translations: nextTranslations,
          translationStatus: "processing",
          translationBatchId: options.batchId,
          processingStartedAt: FieldValue.serverTimestamp(),
          translationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      return {data, targets};
    });
    if (result) claimed.push({
      documentId: candidate.id,
      data: result.data,
      targets: result.targets,
    });
  }

  const items: SourceBatchItem[] = [];
  for (const claimedTopic of claimed) {
    const itemSnapshot = await firestore.collection("topics")
      .doc(claimedTopic.documentId).collection("items").get();
    items.push({
      documentId: claimedTopic.documentId,
      contentVersion: contentVersionOf(claimedTopic.data),
      sourceLanguage: sourceLanguageOf(claimedTopic.data),
      targetLanguages: claimedTopic.targets,
      context: {
        ...(typeof claimedTopic.data.categoryId === "string" ?
          {categoryId: claimedTopic.data.categoryId} : {}),
        ...(Array.isArray(claimedTopic.data.customTags) &&
            claimedTopic.data.customTags.length > 0 ? {
          tagTranslationInstructions: "Translate each custom tag using the Tier title, description, and surrounding tags as context. Preserve each tagId and sourceText exactly. Do not merge tags whose translations happen to match. Use translation:null and status:ambiguous when the context is insufficient.",
        } : {}),
      },
      content: buildSourceContent(claimedTopic.data, itemSnapshot.docs.map((item) => ({
        id: item.id,
        data: item.data() as Record<string, unknown>,
      }))),
    });
  }
  return {
    schemaVersion: 1,
    batchId: options.batchId,
    createdAt: new Date().toISOString(),
    targetLanguages: [...new Set(items.flatMap((item) => item.targetLanguages))],
    items,
  };
};

const cleanTranslatedLocale = (
  value: Record<string, unknown>,
  language: string,
  sourceContentVersion: number,
  batchId: string,
  dictionaryVersion: string,
): Record<string, unknown> => {
  const cacheHit = value.cacheHit === true;
  const result: Record<string, unknown> = {
    status: value.status,
    reviewRequired: value.reviewRequired,
    sourceContentVersion,
    translationVersion: DEFAULT_TRANSLATION_VERSION,
    promptVersion: DEFAULT_PROMPT_VERSION,
    translationProvider: cacheHit ? "exact-cache" : DEFAULT_TRANSLATION_PROVIDER,
    translationMode: "auto",
    qualityStatus: "auto",
    dictionaryVersion,
    manualTranslationOutdated: false,
    cacheHit,
    batchId,
    translatedAt: FieldValue.serverTimestamp(),
  };
  for (const key of ["title", "description", "category", "customTags", "tags", "itemNames", "translationErrorCode"]) {
    if (value[key] !== undefined) result[key] = value[key];
  }
  if (value.status === "failed" && result.translationErrorCode === undefined) {
    result.translationErrorCode = `translation_failed_${language}`;
  }
  return result;
};

const mergeCustomTagTranslations = (
  currentValue: unknown,
  incomingValue: unknown,
  language: string,
): CustomTag[] => {
  const current = customTagsFromUnknown(currentValue);
  if (!Array.isArray(incomingValue)) return current;
  const incomingById = new Map<string, Record<string, unknown>>();
  for (const value of incomingValue) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) continue;
    const tag = value as Record<string, unknown>;
    if (typeof tag.tagId === "string") incomingById.set(tag.tagId, tag);
  }
  return current.map((tag) => {
    const incoming = incomingById.get(tag.id);
    const existing = tag.translations[language];
    // Manual entries are an explicit human decision and must survive both
    // source edits and a later automated batch import.
    if (!incoming || existing?.status === "manual" ||
        existing?.status === "translated" || existing?.status === "ambiguous") {
      return tag;
    }
    const status = incoming.status;
    if (status !== "translated" && status !== "ambiguous" && status !== "failed") {
      return tag;
    }
    const text = status === "translated" && typeof incoming.translation === "string" &&
        incoming.translation.trim().length > 0 ? incoming.translation.trim() : null;
    return {
      ...tag,
      translations: {
        ...tag.translations,
        [language]: {
          text,
          status,
          ...(typeof incoming.confidence === "number" ?
            {confidence: incoming.confidence} : {}),
        },
      },
    };
  });
};

type ImportOutcome =
  | {kind: "missing" | "versionMismatch" | "ineligible" | "idempotent" | "batchMismatch"}
  | {
    kind: "updated";
    status: string;
    skippedManual: Array<{documentId: string; language: string}>;
    stats: ImportReport["translationStats"];
  };

export const importTranslatedBatch = async (
  firestore: Firestore,
  source: SourceBatch,
  translated: TranslatedBatch,
  dryRun: boolean,
): Promise<ImportReport> => {
  const validation = validateTranslatedBatch(source, translated);
  if (!validation.valid) {
    throw new Error(`Translation validation failed:\n${validation.errors.join("\n")}`);
  }
  const report: ImportReport = {
    batchId: source.batchId,
    dryRun,
    startedAt: new Date().toISOString(),
    finishedAt: "",
    updated: [],
    idempotent: [],
    versionMismatches: [],
    ineligible: [],
    missing: [],
    batchMismatches: [],
    skippedManual: [],
    statusCounts: {},
    translationStats: {
      total: 0,
      cacheHits: 0,
      codexTranslations: 0,
      manualSkipped: 0,
      failed: 0,
      reviewRequired: 0,
    },
  };
  const sourceById = new Map(source.items.map((item) => [item.documentId, item]));

  for (const translatedItem of translated.items) {
    const sourceItem = sourceById.get(translatedItem.documentId)!;
    const reference = firestore.collection("topics").doc(translatedItem.documentId);
    const outcome: ImportOutcome = await firestore.runTransaction(
      async (transaction): Promise<ImportOutcome> => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        return {kind: "missing"};
      }
      const data = snapshot.data() as Record<string, unknown>;
      const currentVersion = contentVersionOf(data);
      if (currentVersion !== translatedItem.sourceContentVersion) {
        if (!dryRun) transaction.set(reference, {
          translationStatus: "pending",
          translationBatchId: FieldValue.delete(),
          processingStartedAt: FieldValue.delete(),
          translationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {kind: "versionMismatch"};
      }
      if (data.isPublic === false ||
        (data.moderationStatus != null && data.moderationStatus !== "approved")) {
        if (!dryRun) transaction.set(reference, {
          translationStatus: "pending",
          translationBatchId: FieldValue.delete(),
          processingStartedAt: FieldValue.delete(),
          translationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {kind: "ineligible"};
      }
      if (
        data.lastTranslationBatchId === source.batchId &&
        data.translationStatus !== "processing"
      ) {
        return {kind: "idempotent"};
      }
      if (data.translationBatchId !== source.batchId) {
        // Another worker owns this document. Record the conflict and continue
        // importing independent items instead of aborting the whole batch.
        return {kind: "batchMismatch"};
      }
      const existing = translationsOf(data);
      const next: Record<string, unknown> = {...existing};
      let nextCustomTags = customTagsFromUnknown(data.customTags);
      const skippedManual: Array<{documentId: string; language: string}> = [];
      const stats: ImportReport["translationStats"] = {
        total: 0,
        cacheHits: 0,
        codexTranslations: 0,
        manualSkipped: 0,
        failed: 0,
        reviewRequired: 0,
      };
      for (const language of sourceItem.targetLanguages) {
        const current = existing[language];
        if (current?.translationMode === "manual") {
          skippedManual.push({documentId: translatedItem.documentId, language});
          stats.manualSkipped += 1;
          continue;
        }
        const incoming = translatedItem.translations[language];
        if (incoming) {
          stats.total += 1;
          if (incoming.cacheHit) stats.cacheHits += 1;
          else stats.codexTranslations += 1;
          if (incoming.status === "failed") stats.failed += 1;
          if (incoming.reviewRequired) stats.reviewRequired += 1;
          const dictionaryVersion = (sourceItem as SourceBatchItem & {
            translationContext?: {dictionaryVersion?: string};
          }).translationContext?.dictionaryVersion ?? DEFAULT_DICTIONARY_VERSION;
          next[language] = cleanTranslatedLocale(
            incoming as unknown as Record<string, unknown>,
            language,
            translatedItem.sourceContentVersion,
            source.batchId,
            dictionaryVersion,
          );
          nextCustomTags = mergeCustomTagTranslations(
            nextCustomTags,
            incoming.customTags,
            language,
          );
        } else if (current?.batchId === source.batchId) {
          next[language] = {...current, status: "pending"};
        }
      }
      const statuses = translationStatusesForTopic(
        data,
        next as ReturnType<typeof translationsOf>,
      );
      const status = aggregateTranslationStatus(statuses);
      if (!dryRun) transaction.set(reference, {
        translations: next,
        ...(nextCustomTags.length > 0 ? {
          customTags: nextCustomTags,
          searchTags: searchTagsFor(nextCustomTags),
          searchTokens: topicSearchTokens([
            data.title,
            data.description,
            data.category,
            data.categoryId,
            ...searchTagsFor(nextCustomTags),
            ...Object.values(sourceItem.content.itemNames ?? {}),
          ]),
        } : {}),
        translationStatus: status,
        hasTranslationReviewRequired: statuses.includes("review_required"),
        hasTranslationFailures: statuses.includes("failed"),
        translationBatchId: FieldValue.delete(),
        processingStartedAt: FieldValue.delete(),
        lastTranslationBatchId: source.batchId,
        translationUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {kind: "updated", status, skippedManual, stats};
    });
    switch (outcome.kind) {
    case "missing":
      report.missing.push(translatedItem.documentId);
      break;
    case "versionMismatch":
      report.versionMismatches.push(translatedItem.documentId);
      break;
    case "ineligible":
      report.ineligible.push(translatedItem.documentId);
      break;
    case "idempotent":
      report.idempotent.push(translatedItem.documentId);
      break;
    case "batchMismatch":
      report.batchMismatches.push(translatedItem.documentId);
      break;
    case "updated":
      report.updated.push({documentId: translatedItem.documentId, status: outcome.status});
      report.statusCounts[outcome.status] =
        (report.statusCounts[outcome.status] ?? 0) + 1;
      report.skippedManual.push(...outcome.skippedManual);
      for (const key of Object.keys(outcome.stats) as Array<keyof typeof outcome.stats>) {
        report.translationStats[key] += outcome.stats[key];
      }
      break;
    }
  }
  report.finishedAt = new Date().toISOString();
  return report;
};

export type ReviewExport = {
  schemaVersion: 1;
  createdAt: string;
  items: Array<{
    documentId: string;
    contentVersion: number;
    sourceLanguage: TranslationLanguage;
    content: ReturnType<typeof buildSourceContent>;
    translations: Record<string, unknown>;
  }>;
};

export const staleTranslationUpdate = (
  data: Record<string, unknown>,
  batchId: unknown,
) => {
  const translations = pendingTranslationsAfterStaleBatch(data, batchId);
  const statuses = translationStatusesForTopic(
    data,
    translations as ReturnType<typeof translationsOf>,
  );
  return {
    translations,
    translationStatus: aggregateTranslationStatus(statuses),
    hasTranslationReviewRequired: statuses.includes("review_required"),
    hasTranslationFailures: statuses.includes("failed"),
  };
};

export const exportReviewRequired = async (
  firestore: Firestore,
  limit: number,
): Promise<ReviewExport> => {
  const snapshot = await firestore.collection("topics")
    .where("hasTranslationReviewRequired", "==", true)
    .limit(limit)
    .get();
  const items: ReviewExport["items"] = [];
  for (const document of snapshot.docs) {
    const data = document.data() as Record<string, unknown>;
    if (data.isPublic === false ||
      (data.moderationStatus != null && data.moderationStatus !== "approved")) continue;
    const reviewTranslations = Object.fromEntries(Object.entries(translationsOf(data))
      .filter(([, translation]) => translation?.reviewRequired === true));
    if (Object.keys(reviewTranslations).length === 0) continue;
    const itemSnapshot = await document.ref.collection("items").get();
    items.push({
      documentId: document.id,
      contentVersion: contentVersionOf(data),
      sourceLanguage: sourceLanguageOf(data),
      content: buildSourceContent(data, itemSnapshot.docs.map((item) => ({
        id: item.id,
        data: item.data() as Record<string, unknown>,
      }))),
      translations: reviewTranslations,
    });
  }
  return {schemaVersion: 1, createdAt: new Date().toISOString(), items};
};

export const resetStaleProcessing = async (
  firestore: Firestore,
  staleHours: number,
  dryRun: boolean,
): Promise<string[]> => {
  const threshold = Timestamp.fromMillis(Date.now() - staleHours * 60 * 60 * 1000);
  const snapshot = await firestore.collection("topics")
    .where("translationStatus", "==", "processing")
    .where("processingStartedAt", "<", threshold)
    .get();
  const reset: string[] = [];
  for (const document of snapshot.docs) {
    const data = document.data() as Record<string, unknown>;
    const batchId = data.translationBatchId;
    const update = staleTranslationUpdate(data, batchId);
    reset.push(document.id);
    if (!dryRun) await document.ref.set({
      ...update,
      translationBatchId: FieldValue.delete(),
      processingStartedAt: FieldValue.delete(),
      translationUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return reset;
};
