import assert from "node:assert/strict";
import test from "node:test";

import {
  CustomTag,
  customTagsNeedTranslation,
  markCustomTagTranslationsPending,
  prepareCustomTags,
  searchTagsFor,
} from "./customTags";

const ids = (...values: string[]) => {
  let index = 0;
  return () => values[index++];
};

test("source tags retain separate opaque IDs when translations collide", () => {
  const tags = prepareCustomTags(
    ["理想", "以上", "異常"],
    "ja",
    [],
    ids("tag_ideal", "tag_over", "tag_abnormal"),
  ).map((tag) => ({
    ...tag,
    translations: {
      ko: {text: "이상", status: "translated" as const},
    },
  }));
  assert.deepEqual(tags.map((tag) => tag.id), [
    "tag_ideal",
    "tag_over",
    "tag_abnormal",
  ]);
  assert.equal(new Set(tags.map((tag) => tag.translations.ko.text)).size, 1);
  assert.deepEqual(searchTagsFor(tags), ["理想", "이상", "以上", "異常"]);
});

test("duplicate prevention uses normalized source text, not translated text", () => {
  const tags = prepareCustomTags(
    [" 理想 ", "理想", "異常"],
    "ja",
    [],
    ids("tag_ideal", "tag_abnormal"),
  );
  assert.deepEqual(tags.map((tag) => tag.sourceText), ["理想", "異常"]);
  assert.deepEqual(tags.map((tag) => tag.id), ["tag_ideal", "tag_abnormal"]);
});

test("ambiguous translations fall back to source text and remain pending only when needed", () => {
  const tags: CustomTag[] = prepareCustomTags(["以上"], "ja", [], ids("tag_over"));
  tags[0].translations.ko = {text: null, status: "ambiguous"};
  assert.equal(customTagsNeedTranslation(tags, "ko"), false);
  assert.equal(customTagsNeedTranslation(tags, "en"), true);
  assert.equal(tags[0].translations.ko.text ?? tags[0].sourceText, "以上");
});

test("edits create a new source tag while unchanged IDs and manual labels survive", () => {
  const initial = prepareCustomTags(["理想"], "ja", [], ids("tag_original"));
  initial[0].translations.en = {text: "ideal", status: "manual"};
  const unchanged = prepareCustomTags(["理想"], "ja", initial, ids("unused"));
  assert.equal(unchanged[0].id, "tag_original");
  assert.equal(unchanged[0].translations.en.status, "manual");

  const edited = prepareCustomTags(["理想の恋人"], "ja", unchanged, ids("tag_edited"));
  assert.equal(edited[0].id, "tag_edited");
  assert.deepEqual(edited[0].translations, {});

  const invalidated = markCustomTagTranslationsPending(unchanged, "ja");
  assert.equal(invalidated[0].translations.en.status, "manual");
});
