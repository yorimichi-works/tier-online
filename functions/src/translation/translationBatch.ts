import {createHash} from "node:crypto";

import {firestoreLanguage} from "../internationalization";

export const TRANSLATION_LANGUAGES = [
  "ja",
  "en",
  "ko",
  "zh-TW",
  "pt-BR",
] as const;

export type TranslationLanguage = typeof TRANSLATION_LANGUAGES[number];
export type LocaleTranslationStatus =
  "pending" | "processing" | "completed" | "failed" | "review_required";
export type TopicTranslationStatus =
  "pending" | "processing" | "completed" | "partial" | "failed" |
  "review_required";

export type SourceContent = {
  title: string;
  description?: string;
  category?: string;
  tags?: string[];
  itemNames?: Record<string, string>;
};

export type SourceBatchItem = {
  documentId: string;
  contentVersion: number;
  sourceLanguage: TranslationLanguage;
  targetLanguages: TranslationLanguage[];
  context: {
    categoryId?: string;
  };
  content: SourceContent;
};

export type SourceBatch = {
  schemaVersion: 1;
  batchId: string;
  createdAt: string;
  targetLanguages: TranslationLanguage[];
  items: SourceBatchItem[];
};

export type TranslatedLocale = {
  status: "completed" | "failed" | "review_required";
  title?: string;
  description?: string;
  category?: string;
  tags?: string[];
  itemNames?: Record<string, string>;
  reviewRequired: boolean;
  translationErrorCode?: string;
  cacheHit?: boolean;
};

export type TranslatedBatch = {
  schemaVersion: 1;
  batchId: string;
  items: Array<{
    documentId: string;
    sourceContentVersion: number;
    translations: Partial<Record<TranslationLanguage, TranslatedLocale>>;
  }>;
};

export type StoredTranslation = Omit<TranslatedLocale, "status"> & {
  status: LocaleTranslationStatus;
  sourceContentVersion: number;
  translationVersion: number;
  promptVersion: string;
  translationProvider: string;
  translationMode: "auto" | "manual";
  qualityStatus?: "auto" | "reviewed" | "approved" | "rejected";
  dictionaryVersion?: string;
  manualTranslationOutdated?: boolean;
  translatedAt?: unknown;
  batchId?: string;
};

export const DEFAULT_TRANSLATION_VERSION = 1;
export const DEFAULT_PROMPT_VERSION = "tier-translation-v2";
export const DEFAULT_TRANSLATION_PROVIDER = "codex";

const asRecord = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ?
    value as Record<string, unknown> : null;

export const sourceLanguageOf = (
  data: Record<string, unknown>,
): TranslationLanguage => {
  const code = firestoreLanguage(data.sourceLanguage ?? data.contentLanguage);
  return (TRANSLATION_LANGUAGES as readonly string[]).includes(code) ?
    code as TranslationLanguage : "ja";
};

export const contentVersionOf = (data: Record<string, unknown>): number => {
  const value = data.contentVersion;
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ?
    value : 1;
};

export const translationsOf = (
  data: Record<string, unknown>,
): Partial<Record<TranslationLanguage, StoredTranslation>> => {
  const raw = asRecord(data.translations);
  if (!raw) return {};
  const result: Partial<Record<TranslationLanguage, StoredTranslation>> = {};
  for (const language of TRANSLATION_LANGUAGES) {
    const value = asRecord(raw[language]);
    if (value) result[language] = value as StoredTranslation;
  }
  return result;
};

export const targetLanguagesFor = (
  data: Record<string, unknown>,
): TranslationLanguage[] => {
  const sourceLanguage = sourceLanguageOf(data);
  const version = contentVersionOf(data);
  const translations = translationsOf(data);
  return TRANSLATION_LANGUAGES.filter((language) => {
    if (language === sourceLanguage) return false;
    const current = translations[language];
    if (current?.translationMode === "manual") return false;
    if (
      current?.sourceContentVersion === version &&
      (current.status === "completed" || current.status === "review_required")
    ) return false;
    return current?.status !== "processing";
  });
};

export const isTranslationCandidate = (
  data: Record<string, unknown>,
): boolean => data.isPublic !== false &&
  data.moderationStatus === "approved" &&
  data.translationStatus !== "processing" &&
  targetLanguagesFor(data).length > 0;

const normalizedText = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  return text.length > 0 ? text : undefined;
};

