import {createHash} from "node:crypto";

import {
  DEFAULT_PROMPT_VERSION,
  DEFAULT_TRANSLATION_VERSION,
  SourceBatch,
  SourceBatchItem,
  SourceContent,
  TranslatedBatch,
  TranslatedLocale,
  TranslationLanguage,
  validateTranslatedBatch,
} from "./translationBatch";

export const DEFAULT_DICTIONARY_VERSION = "tier-dict-v1+official-names-v1";

type DictionaryTranslations = Record<TranslationLanguage, string>;

export type CommonTermsDictionary = {
  version: string;
  terms: Record<string, {
    match: string[];
    translations: DictionaryTranslations;
  }>;
};

export type OfficialNamesDictionary = {
  version: string;
  names: Record<string, {
    type: string;
    match: string[];
    translations: DictionaryTranslations;
  }>;
  doNotTranslate: string[];
};

export type DictionaryBundle = {
  common: CommonTermsDictionary;
  official: OfficialNamesDictionary;
};

export type TranslationDictionaryContext = {
  dictionaryVersion: string;
  commonTerms: Record<string, DictionaryTranslations>;
  officialNames: Record<string, DictionaryTranslations & {type: string}>;
  doNotTranslate: string[];
};

export type TranslationCacheEntry = {
  key: string;
  field: string;
  sourceLanguage: TranslationLanguage;
  targetLanguage: TranslationLanguage;
  sourceTextHash: string;
  translation: string;
  translationVersion: number;
  promptVersion: string;
  dictionaryVersion: string;
  isValid: boolean;
  createdAt: string;
  lastUsedAt: string;
  hitCount: number;
};

export type TranslationCache = {
  schemaVersion: 1;
  entries: Record<string, TranslationCacheEntry>;
};

export const emptyTranslationCache = (): TranslationCache => ({
  schemaVersion: 1,
  entries: {},
});

const normalizeCacheText = (text: string): string =>
  text.trim().replace(/\r\n?/g, "\n");

const hashText = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

export const translationCacheKey = (input: {
  field: string;
  sourceText: string;
  sourceLanguage: TranslationLanguage;
  targetLanguage: TranslationLanguage;
  translationVersion?: number;
  promptVersion?: string;
  dictionaryVersion?: string;
}): string => {
  const field = input.field.startsWith("tags.") ? "tag" :
    input.field.startsWith("itemNames.") ? "itemName" : input.field;
  const canonical = JSON.stringify({
    field,
    sourceText: normalizeCacheText(input.sourceText),
    sourceLanguage: input.sourceLanguage,
    targetLanguage: input.targetLanguage,
    translationVersion: input.translationVersion ?? DEFAULT_TRANSLATION_VERSION,
    promptVersion: input.promptVersion ?? DEFAULT_PROMPT_VERSION,
    dictionaryVersion: input.dictionaryVersion ?? DEFAULT_DICTIONARY_VERSION,
  });
  return createHash("sha256").update(canonical).digest("hex");
};

const sourceStrings = (content: SourceContent): string[] => [
  content.title,
  content.description,
  content.category,
  ...(content.tags ?? []),
  ...Object.values(content.itemNames ?? {}),
].filter((value): value is string => typeof value === "string");

const includesAny = (haystack: string, needles: string[]): boolean => {
  const normalized = haystack.toLocaleLowerCase();
  return needles.some((needle) => normalized.includes(needle.toLocaleLowerCase()));
};

export const extractDictionaryContext = (
  content: SourceContent,
  dictionaries: DictionaryBundle,
): TranslationDictionaryContext => {
  const text = sourceStrings(content).join("\n");
  const commonTerms = Object.fromEntries(Object.entries(dictionaries.common.terms)
    .filter(([, entry]) => includesAny(text, entry.match))
    .map(([key, entry]) => [key, entry.translations]));
  const officialNames = Object.fromEntries(Object.entries(dictionaries.official.names)
    .filter(([, entry]) => includesAny(text, entry.match))
    .map(([key, entry]) => [key, {type: entry.type, ...entry.translations}]));
  return {
    dictionaryVersion: `${dictionaries.common.version}+${dictionaries.official.version}`,
    commonTerms,
    officialNames,
    doNotTranslate: dictionaries.official.doNotTranslate
      .filter((name) => includesAny(text, [name])),
  };
};

type TextField = {path: string; sourceText: string};

