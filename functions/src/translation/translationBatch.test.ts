import assert from "node:assert/strict";
import test from "node:test";

import {importTranslatedBatch} from "./firestoreBatch";
import {DEFAULT_DICTIONARY_VERSION} from "./phase1d";
import {
  DEFAULT_PROMPT_VERSION,
  DEFAULT_TRANSLATION_VERSION,
  SourceBatch,
  TRANSLATION_LANGUAGES,
  TranslatedBatch,
  aggregateTranslationStatus,
  isTranslationCandidate,
  pendingTranslationsAfterSourceChange,
  pendingTranslationsAfterStaleBatch,
  sourceFingerprint,
  targetLanguagesFor,
  validateTranslatedBatch,
} from "./translationBatch";

type FakeTopic = Record<string, unknown>;

const fakeFirestore = (topics: Record<string, FakeTopic>) => {
  let writes = 0;
  const firestore = {
    collection: (name: string) => {
      assert.equal(name, "topics");
      return {
        doc: (id: string) => ({id}),
      };
    },
    runTransaction: async <T>(callback: (transaction: {
      get: (reference: {id: string}) => Promise<{
        exists: boolean;
        data: () => FakeTopic | undefined;
      }>;
      set: (
        reference: {id: string},
        value: FakeTopic,
        options: {merge: boolean},
      ) => void;
    }) => Promise<T>): Promise<T> => callback({
      get: async (reference) => ({
        exists: topics[reference.id] !== undefined,
        data: () => topics[reference.id],
      }),
      set: (reference, value, options) => {
        assert.equal(options.merge, true);
        writes += 1;
        topics[reference.id] = {...topics[reference.id], ...value};
      },
    }),
  };
  return {
    firestore: firestore as never,
    get writes() {
      return writes;
    },
  };
};

const baseTopic = (sourceLanguage = "ja"): Record<string, unknown> => ({
  isPublic: true,
  moderationStatus: "approved",
  translationStatus: "pending",
  contentVersion: 3,
  sourceLanguage,
  title: "おいしいパスタTier",
});

test("only approved public pending UGC becomes a candidate", () => {
  assert.equal(isTranslationCandidate(baseTopic()), true);
  assert.equal(isTranslationCandidate({...baseTopic(), isPublic: false}), false);
  assert.equal(isTranslationCandidate({...baseTopic(), moderationStatus: "flagged"}), false);
  assert.equal(isTranslationCandidate({...baseTopic(), translationStatus: "processing"}), false);
});

test("source, current completed, manual, and processing locales are skipped", () => {
  const topic = {
    ...baseTopic("ja"),
    translations: {
      en: {status: "completed", sourceContentVersion: 3, translationMode: "auto"},
      ko: {status: "completed", sourceContentVersion: 2, translationMode: "auto"},
      "zh-TW": {status: "completed", sourceContentVersion: 2, translationMode: "manual"},
      "pt-BR": {status: "processing", sourceContentVersion: 3, translationMode: "auto"},
    },
  };
  assert.deepEqual(targetLanguagesFor(topic), ["ko"]);
});

test("source edits invalidate auto translations but preserve manual translations", () => {
  const next = pendingTranslationsAfterSourceChange({
    translations: {
      en: {status: "completed", translationMode: "auto"},
      ko: {status: "completed", translationMode: "manual"},
    },
  });
  assert.equal((next.en as Record<string, unknown>).status, "pending");
  assert.equal((next.ko as Record<string, unknown>).status, "completed");
  assert.equal(
    (next.ko as Record<string, unknown>).manualTranslationOutdated,
    true,
  );
});

test("source fingerprint changes only when translatable source changes", () => {
  const first = sourceFingerprint(baseTopic(), [{id: "a", name: "カルボナーラ"}]);
  const same = sourceFingerprint(baseTopic(), [{id: "a", name: "カルボナーラ"}]);
  const changed = sourceFingerprint(baseTopic(), [{id: "a", name: "ボロネーゼ"}]);
  assert.equal(first, same);
  assert.notEqual(first, changed);
});