export const buildSourceContent = (
  topic: Record<string, unknown>,
  items: Array<{id: string; data: Record<string, unknown>}>,
): SourceContent => {
  const title = normalizedText(topic.title) ?? "";
  const description = normalizedText(topic.description);
  const category = normalizedText(topic.category);
  const tags = Array.isArray(topic.tags) ? topic.tags
    .map(normalizedText)
    .filter((value): value is string => value !== undefined) : [];
  const itemNames = Object.fromEntries(items
    .map((item) => [item.id, normalizedText(item.data.name)] as const)
    .filter((entry): entry is readonly [string, string] => entry[1] !== undefined));
  return {
    title,
    ...(description ? {description} : {}),
    ...(category ? {category} : {}),
    ...(tags.length > 0 ? {tags} : {}),
    ...(Object.keys(itemNames).length > 0 ? {itemNames} : {}),
  };
};

export const sourceFingerprint = (
  topic: Record<string, unknown>,
  items: Array<{id: string; name?: unknown}>,
): string => {
  const canonical = {
    sourceLanguage: sourceLanguageOf(topic),
    title: normalizedText(topic.title) ?? "",
    description: normalizedText(topic.description) ?? "",
    category: normalizedText(topic.category) ?? "",
    tags: Array.isArray(topic.tags) ? topic.tags.map((tag) => String(tag)) : [],
    items: [...items]
      .map((item) => ({id: item.id, name: normalizedText(item.name) ?? ""}))
      .sort((left, right) => left.id.localeCompare(right.id)),
  };
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
};

export const pendingTranslationsAfterSourceChange = (
  data: Record<string, unknown>,
): Record<string, unknown> => {
  const existing = translationsOf(data);
  return Object.fromEntries(Object.entries(existing).map(([language, value]) => [
    language,
    value?.translationMode === "manual" ? {
      ...value,
      manualTranslationOutdated: true,
    } : {
      ...value,
      status: "pending",
    },
  ]));
};

export const pendingTranslationsAfterStaleBatch = (
  data: Record<string, unknown>,
  batchId: unknown,
): Record<string, unknown> => {
  const existing = translationsOf(data);
  return Object.fromEntries(Object.entries(existing).map(([language, value]) => [
    language,
    value?.status === "processing" && value.batchId === batchId ?
      {...value, status: "pending"} : value,
  ]));
};

const allowedKeys = (
  value: Record<string, unknown>,
  keys: readonly string[],
  path: string,
  errors: string[],
) => {
  for (const key of Object.keys(value)) {
    if (!keys.includes(key)) errors.push(`${path}.${key}: unknown field`);
  }
};

const validString = (
  value: unknown,
  path: string,
  maximum: number,
  errors: string[],
) => {
  if (typeof value !== "string" || value.trim().length === 0) {
    errors.push(`${path}: non-empty string required`);
  } else if (value.length > maximum) {
    errors.push(`${path}: exceeds ${maximum} characters`);
  }
};

export type ValidationReport = {
  valid: boolean;
  errors: string[];
  itemCount: number;
  translationCount: number;
};