const sourceFields = (content: SourceContent): TextField[] => [
  {path: "title", sourceText: content.title},
  ...(content.description === undefined ? [] :
    [{path: "description", sourceText: content.description}]),
  ...(content.category === undefined ? [] :
    [{path: "category", sourceText: content.category}]),
  ...(content.tags ?? []).map((sourceText, index) => ({
    path: `tags.${index}`,
    sourceText,
  })),
  ...Object.entries(content.itemNames ?? {}).map(([id, sourceText]) => ({
    path: `itemNames.${id}`,
    sourceText,
  })),
];

const translatedTextAt = (
  translation: TranslatedLocale,
  path: string,
): string | undefined => {
  if (path === "title" || path === "description" || path === "category") {
    return translation[path];
  }
  if (path.startsWith("tags.")) {
    return translation.tags?.[Number(path.slice(5))];
  }
  if (path.startsWith("itemNames.")) {
    return translation.itemNames?.[path.slice(10)];
  }
  return undefined;
};

const localeFromCachedFields = (
  content: SourceContent,
  values: Map<string, string>,
): TranslatedLocale => ({
  status: "completed",
  title: values.get("title"),
  ...(content.description === undefined ? {} :
    {description: values.get("description")}),
  ...(content.category === undefined ? {} :
    {category: values.get("category")}),
  ...(content.tags === undefined ? {} : {
    tags: content.tags.map((_, index) => values.get(`tags.${index}`) ?? ""),
  }),
  ...(content.itemNames === undefined ? {} : {
    itemNames: Object.fromEntries(Object.keys(content.itemNames).map((id) => [
      id,
      values.get(`itemNames.${id}`) ?? "",
    ])),
  }),
  reviewRequired: false,
  cacheHit: true,
});

export type EnhancedSourceBatchItem = SourceBatchItem & {
  codexTargetLanguages: TranslationLanguage[];
  translationContext: TranslationDictionaryContext;
};

export type EnhancedSourceBatch = Omit<SourceBatch, "items"> & {
  items: EnhancedSourceBatchItem[];
};

export const prepareBatchWithDictionaryAndCache = (
  source: SourceBatch,
  dictionaries: DictionaryBundle,
  cache: TranslationCache,
  now = new Date().toISOString(),
): {
  source: EnhancedSourceBatch;
  cached: TranslatedBatch;
  cacheHits: number;
  codexTranslations: number;
} => {
  const cachedItems: TranslatedBatch["items"] = [];
  let cacheHits = 0;
  let codexTranslations = 0;
  const enhancedItems = source.items.map((item) => {
    const context = extractDictionaryContext(item.content, dictionaries);
    const cachedTranslations: Partial<Record<TranslationLanguage, TranslatedLocale>> = {};
    const codexTargetLanguages: TranslationLanguage[] = [];
    for (const targetLanguage of item.targetLanguages) {
      const values = new Map<string, string>();
      let complete = true;
      for (const field of sourceFields(item.content)) {
        const key = translationCacheKey({
          field: field.path,
          sourceText: field.sourceText,
          sourceLanguage: item.sourceLanguage,
          targetLanguage,
          dictionaryVersion: context.dictionaryVersion,
        });
        const entry = cache.entries[key];
        if (!entry?.isValid) {
          complete = false;
          break;
        }
        values.set(field.path, entry.translation);
      }
      if (complete) {
        cachedTranslations[targetLanguage] = localeFromCachedFields(item.content, values);
        cacheHits += 1;
        for (const field of sourceFields(item.content)) {
          const key = translationCacheKey({
            field: field.path,
            sourceText: field.sourceText,
            sourceLanguage: item.sourceLanguage,
            targetLanguage,
            dictionaryVersion: context.dictionaryVersion,
          });
          cache.entries[key].lastUsedAt = now;
          cache.entries[key].hitCount += 1;
        }
      } else {
        codexTargetLanguages.push(targetLanguage);
        codexTranslations += 1;
      }
    }
    if (Object.keys(cachedTranslations).length > 0) {
      cachedItems.push({
        documentId: item.documentId,
        sourceContentVersion: item.contentVersion,
        translations: cachedTranslations,
      });
    }
    return {
      ...item,
      codexTargetLanguages,
      translationContext: context,
    };
  });
  return {
    source: {...source, items: enhancedItems},
    cached: {
      schemaVersion: 1,
      batchId: source.batchId,
      items: cachedItems,
    },
    cacheHits,
    codexTranslations,
  };
};

const itemMap = (batch: TranslatedBatch): Map<string, TranslatedBatch["items"][number]> =>
  new Map(batch.items.map((item) => [item.documentId, item]));

