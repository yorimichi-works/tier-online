import {randomUUID} from "node:crypto";

import {firestoreLanguage} from "./internationalization";

export const MAX_CUSTOM_TAGS = 10;
export const MAX_CUSTOM_TAG_LENGTH = 30;

export type CustomTagTranslationStatus =
  "pending" | "translated" | "ambiguous" | "failed" | "manual";

export type CustomTagTranslation = {
  text: string | null;
  status: CustomTagTranslationStatus;
  confidence?: number;
};

export type CustomTag = {
  id: string;
  type: "custom";
  sourceText: string;
  sourceLocale: string;
  normalizedSourceText: string;
  translations: Record<string, CustomTagTranslation>;
};

const asRecord = (value: unknown): Record<string, unknown> | null =>
  typeof value === "object" && value !== null && !Array.isArray(value) ?
    value as Record<string, unknown> : null;

const validStatus = (value: unknown): value is CustomTagTranslationStatus =>
  value === "pending" || value === "translated" || value === "ambiguous" ||
  value === "failed" || value === "manual";

/** Normalization is exclusively for duplicate prevention and search. */
export const normalizeCustomTagText = (value: string): string =>
  value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLocaleLowerCase();

export const customTagsFromUnknown = (value: unknown): CustomTag[] => {
  if (!Array.isArray(value)) return [];
  const result: CustomTag[] = [];
  for (const rawTag of value) {
    const tag = asRecord(rawTag);
    if (!tag || typeof tag.id !== "string" || typeof tag.sourceText !== "string") {
      continue;
    }
    const sourceText = tag.sourceText.trim();
    const normalized = typeof tag.normalizedSourceText === "string" ?
      tag.normalizedSourceText : normalizeCustomTagText(sourceText);
    const translations: Record<string, CustomTagTranslation> = {};
    const rawTranslations = asRecord(tag.translations);
    if (rawTranslations) {
      for (const [locale, rawTranslation] of Object.entries(rawTranslations)) {
        const translation = asRecord(rawTranslation);
        if (!translation || !validStatus(translation.status)) continue;
        const text = typeof translation.text === "string" && translation.text.trim() ?
          translation.text.trim() : null;
        translations[locale] = {
          text,
          status: translation.status,
          ...(typeof translation.confidence === "number" &&
              translation.confidence >= 0 && translation.confidence <= 1 ?
            {confidence: translation.confidence} : {}),
        };
      }
    }
    if (sourceText.length === 0 || normalized.length === 0) continue;
    result.push({
      id: tag.id,
      type: "custom",
      sourceText,
      sourceLocale: typeof tag.sourceLocale === "string" ?
        firestoreLanguage(tag.sourceLocale) : "ja",
      normalizedSourceText: normalized,
      translations,
    });
  }
  return result;
};

const tagIdentity = (sourceLocale: string, normalizedSourceText: string): string =>
  `${sourceLocale}\u0000${normalizedSourceText}`;

/**
 * Converts the client-side string input into server-owned tag records. Matching
 * unchanged source tags retain their opaque IDs and manual translations. IDs
 * are deliberately random and are never derived from translated text.
 */
export const prepareCustomTags = (
  input: unknown,
  sourceLocaleInput: unknown,
  existingValue: unknown,
  makeId: () => string = () => `tag_${randomUUID()}`,
): CustomTag[] => {
  if (!Array.isArray(input)) return [];
  if (input.length > MAX_CUSTOM_TAGS) {
    throw new Error(`A Tier can have at most ${MAX_CUSTOM_TAGS} tags.`);
  }
  const sourceLocale = firestoreLanguage(sourceLocaleInput);
  const existing = customTagsFromUnknown(existingValue);
  const existingByIdentity = new Map(existing.map((tag) => [
    tagIdentity(tag.sourceLocale, tag.normalizedSourceText), tag,
  ]));
  const seen = new Set<string>();
  const result: CustomTag[] = [];
  for (const raw of input) {
    if (typeof raw !== "string") {
      throw new Error("Tags must be text.");
    }
    const sourceText = raw.trim();
    const normalizedSourceText = normalizeCustomTagText(sourceText);
    if (sourceText.length === 0 || normalizedSourceText.length === 0) continue;
    if (sourceText.length > MAX_CUSTOM_TAG_LENGTH) {
      throw new Error(`Each tag must be ${MAX_CUSTOM_TAG_LENGTH} characters or less.`);
    }
    const identity = tagIdentity(sourceLocale, normalizedSourceText);
    if (seen.has(identity)) continue;
    seen.add(identity);
    const existingTag = existingByIdentity.get(identity);
    result.push(existingTag ? {
      ...existingTag,
      sourceText,
      sourceLocale,
      normalizedSourceText,
    } : {
      id: makeId(),
      type: "custom",
      sourceText,
      sourceLocale,
      normalizedSourceText,
      translations: {},
    });
  }
  return result;
};

export const markCustomTagTranslationsPending = (
  tags: readonly CustomTag[],
  sourceLocaleInput: unknown,
): CustomTag[] => {
  const sourceLocale = firestoreLanguage(sourceLocaleInput);
  return tags.map((tag) => ({
    ...tag,
    translations: Object.fromEntries(Object.entries(tag.translations).map(
      ([locale, translation]) => [locale, locale === sourceLocale ||
          translation.status === "manual" ? translation : {
            text: null,
            status: "pending" as const,
          }],
    )),
  }));
};

/**
 * One-time compatibility bridge for old documents that only stored translated
 * positional `translations.{locale}.tags` arrays. It is used only while a
 * legacy document is first converted to structured tags; later updates use
 * tag IDs instead of positional matching.
 */
export const inheritLegacyTagTranslations = (
  tags: readonly CustomTag[],
  rawTranslations: unknown,
): CustomTag[] => {
  const translations = asRecord(rawTranslations);
  if (!translations) return [...tags];
  return tags.map((tag, index) => {
    const next = {...tag.translations};
    for (const [locale, rawLocale] of Object.entries(translations)) {
      const localeTranslation = asRecord(rawLocale);
      const legacyTags = localeTranslation?.tags;
      const legacyText = Array.isArray(legacyTags) &&
          typeof legacyTags[index] === "string" ? legacyTags[index].trim() : "";
      if (!legacyText || next[locale]) continue;
      next[locale] = {
        text: legacyText,
        status: localeTranslation?.translationMode === "manual" ? "manual" : "translated",
      };
    }
    return {...tag, translations: next};
  });
};

/** All source and usable translated labels. This is a search projection only. */
export const searchTagsFor = (tags: readonly CustomTag[]): string[] => {
  const values = new Set<string>();
  for (const tag of tags) {
    values.add(tag.sourceText);
    values.add(tag.normalizedSourceText);
    for (const translation of Object.values(tag.translations)) {
      if ((translation.status === "translated" || translation.status === "manual") &&
          translation.text?.trim()) {
        values.add(translation.text.trim());
      }
    }
  }
  return [...values];
};

export const customTagsNeedTranslation = (
  tags: readonly CustomTag[],
  language: string,
): boolean => tags.some((tag) => {
  if (tag.sourceLocale === language) return false;
  const translation = tag.translations[language];
  return translation === undefined || translation.status === "pending" ||
    translation.status === "failed";
});
