import assert from "node:assert/strict";
import test from "node:test";

import {
  hreflang,
  firestoreLanguage,
  isSupportedLocale,
  localeFromAcceptLanguage,
  normalizeLocale,
  parseSupportedLocale,
  resolveLocalizedValue,
  SUPPORTED_LOCALES,
  wikipediaLanguage,
} from "./internationalization";
import {
  GENERIC_PRESET_TOPIC_IDS,
  genericPresetMeta,
  isGenericPresetTopic,
} from "./presets";

test("supported locale codes are stable across routes and stored content", () => {
  assert.deepEqual(SUPPORTED_LOCALES, ["ja", "ko", "en", "zh-tw", "pt-br"]);
  for (const locale of SUPPORTED_LOCALES) {
    assert.equal(isSupportedLocale(locale), true);
  }
});

test("locale aliases and browser language are normalized", () => {
  assert.equal(normalizeLocale("zh_Hant"), "zh-tw");
  assert.equal(normalizeLocale("pt"), "pt-br");
  assert.equal(normalizeLocale("es"), "en");
  assert.equal(localeFromAcceptLanguage("zh-Hant-HK,zh;q=0.9"), "zh-tw");
  assert.equal(localeFromAcceptLanguage("zh-HK,zh;q=0.9"), "zh-tw");
  assert.equal(localeFromAcceptLanguage("zh-MO,zh;q=0.9"), "zh-tw");
  assert.equal(localeFromAcceptLanguage("pt-PT,pt;q=0.9"), "pt-br");
});

test("missing legacy locale stays unknown instead of becoming Japanese", () => {
  assert.equal(parseSupportedLocale(undefined), undefined);
  assert.equal(parseSupportedLocale("unknown"), undefined);
  assert.equal(parseSupportedLocale("ko-KR"), "ko");
  assert.equal(parseSupportedLocale("zh-Hant"), "zh-tw");
});

test("localized values resolve by exact, language, English, then Japanese", () => {
  assert.equal(resolveLocalizedValue("ko", {ko: "exact", en: "en"}), "exact");
  assert.equal(resolveLocalizedValue("pt-br", {en: "en", ja: "ja"}), "en");
  assert.equal(resolveLocalizedValue("zh-tw", {ja: "ja"}), "ja");
});

test("external and SEO language codes are derived centrally", () => {
  assert.equal(hreflang("zh-tw"), "zh-Hant-TW");
  assert.equal(hreflang("pt-br"), "pt-BR");
  assert.equal(wikipediaLanguage("zh-tw"), "zh");
  assert.equal(wikipediaLanguage("pt-br"), "pt");
  assert.equal(firestoreLanguage("zh-tw"), "zh-TW");
  assert.equal(firestoreLanguage("pt_BR"), "pt-BR");
});

test("all generic presets are exposed to SSR and sitemap in five locales", () => {
  assert.equal(GENERIC_PRESET_TOPIC_IDS.length, 51);
  assert.equal(new Set(GENERIC_PRESET_TOPIC_IDS).size, 51);
  for (const id of GENERIC_PRESET_TOPIC_IDS) {
    assert.equal(isGenericPresetTopic(id), true);
  }
  for (const locale of SUPPORTED_LOCALES) {
    const meta = genericPresetMeta(locale);
    assert.ok(meta.title.length > 0);
    assert.ok(meta.description.length > 0);
  }
});