export const mergeCachedAndCodexTranslations = (
  source: EnhancedSourceBatch,
  cached: TranslatedBatch,
  codex: TranslatedBatch,
): TranslatedBatch => {
  if (cached.batchId !== source.batchId || codex.batchId !== source.batchId) {
    throw new Error("batchId mismatch while merging translation results");
  }
  const cachedById = itemMap(cached);
  const codexById = itemMap(codex);
  const result: TranslatedBatch = {
    schemaVersion: 1,
    batchId: source.batchId,
    items: source.items.map((item) => {
      const cachedItem = cachedById.get(item.documentId);
      const codexItem = codexById.get(item.documentId);
      if (cachedItem && cachedItem.sourceContentVersion !== item.contentVersion) {
        throw new Error(`${item.documentId}: cached content version mismatch`);
      }
      if (codexItem && codexItem.sourceContentVersion !== item.contentVersion) {
        throw new Error(`${item.documentId}: Codex content version mismatch`);
      }
      const cachedTranslations = cachedItem?.translations ?? {};
      const codexTranslations = codexItem?.translations ?? {};
      for (const language of Object.keys(codexTranslations)) {
        if (!item.codexTargetLanguages.includes(language as TranslationLanguage)) {
          throw new Error(`${item.documentId}.${language}: not a Codex target`);
        }
        if (cachedTranslations[language as TranslationLanguage]) {
          throw new Error(`${item.documentId}.${language}: cache/Codex overlap`);
        }
        if (codexTranslations[language as TranslationLanguage]?.cacheHit === true) {
          throw new Error(`${item.documentId}.${language}: Codex cannot set cacheHit`);
        }
      }
      for (const [language, translation] of Object.entries(cachedTranslations)) {
        if (translation?.status !== "completed" || translation.cacheHit !== true ||
            translation.reviewRequired) {
          throw new Error(`${item.documentId}.${language}: invalid cached translation`);
        }
      }
      return {
        documentId: item.documentId,
        sourceContentVersion: item.contentVersion,
        translations: {...cachedTranslations, ...codexTranslations},
      };
    }),
  };
  const report = validateTranslatedBatch(source, result);
  if (!report.valid) {
    throw new Error(`Merged translation validation failed:\n${report.errors.join("\n")}`);
  }
  return result;
};

const containsSensitiveText = (text: string): boolean =>
  /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i.test(text) ||
  /(?:https?:\/\/|www\.)/i.test(text) ||
  /(?:\+?\d[\d\s().-]{8,}\d)/.test(text);

export const updateExactCache = (
  source: EnhancedSourceBatch,
  translated: TranslatedBatch,
  cache: TranslationCache,
  importedDocumentIds: Set<string>,
  skippedManual: Set<string> = new Set(),
  now = new Date().toISOString(),
): {storedFields: number} => {
  let storedFields = 0;
  const translatedById = itemMap(translated);
  for (const item of source.items) {
    if (!importedDocumentIds.has(item.documentId)) continue;
    const result = translatedById.get(item.documentId);
    if (!result) continue;
    for (const [language, translation] of Object.entries(result.translations)) {
      if (skippedManual.has(`${item.documentId}\u0000${language}`)) continue;
      if (!translation || translation.status !== "completed" ||
          translation.reviewRequired || translation.cacheHit) continue;
      const targetLanguage = language as TranslationLanguage;
      for (const field of sourceFields(item.content)) {
        if (containsSensitiveText(field.sourceText)) continue;
        const translatedText = translatedTextAt(translation, field.path);
        if (!translatedText?.trim()) continue;
        const key = translationCacheKey({
          field: field.path,
          sourceText: field.sourceText,
          sourceLanguage: item.sourceLanguage,
          targetLanguage,
          dictionaryVersion: item.translationContext?.dictionaryVersion ??
            DEFAULT_DICTIONARY_VERSION,
        });
        cache.entries[key] = {
          key,
          field: field.path,
          sourceLanguage: item.sourceLanguage,
          targetLanguage,
          sourceTextHash: hashText(normalizeCacheText(field.sourceText)),
          translation: translatedText,
          translationVersion: DEFAULT_TRANSLATION_VERSION,
          promptVersion: DEFAULT_PROMPT_VERSION,
          dictionaryVersion: item.translationContext?.dictionaryVersion ??
            DEFAULT_DICTIONARY_VERSION,
          isValid: true,
          createdAt: cache.entries[key]?.createdAt ?? now,
          lastUsedAt: now,
          hitCount: cache.entries[key]?.hitCount ?? 0,
        };
        storedFields += 1;
      }
    }
  }
  return {storedFields};
};

export const invalidateCacheEntry = (
  cache: TranslationCache,
  key: string,
): boolean => {
  const entry = cache.entries[key];
  if (!entry) return false;
  entry.isValid = false;
  return true;
};