const makeSourceBatch = (): SourceBatch => ({
  schemaVersion: 1,
  batchId: "tr_test",
  createdAt: "2026-08-30T00:00:00.000Z",
  targetLanguages: [...TRANSLATION_LANGUAGES],
  items: TRANSLATION_LANGUAGES.map((sourceLanguage, index) => ({
    documentId: `topic-${sourceLanguage}`,
    contentVersion: index + 1,
    sourceLanguage,
    targetLanguages: TRANSLATION_LANGUAGES.filter((language) => language !== sourceLanguage),
    context: {categoryId: "food"},
    content: {
      title: `title-${sourceLanguage}`,
      description: `description-${sourceLanguage}`,
      category: "food",
      tags: ["pasta"],
      itemNames: {card1: "Carbonara"},
    },
  })),
});

const makeTranslatedBatch = (source: SourceBatch): TranslatedBatch => ({
  schemaVersion: 1,
  batchId: source.batchId,
  items: source.items.map((item) => ({
    documentId: item.documentId,
    sourceContentVersion: item.contentVersion,
    translations: Object.fromEntries(item.targetLanguages.map((language) => [language, {
      status: "completed",
      title: `translated-${language}`,
      description: `translated-description-${language}`,
      category: `translated-category-${language}`,
      tags: [`translated-tag-${language}`],
      itemNames: {card1: `translated-card-${language}`},
      reviewRequired: false,
    }])),
  })),
});

test("all five source languages validate with at most four target languages", () => {
  const source = makeSourceBatch();
  const translated = makeTranslatedBatch(source);
  const report = validateTranslatedBatch(source, translated);
  assert.equal(report.valid, true, report.errors.join("\n"));
  assert.equal(report.itemCount, 5);
  assert.equal(report.translationCount, 20);
});

test("validation rejects batch, version, ID, locale, unknown field, and empty text", () => {
  const source = makeSourceBatch();
  const translated = makeTranslatedBatch(source) as unknown as Record<string, unknown>;
  translated.batchId = "wrong";
  const items = translated.items as Array<Record<string, unknown>>;
  items[0].documentId = "invented-id";
  items[1].sourceContentVersion = 999;
  const translations = items[2].translations as Record<string, Record<string, unknown>>;
  translations["unsupported"] = {
    status: "completed",
    title: "x",
    reviewRequired: false,
  };
  const firstTranslation = Object.values(
    items[3].translations as Record<string, Record<string, unknown>>,
  )[0];
  firstTranslation.title = "";
  firstTranslation.invented = "not allowed";
  const report = validateTranslatedBatch(source, translated);
  assert.equal(report.valid, false);
  assert.ok(report.errors.some((error) => error.includes("batchId")));
  assert.ok(report.errors.some((error) => error.includes("not present in source")));
  assert.ok(report.errors.some((error) => error.includes("source version mismatch")));
  assert.ok(report.errors.some((error) => error.includes("not a target")));
  assert.ok(report.errors.some((error) => error.includes("unknown field")));
  assert.ok(report.errors.some((error) => error.includes("non-empty string")));
});

test("partial, review-required, failed, and completed top statuses are deterministic", () => {
  assert.equal(aggregateTranslationStatus(["completed", "completed"]), "completed");
  assert.equal(aggregateTranslationStatus(["completed", "failed"]), "partial");
  assert.equal(aggregateTranslationStatus(["failed", "failed"]), "failed");
  assert.equal(aggregateTranslationStatus(["completed", "review_required"]), "review_required");
});

test("stale processing reset affects only the matching batch and is idempotent", () => {
  const data = {
    translations: {
      en: {status: "processing", batchId: "tr_old", translationMode: "auto"},
      ko: {status: "processing", batchId: "tr_other", translationMode: "auto"},
      "zh-TW": {status: "completed", batchId: "tr_old", translationMode: "manual"},
    },
  };
  const once = pendingTranslationsAfterStaleBatch(data, "tr_old");
  const twice = pendingTranslationsAfterStaleBatch({translations: once}, "tr_old");
  assert.equal((once.en as Record<string, unknown>).status, "pending");
  assert.equal((once.ko as Record<string, unknown>).status, "processing");
  assert.equal((once["zh-TW"] as Record<string, unknown>).status, "completed");
  assert.deepEqual(twice, once);
});

