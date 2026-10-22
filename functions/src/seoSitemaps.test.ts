import assert from "node:assert/strict";
import test from "node:test";

import {GENERIC_PRESET_TOPIC_IDS} from "./presets";
import {
  buildSitemapBundle,
  MAX_URLS_PER_SITEMAP,
  sitemapIndexXml,
} from "./seoSitemaps";
import {localizedTopicUrl} from "./seoUrls";

function assertWellFormed(xml: string): void {
  const tags = [...xml.matchAll(/<\/?([a-z]+)(?:\s[^>]*)?>/g)];
  const stack: string[] = [];
  for (const match of tags) {
    const full = match[0];
    const name = match[1];
    if (full.startsWith("</")) {
      assert.equal(stack.pop(), name, `unexpected closing tag ${name}`);
    } else if (!full.endsWith("/>")) {
      stack.push(name);
    }
  }
  assert.deepEqual(stack, []);
  assert.doesNotMatch(xml, /&(?!amp;|lt;|gt;|quot;|apos;)/);
}

const approvedTopic = {
  isPublic: true,
  moderationStatus: "approved",
  title: "朝ごはん & 飲み物",
  itemCount: 3,
  sourceLocale: "ja",
  contentVersion: 1,
  updatedAt: "2026-08-30T00:00:00.000Z",
  translations: {
    en: {
      status: "completed",
      reviewRequired: false,
      title: "Breakfast & Drinks",
      sourceContentVersion: 1,
      itemNames: {one: "Eggs", two: "Toast", three: "Coffee"},
    },
    ko: {
      status: "review_required",
      reviewRequired: true,
      title: "아침 식사",
      sourceContentVersion: 1,
      itemNames: {one: "달걀", two: "토스트", three: "커피"},
    },
  },
};

test("sitemap index references exactly five locale sitemaps and parses", () => {
  const xml = sitemapIndexXml();
  assertWellFormed(xml);
  for (const locale of ["ja", "en", "ko", "zh-tw", "pt-br"]) {
    assert.match(xml, new RegExp(`/sitemap-${locale}\\.xml`));
  }
  assert.equal(xml.match(/<sitemap>/g)?.length, 5);
});

test("locale sitemaps contain canonical homes, presets and eligible UGC only", () => {
  const bundle = buildSitemapBundle([
    {id: "breakfast&drinks", data: approvedTopic},
    {id: "private", data: {...approvedTopic, isPublic: false}},
    {id: "hidden", data: {...approvedTopic, hidden: true}},
    {id: "deleted", data: {...approvedTopic, deleted: true}},
    {id: "thin", data: {...approvedTopic, itemCount: 2}},
  ]);
  const baseline = GENERIC_PRESET_TOPIC_IDS.length + 1;
  assert.equal(bundle.entries.ja.length, baseline + 1);
  assert.equal(bundle.entries.en.length, baseline + 1);
  assert.equal(bundle.entries.ko.length, baseline);
  assert.match(bundle.xml.ja, /\/ja\/tier\/breakfast%26drinks/);
  assert.match(bundle.xml.en, /\/en\/tier\/breakfast%26drinks/);
  assert.equal(
    bundle.entries.en.at(-1)?.loc,
    localizedTopicUrl("en", "breakfast&drinks"),
  );
  assert.doesNotMatch(bundle.xml.ko, /breakfast/);
  assert.doesNotMatch(bundle.xml.ja, /\/tier\/starter-generic-/);
  assert.match(bundle.xml.ja, /\/preset\/starter-generic-/);
  assert.doesNotMatch(bundle.xml.ja, /<loc>[^<]*[?#]/);
  assert.doesNotMatch(bundle.xml.ja, /\/tier\/(private|hidden|deleted)/);
  assert.match(bundle.xml.ja, /<lastmod>2026-08-30T00:00:00\.000Z<\/lastmod>/);
  assertWellFormed(bundle.xml.ja);
  assertWellFormed(bundle.xml.en);
});

test("hidden or deleted topics disappear on the next sitemap build", () => {
  const visible = buildSitemapBundle([{id: "topic", data: approvedTopic}]);
  const hidden = buildSitemapBundle([
    {id: "topic", data: {...approvedTopic, hidden: true}},
  ]);
  const deleted = buildSitemapBundle([
    {id: "topic", data: {...approvedTopic, deleted: true}},
  ]);
  assert.match(visible.xml.ja, /\/ja\/tier\/topic/);
  assert.doesNotMatch(hidden.xml.ja, /\/ja\/tier\/topic/);
  assert.doesNotMatch(deleted.xml.ja, /\/ja\/tier\/topic/);
});

test("locale sitemap overflow is split into protocol-sized pages", () => {
  const baseEntries = Array.from(
    {length: MAX_URLS_PER_SITEMAP},
    (_, index) => ({
      id: `topic-${index}`,
      data: approvedTopic,
    }),
  );
  const bundle = buildSitemapBundle(baseEntries);
  assert.equal(bundle.pages.ja.length, 2);
  assert.equal(bundle.pages.ja[0].entries.length, MAX_URLS_PER_SITEMAP);
  assert.equal(bundle.pages.ja[1].entries.length, GENERIC_PRESET_TOPIC_IDS.length + 1);
  const index = sitemapIndexXml(bundle);
  assert.match(index, /\/sitemap-ja-2\.xml/);
  assertWellFormed(index);
});
