import {
  parseSupportedLocale,
  SUPPORTED_LOCALES,
  SupportedLocale,
} from "./internationalization";

export const MIN_INDEXABLE_ITEMS = 3;

export type SeoExclusionReason =
  "private" |
  "unpublished" |
  "moderation" |
  "hidden" |
  "deleted" |
  "spam" |
  "duplicate" |
  "missing_title" |
  "unknown_item_count" |
  "too_few_items" |
  "unknown_source_locale" |
  "translation_incomplete" |
  "translation_review_required" |
  "translation_outdated";

export type SeoIndexability = {
  indexable: boolean;
  reason?: SeoExclusionReason;
};

const recordOf = (value: unknown): Record<string, unknown> | undefined =>
  typeof value === "object" && value !== null && !Array.isArray(value) ?
    value as Record<string, unknown> : undefined;

const nonEmptyText = (value: unknown): boolean =>
  typeof value === "string" && value.trim().length > 0;

const topicItemCount = (
  data: Record<string, unknown>,
  itemCountOverride?: number,
): number | undefined => {
  if (itemCountOverride !== undefined) return itemCountOverride;
  const count = data.itemCount;
  return typeof count === "number" && Number.isSafeInteger(count) && count >= 0 ?
    count : undefined;
};

export function baseTopicIndexability(
  data: Record<string, unknown>,
  itemCountOverride?: number,
): SeoIndexability {
  if (data.isPublic !== true) return {indexable: false, reason: "private"};
  if (typeof data.status === "string" && data.status !== "published") {
    return {indexable: false, reason: "unpublished"};
  }
  if (data.deleting === true || data.deleted === true || data.isDeleted === true ||
      data.deletedAt != null) {
    return {indexable: false, reason: "deleted"};
  }
  if (data.hidden === true || data.isHidden === true) {
    return {indexable: false, reason: "hidden"};
  }
  if (data.isSpam === true || data.spam === true) {
    return {indexable: false, reason: "spam"};
  }
  // moderationStatus未設定(モデレーション導入前からあるTier)はapproved扱い
  // にする。firestore.rulesのisPubliclyVisibleTopic()と判定基準を揃える。
  if (data.moderationStatus != null && data.moderationStatus !== "approved") {
    return {indexable: false, reason: "moderation"};
  }
  if (data.isDuplicate === true || nonEmptyText(data.duplicateOf)) {
    return {indexable: false, reason: "duplicate"};
  }
  if (!nonEmptyText(data.title)) {
    return {indexable: false, reason: "missing_title"};
  }
  const itemCount = topicItemCount(data, itemCountOverride);
  if (itemCount === undefined) {
    return {indexable: false, reason: "unknown_item_count"};
  }
  if (itemCount < MIN_INDEXABLE_ITEMS) {
    return {indexable: false, reason: "too_few_items"};
  }
  return {indexable: true};
}

export function sourceLocaleOf(
  data: Record<string, unknown>,
): SupportedLocale | undefined {
  return parseSupportedLocale(
    data.sourceLocale ?? data.sourceLanguage ?? data.contentLanguage,
  );
}

function translationForLocale(
  data: Record<string, unknown>,
  locale: SupportedLocale,
): Record<string, unknown> | undefined {
  const translations = recordOf(data.translations);
  if (!translations) return undefined;
  for (const [rawLocale, rawTranslation] of Object.entries(translations)) {
    if (parseSupportedLocale(rawLocale) === locale) {
      return recordOf(rawTranslation);
    }
  }
  return undefined;
}

export function localeTopicIndexability(
  data: Record<string, unknown>,
  locale: SupportedLocale,
  itemCountOverride?: number,
): SeoIndexability {
  const base = baseTopicIndexability(data, itemCountOverride);
  if (!base.indexable) return base;

  const sourceLocale = sourceLocaleOf(data);
  if (sourceLocale === undefined) {
    return {indexable: false, reason: "unknown_source_locale"};
  }
  if (locale === sourceLocale) return {indexable: true};

  const translation = translationForLocale(data, locale);
  if (!translation) {
    return {indexable: false, reason: "translation_incomplete"};
  }
  if (translation.status === "review_required" ||
      translation.reviewRequired === true ||
      translation.qualityStatus === "rejected") {
    return {indexable: false, reason: "translation_review_required"};
  }
  if (translation.manualTranslationOutdated === true) {
    return {indexable: false, reason: "translation_outdated"};
  }
  if (translation.status !== "completed" || !nonEmptyText(translation.title)) {
    return {indexable: false, reason: "translation_incomplete"};
  }
  const contentVersion = data.contentVersion;
  const translatedVersion = translation.sourceContentVersion;
  if (translation.translationMode !== "manual" &&
      typeof contentVersion === "number" &&
      translatedVersion !== contentVersion) {
    return {indexable: false, reason: "translation_outdated"};
  }
  const itemNames = recordOf(translation.itemNames);
  const translatedItems = itemNames == null ? 0 :
    Object.values(itemNames).filter(nonEmptyText).length;
  const requiredItems = topicItemCount(data, itemCountOverride) ??
    MIN_INDEXABLE_ITEMS;
  if (translatedItems < requiredItems) {
    return {indexable: false, reason: "translation_incomplete"};
  }
  return {indexable: true};
}

export function indexableTopicLocales(
  data: Record<string, unknown>,
  itemCountOverride?: number,
): SupportedLocale[] {
  return SUPPORTED_LOCALES.filter(
    (locale) => localeTopicIndexability(data, locale, itemCountOverride).indexable,
  );
}
