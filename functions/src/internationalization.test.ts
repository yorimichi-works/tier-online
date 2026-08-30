import assert from "node:assert/strict";
import test from "node:test";

import {
  hreflang,
  firestoreLanguage,
  isSupportedLocale,
  localeFromAcceptLanguage,
  normalizeLocale,
  SUPPORTED_LOCALES,
  wikipediaLanguage,
} from "./internationalization";

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
  assert.equal(localeFromAcceptLanguage("pt-PT,pt;q=0.9"), "pt-br");
});

test("external and SEO language codes are derived centrally", () => {
  assert.equal(hreflang("zh-tw"), "zh-Hant-TW");
  assert.equal(hreflang("pt-br"), "pt-BR");
  assert.equal(wikipediaLanguage("zh-tw"), "zh");
  assert.equal(wikipediaLanguage("pt-br"), "pt");
  assert.equal(firestoreLanguage("zh-tw"), "zh-TW");
  assert.equal(firestoreLanguage("pt_BR"), "pt-BR");
});