test("import dry-run does not write and a repeated import is idempotent", async () => {
  const source: SourceBatch = {
    schemaVersion: 1,
    batchId: "tr_import",
    createdAt: "2026-08-30T00:00:00.000Z",
    targetLanguages: ["en", "ko", "zh-TW", "pt-BR"],
    items: [{
      documentId: "topic-ja",
      contentVersion: 3,
      sourceLanguage: "ja",
      targetLanguages: ["en", "ko", "zh-TW", "pt-BR"],
      context: {},
      content: {title: "パスタTier"},
    }],
  };
  const translated: TranslatedBatch = {
    schemaVersion: 1,
    batchId: source.batchId,
    items: [{
      documentId: "topic-ja",
      sourceContentVersion: 3,
      translations: Object.fromEntries(source.items[0].targetLanguages.map((language) => [
        language,
        {
          status: "completed",
          title: `pasta-${language}`,
          reviewRequired: false,
        },
      ])),
    }],
  };
  const topics = {
    "topic-ja": {
      isPublic: true,
      moderationStatus: "approved",
      sourceLanguage: "ja",
      contentVersion: 3,
      translationStatus: "processing",
      translationBatchId: source.batchId,
    },
  };
  const fake = fakeFirestore(topics);
  const dryRun = await importTranslatedBatch(fake.firestore, source, translated, true);
  assert.equal(fake.writes, 0);
  assert.deepEqual(dryRun.updated, [{documentId: "topic-ja", status: "completed"}]);

  const imported = await importTranslatedBatch(fake.firestore, source, translated, false);
  assert.equal(fake.writes, 1);
  assert.equal(imported.statusCounts.completed, 1);
  assert.deepEqual(imported.translationStats, {
    total: 4,
    cacheHits: 0,
    codexTranslations: 4,
    manualSkipped: 0,
    failed: 0,
    reviewRequired: 0,
  });
  const storedEnglish = (
    (topics["topic-ja"] as Record<string, unknown>).translations as
      Record<string, Record<string, unknown>>
  ).en;
  assert.equal(storedEnglish.translationVersion, DEFAULT_TRANSLATION_VERSION);
  assert.equal(storedEnglish.promptVersion, DEFAULT_PROMPT_VERSION);
  assert.equal(storedEnglish.dictionaryVersion, DEFAULT_DICTIONARY_VERSION);
  const repeated = await importTranslatedBatch(fake.firestore, source, translated, false);
  assert.deepEqual(repeated.idempotent, ["topic-ja"]);
  assert.equal(fake.writes, 1);
});

test("import rejects a changed source version and protects manual translations", async () => {
  const source: SourceBatch = {
    schemaVersion: 1,
    batchId: "tr_guard",
    createdAt: "2026-08-30T00:00:00.000Z",
    targetLanguages: ["en"],
    items: [{
      documentId: "changed",
      contentVersion: 1,
      sourceLanguage: "ja",
      targetLanguages: ["en"],
      context: {},
      content: {title: "原文"},
    }, {
      documentId: "manual",
      contentVersion: 1,
      sourceLanguage: "ja",
      targetLanguages: ["en"],
      context: {},
      content: {title: "原文"},
    }],
  };
  const translated: TranslatedBatch = {
    schemaVersion: 1,
    batchId: source.batchId,
    items: source.items.map((item) => ({
      documentId: item.documentId,
      sourceContentVersion: 1,
      translations: {
        en: {status: "completed", title: "Source", reviewRequired: false},
      },
    })),
  };
  const topics = {
    changed: {
      isPublic: true,
      moderationStatus: "approved",
      sourceLanguage: "ja",
      contentVersion: 2,
      translationStatus: "processing",
      translationBatchId: source.batchId,
    },
    manual: {
      isPublic: true,
      moderationStatus: "approved",
      sourceLanguage: "ja",
      contentVersion: 1,
      translationStatus: "processing",
      translationBatchId: source.batchId,
      translations: {
        en: {
          status: "completed",
          title: "Human translation",
          reviewRequired: false,
          sourceContentVersion: 1,
          translationVersion: 1,
          promptVersion: "manual",
          translationProvider: "human",
          translationMode: "manual",
        },
      },
    },
  };
  const fake = fakeFirestore(topics);
  const report = await importTranslatedBatch(fake.firestore, source, translated, false);
  assert.deepEqual(report.versionMismatches, ["changed"]);
  assert.deepEqual(report.skippedManual, [{documentId: "manual", language: "en"}]);
  const manual = (topics.manual.translations as Record<string, Record<string, unknown>>).en;
  assert.equal(manual.title, "Human translation");
});
