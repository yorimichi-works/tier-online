import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import test from "node:test";

import {
  DictionaryBundle,
  EnhancedSourceBatch,
  emptyTranslationCache,
  extractDictionaryContext,
  invalidateCacheEntry,
  mergeCachedAndCodexTranslations,
  prepareBatchWithDictionaryAndCache,
  translationCacheKey,
  updateExactCache,
} from "./phase1d";
import {SourceBatch, TranslatedBatch} from "./translationBatch";

const translations = (values: [string, string, string, string, string]) => ({
  ja: values[0],
  en: values[1],
  ko: values[2],
  "zh-TW": values[3],
  "pt-BR": values[4],
});

const dictionaries: DictionaryBundle = {
  common: {
    version: "tier-dict-v1",
    terms: {
      tier_list: {
        match: ["Tier", "Tier表"],
        translations: translations(["Tier表", "Tier List", "티어표", "Tier List", "Tier List"]),
      },
      unrelated: {
        match: ["参加する"],
        translations: translations(["参加する", "Join", "참여", "參加", "Participar"]),
      },
    },
  },
  official: {
    version: "official-v1",
    names: {
      genshin: {
        type: "work",
        match: ["原神", "Genshin Impact"],
        translations: translations(["原神", "Genshin Impact", "원신", "原神", "Genshin Impact"]),
      },
      unrelated: {
        type: "work",
        match: ["Pokémon"],
        translations: translations(["ポケモン", "Pokémon", "포켓몬", "寶可夢", "Pokémon"]),
      },
    },
    doNotTranslate: ["VALORANT", "YouTube"],
  },
};

const sourceBatch = (): SourceBatch => ({
  schemaVersion: 1,
  batchId: "tr_phase1d",
  createdAt: "2026-08-31T00:00:00.000Z",
  targetLanguages: ["en", "ko"],
  items: [{
    documentId: "topic-1",
    contentVersion: 4,
    sourceLanguage: "ja",
    targetLanguages: ["en", "ko"],
    context: {categoryId: "game"},
    content: {
      title: "原神 最強Tier",
      description: "キャラクターを評価",
      tags: ["原神"],
      itemNames: {a: "胡桃"},
    },
  }],
});

test("repository dictionaries cover every supported locale", () => {
  const dictionaryDirectory = resolve(
    __dirname,
    "../../../scripts/translation/dictionaries",
  );
  const common = JSON.parse(readFileSync(
    resolve(dictionaryDirectory, "common_terms.json"),
    "utf8",
  )) as DictionaryBundle["common"];
  const official = JSON.parse(readFileSync(
    resolve(dictionaryDirectory, "official_names.json"),
    "utf8",
  )) as DictionaryBundle["official"];
  const required = ["ja", "en", "ko", "zh-TW", "pt-BR"];
  for (const entry of [
    ...Object.values(common.terms),
    ...Object.values(official.names),
  ]) {
    assert.deepEqual(Object.keys(entry.translations).sort(), [...required].sort());
    assert.ok(entry.match.length > 0);
  }
});

const completedBatch = (
  source: EnhancedSourceBatch,
  reviewRequired = false,
): TranslatedBatch => ({
  schemaVersion: 1,
  batchId: source.batchId,
  items: source.items.map((item) => ({
    documentId: item.documentId,
    sourceContentVersion: item.contentVersion,
    translations: {
      en: {
        status: reviewRequired ? "review_required" : "completed",
        title: "Genshin Impact Strongest Tier List",
        description: "Character ranking",
        tags: ["Genshin Impact"],
        itemNames: {a: "Hu Tao"},
        reviewRequired,
      },
      ko: {
        status: "completed",
        title: "원신 최강 티어표",
        description: "캐릭터 평가",
        tags: ["원신"],
        itemNames: {a: "호두"},
        reviewRequired: false,
      },
    },
  })),
});

