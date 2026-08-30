import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {randomUUID} from "node:crypto";

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
  skippedManual: Array<{documentId: string; language: string}>;
  statusCounts: Record<string, number>;
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
  const snapshot = await firestore.collection("topics")
    .where("isPublic", "==", true)
    .where("moderationStatus", "==", "approved")
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
): Record<string, unknown> => {
  const result: Record<string, unknown> = {
    status: value.status,
    reviewRequired: value.reviewRequired,
    sourceContentVersion,
    translationVersion: DEFAULT_TRANSLATION_VERSION,
    promptVersion: DEFAULT_PROMPT_VERSION,
    translationProvider: DEFAULT_TRANSLATION_PROVIDER,
    translationMode: "auto",
    batchId,
    translatedAt: FieldValue.serverTimestamp(),
  };
  for (const key of ["title", "description", "category", "tags", "itemNames", "translationErrorCode"]) {
    if (value[key] !== undefined) result[key] = value[key];
  }
  if (value.status === "failed" && result.translationErrorCode === undefined) {
    result.translationErrorCode = `translation_failed_${language}`;
  }
  return result;
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
    skippedManual: [],
    statusCounts: {},
  };
  const sourceById = new Map(source.items.map((item) => [item.documentId, item]));

  for (const translatedItem of translated.items) {
    const sourceItem = sourceById.get(translatedItem.documentId)!;
    const reference = firestore.collection("topics").doc(translatedItem.documentId);
    await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        report.missing.push(translatedItem.documentId);
        return;
      }
      const data = snapshot.data() as Record<string, unknown>;
      const currentVersion = contentVersionOf(data);
      if (currentVersion !== translatedItem.sourceContentVersion) {
        report.versionMismatches.push(translatedItem.documentId);
        if (!dryRun) transaction.set(reference, {
          translationStatus: "pending",
          translationBatchId: FieldValue.delete(),
          processingStartedAt: FieldValue.delete(),
          translationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return;
      }
      if (data.isPublic === false || data.moderationStatus !== "approved") {
        report.ineligible.push(translatedItem.documentId);
        if (!dryRun) transaction.set(reference, {
          translationStatus: "pending",
          translationBatchId: FieldValue.delete(),
          processingStartedAt: FieldValue.delete(),
          translationUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return;
      }
      if (
        data.lastTranslationBatchId === source.batchId &&
        data.translationStatus !== "processing"
      ) {
        report.idempotent.push(translatedItem.documentId);
        return;
      }
      if (data.translationBatchId !== source.batchId) {
        throw new Error(`${translatedItem.documentId}: Firestore batchId mismatch`);
      }
      const existing = translationsOf(data);
      const next: Record<string, unknown> = {...existing};
      for (const language of sourceItem.targetLanguages) {
        const current = existing[language];
        if (current?.translationMode === "manual") {
          report.skippedManual.push({documentId: translatedItem.documentId, language});
          continue;
        }
        const incoming = translatedItem.translations[language];
        if (incoming) {
          next[language] = cleanTranslatedLocale(
            incoming as unknown as Record<string, unknown>,
            language,
            translatedItem.sourceContentVersion,
            source.batchId,
          );
        } else if (current?.batchId === source.batchId) {
          next[language] = {...current, status: "pending"};
        }
      }
      const sourceLanguage = sourceLanguageOf(data);
      const statuses = (["ja", "en", "ko", "zh-TW", "pt-BR"] as TranslationLanguage[])
        .filter((language) => language !== sourceLanguage)
        .map((language) => {
          const translation = next[language] as Record<string, unknown> | undefined;
          if (translation?.translationMode === "manual") {
            return String(translation.status ?? "completed");
          }
          if (translation?.sourceContentVersion !== currentVersion) return "pending";
          return String(translation?.status ?? "pending");
        }) as Array<"pending" | "processing" | "completed" | "failed" | "review_required">;
      const status = aggregateTranslationStatus(statuses);
      report.updated.push({documentId: translatedItem.documentId, status});
      report.statusCounts[status] = (report.statusCounts[status] ?? 0) + 1;
      if (!dryRun) transaction.set(reference, {
        translations: next,
        translationStatus: status,
        hasTranslationReviewRequired: statuses.includes("review_required"),
        translationBatchId: FieldValue.delete(),
        processingStartedAt: FieldValue.delete(),
        lastTranslationBatchId: source.batchId,
        translationUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  }
  report.finishedAt = new Date().toISOString();
  return report;
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
    const next = pendingTranslationsAfterStaleBatch(data, batchId);
    reset.push(document.id);
    if (!dryRun) await document.ref.set({
      translations: next,
      translationStatus: "pending",
      translationBatchId: FieldValue.delete(),
      processingStartedAt: FieldValue.delete(),
      translationUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return reset;
};
