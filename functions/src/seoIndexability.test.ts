import assert from "node:assert/strict";
import test from "node:test";

import {
  baseTopicIndexability,
  localeTopicIndexability,
  MIN_INDEXABLE_ITEMS,
} from "./seoIndexability";

const sourceTopic = (): Record<string, unknown> => ({
  isPublic: true,
  moderationStatus: "approved",
  title: "朝ごはんTier",
  itemCount: MIN_INDEXABLE_ITEMS,
  sourceLocale: "ja",
  contentVersion: 2,
});

const completedTranslation = () => ({
  status: "completed",
  reviewRequired: false,
  title: "Breakfast Tier",
  sourceContentVersion: 2,
  translationMode: "auto",
  itemNames: {one: "Eggs", two: "Toast", three: "Fruit"},
});

test("public approved topics with enough items are indexable", () => {
  assert.deepEqual(baseTopicIndexability(sourceTopic()), {indexable: true});
  assert.equal(localeTopicIndexability(sourceTopic(), "ja").indexable, true);
});

test("private, pending, hidden, deleted and thin topics are noindex", () => {
  assert.equal(baseTopicIndexability({...sourceTopic(), isPublic: false}).reason, "private");
  assert.equal(
    baseTopicIndexability({...sourceTopic(), moderationStatus: "flagged"}).reason,
    "moderation",
  );
  assert.equal(baseTopicIndexability({...sourceTopic(), hidden: true}).reason, "hidden");
  assert.equal(baseTopicIndexability({...sourceTopic(), deleted: true}).reason, "deleted");
  assert.equal(baseTopicIndexability({...sourceTopic(), itemCount: 2}).reason, "too_few_items");
  assert.equal(
    baseTopicIndexability({...sourceTopic(), itemCount: undefined}).reason,
    "unknown_item_count",
  );
});

test("locale indexability follows translation completion and review state", () => {
  const incomplete = sourceTopic();
  assert.equal(
    localeTopicIndexability(incomplete, "en").reason,
    "translation_incomplete",
  );

  const reviewRequired = {
    ...sourceTopic(),
    translations: {
      en: {...completedTranslation(), status: "review_required", reviewRequired: true},
    },
  };
  assert.equal(
    localeTopicIndexability(reviewRequired, "en").reason,
    "translation_review_required",
  );

  const completed = {
    ...sourceTopic(),
    translations: {en: completedTranslation()},
  };
  assert.deepEqual(
    localeTopicIndexability(completed, "en"),
    {indexable: true},
  );

  const unsupportedLocaleKey = {
    ...sourceTopic(),
    translations: {fr: completedTranslation()},
  };
  assert.equal(
    localeTopicIndexability(unsupportedLocaleKey, "en").reason,
    "translation_incomplete",
  );
});

test("outdated automatic translation is noindex and current manual translation can index", () => {
  const outdated = {
    ...sourceTopic(),
    translations: {
      en: {...completedTranslation(), sourceContentVersion: 1},
    },
  };
  assert.equal(
    localeTopicIndexability(outdated, "en").reason,
    "translation_outdated",
  );

  const manual = {
    ...sourceTopic(),
    translations: {
      en: {
        ...completedTranslation(),
        translationMode: "manual",
        qualityStatus: "reviewed",
      },
    },
  };
  assert.equal(localeTopicIndexability(manual, "en").indexable, true);
});