test("only matching common terms and official names enter the prompt context", () => {
  const context = extractDictionaryContext(sourceBatch().items[0].content, dictionaries);
  assert.deepEqual(Object.keys(context.commonTerms), ["tier_list"]);
  assert.deepEqual(Object.keys(context.officialNames), ["genshin"]);
  assert.deepEqual(context.doNotTranslate, []);
  assert.equal(context.officialNames.genshin.en, "Genshin Impact");
});

test("first run is a cache miss and second identical run is a cache hit", () => {
  const cache = emptyTranslationCache();
  const first = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  assert.equal(first.cacheHits, 0);
  assert.equal(first.codexTranslations, 2);
  assert.deepEqual(first.source.items[0].codexTargetLanguages, ["en", "ko"]);

  const translated = completedBatch(first.source);
  const stored = updateExactCache(
    first.source,
    translated,
    cache,
    new Set(["topic-1"]),
    new Set(),
    "2026-08-31T01:00:00.000Z",
  );
  assert.equal(stored.storedFields, 8);

  const second = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  assert.equal(second.cacheHits, 2);
  assert.equal(second.codexTranslations, 0);
  assert.deepEqual(second.source.items[0].codexTargetLanguages, []);
  assert.equal(second.cached.items[0].translations.en?.cacheHit, true);
});

test("invalid cache and changed versions are not reused", () => {
  const cache = emptyTranslationCache();
  const prepared = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  updateExactCache(
    prepared.source,
    completedBatch(prepared.source),
    cache,
    new Set(["topic-1"]),
  );
  const key = Object.keys(cache.entries)[0];
  assert.equal(invalidateCacheEntry(cache, key), true);
  const invalid = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  assert.equal(invalid.cacheHits, 1);
  assert.equal(invalid.codexTranslations, 1);
  const baseline = translationCacheKey({
    field: "title",
    sourceText: "same",
    sourceLanguage: "ja",
    targetLanguage: "en",
  });
  const changedPrompt = translationCacheKey({
    field: "title",
    sourceText: "same",
    sourceLanguage: "ja",
    targetLanguage: "en",
    promptVersion: "different",
  });
  const changedDictionary = translationCacheKey({
    field: "title",
    sourceText: "same",
    sourceLanguage: "ja",
    targetLanguage: "en",
    dictionaryVersion: "different",
  });
  assert.notEqual(baseline, changedPrompt);
  assert.notEqual(baseline, changedDictionary);
});

test("review-required results and manual-skipped locales do not enter cache", () => {
  const cache = emptyTranslationCache();
  const prepared = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  const translated = completedBatch(prepared.source, true);
  const result = updateExactCache(
    prepared.source,
    translated,
    cache,
    new Set(["topic-1"]),
    new Set(["topic-1\u0000ko"]),
  );
  assert.equal(result.storedFields, 0);
  assert.deepEqual(cache.entries, {});
});

test("cached and Codex locales merge without allowing overlap or forged cache hits", () => {
  const cache = emptyTranslationCache();
  const first = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  const all = completedBatch(first.source);
  updateExactCache(first.source, {
    ...all,
    items: [{...all.items[0], translations: {en: all.items[0].translations.en}}],
  }, cache, new Set(["topic-1"]));
  const second = prepareBatchWithDictionaryAndCache(sourceBatch(), dictionaries, cache);
  assert.deepEqual(second.source.items[0].codexTargetLanguages, ["ko"]);
  const codex: TranslatedBatch = {
    schemaVersion: 1,
    batchId: second.source.batchId,
    items: [{
      documentId: "topic-1",
      sourceContentVersion: 4,
      translations: {ko: all.items[0].translations.ko},
    }],
  };
  const merged = mergeCachedAndCodexTranslations(second.source, second.cached, codex);
  assert.equal(merged.items[0].translations.en?.cacheHit, true);
  assert.equal(merged.items[0].translations.ko?.cacheHit, undefined);

  codex.items[0].translations.ko!.cacheHit = true;
  assert.throws(
    () => mergeCachedAndCodexTranslations(second.source, second.cached, codex),
    /Codex cannot set cacheHit/,
  );
});