export const validateTranslatedBatch = (
  source: SourceBatch,
  translated: unknown,
): ValidationReport => {
  const errors: string[] = [];
  const root = asRecord(translated);
  if (!root) return {valid: false, errors: ["root: object required"], itemCount: 0, translationCount: 0};
  allowedKeys(root, ["schemaVersion", "batchId", "items"], "root", errors);
  if (root.schemaVersion !== 1) errors.push("schemaVersion: must be 1");
  if (root.batchId !== source.batchId) errors.push("batchId: source batch mismatch");
  if (!Array.isArray(root.items)) {
    errors.push("items: array required");
    return {valid: false, errors, itemCount: 0, translationCount: 0};
  }
  const sourceById = new Map(source.items.map((item) => [item.documentId, item]));
  const seen = new Set<string>();
  let translationCount = 0;
  for (const [index, rawItem] of root.items.entries()) {
    const path = `items[${index}]`;
    const item = asRecord(rawItem);
    if (!item) {
      errors.push(`${path}: object required`);
      continue;
    }
    allowedKeys(item, ["documentId", "sourceContentVersion", "translations"], path, errors);
    if (typeof item.documentId !== "string") {
      errors.push(`${path}.documentId: string required`);
      continue;
    }
    if (seen.has(item.documentId)) errors.push(`${path}.documentId: duplicate`);
    seen.add(item.documentId);
    const sourceItem = sourceById.get(item.documentId);
    if (!sourceItem) {
      errors.push(`${path}.documentId: not present in source batch`);
      continue;
    }
    if (item.sourceContentVersion !== sourceItem.contentVersion) {
      errors.push(`${path}.sourceContentVersion: source version mismatch`);
    }
    const translations = asRecord(item.translations);
    if (!translations) {
      errors.push(`${path}.translations: object required`);
      continue;
    }
    for (const language of sourceItem.targetLanguages) {
      if (!(language in translations)) {
        errors.push(`${path}.translations.${language}: target locale result required`);
      }
    }
    for (const [language, rawTranslation] of Object.entries(translations)) {
      const translationPath = `${path}.translations.${language}`;
      if (!sourceItem.targetLanguages.includes(language as TranslationLanguage)) {
        errors.push(`${translationPath}: locale is not a target`);
        continue;
      }
      const translation = asRecord(rawTranslation);
      if (!translation) {
        errors.push(`${translationPath}: object required`);
        continue;
      }
      translationCount += 1;
      allowedKeys(translation, [
        "status", "title", "description", "category", "tags", "itemNames",
        "reviewRequired", "translationErrorCode",
        "cacheHit",
      ], translationPath, errors);
      if (!["completed", "failed", "review_required"].includes(String(translation.status))) {
        errors.push(`${translationPath}.status: unsupported status`);
        continue;
      }
      if (typeof translation.reviewRequired !== "boolean") {
        errors.push(`${translationPath}.reviewRequired: boolean required`);
      }
      if (translation.cacheHit !== undefined && typeof translation.cacheHit !== "boolean") {
        errors.push(`${translationPath}.cacheHit: boolean required`);
      }
      if ((translation.status === "review_required") !== (translation.reviewRequired === true)) {
        errors.push(`${translationPath}.reviewRequired: inconsistent with status`);
      }
      if (translation.status === "failed") {
        if (translation.translationErrorCode !== undefined) {
          validString(translation.translationErrorCode, `${translationPath}.translationErrorCode`, 100, errors);
        }
        continue;
      }
      validString(translation.title, `${translationPath}.title`, 300, errors);
      if (sourceItem.content.description !== undefined) {
        validString(translation.description, `${translationPath}.description`, 5000, errors);
      }
      if (sourceItem.content.category !== undefined) {
        validString(translation.category, `${translationPath}.category`, 200, errors);
      }
      if (sourceItem.content.tags !== undefined) {
        if (!Array.isArray(translation.tags) ||
            translation.tags.length !== sourceItem.content.tags.length) {
          errors.push(`${translationPath}.tags: matching string array required`);
        } else {
          translation.tags.forEach((tag, tagIndex) =>
            validString(tag, `${translationPath}.tags[${tagIndex}]`, 100, errors));
        }
      }
      if (sourceItem.content.itemNames !== undefined) {
        const itemNames = asRecord(translation.itemNames);
        const expectedIds = Object.keys(sourceItem.content.itemNames).sort();
        const actualIds = itemNames ? Object.keys(itemNames).sort() : [];
        if (JSON.stringify(expectedIds) !== JSON.stringify(actualIds)) {
          errors.push(`${translationPath}.itemNames: item IDs must match source`);
        } else if (itemNames) {
          for (const [itemId, name] of Object.entries(itemNames)) {
            validString(name, `${translationPath}.itemNames.${itemId}`, 300, errors);
          }
        }
      }
    }
  }
  for (const documentId of sourceById.keys()) {
    if (!seen.has(documentId)) {
      errors.push(`items: missing source document ${documentId}`);
    }
  }
  return {
    valid: errors.length === 0,
    errors,
    itemCount: root.items.length,
    translationCount,
  };
};

export const aggregateTranslationStatus = (
  statuses: LocaleTranslationStatus[],
): TopicTranslationStatus => {
  if (statuses.includes("review_required")) return "review_required";
  if (statuses.length > 0 && statuses.every((status) => status === "completed")) {
    return "completed";
  }
  if (statuses.length > 0 && statuses.every((status) => status === "failed")) {
    return "failed";
  }
  if (statuses.includes("completed")) return "partial";
  if (statuses.includes("processing")) return "processing";
  return "pending";
};
