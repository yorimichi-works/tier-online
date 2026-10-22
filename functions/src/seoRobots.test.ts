import assert from "node:assert/strict";
import test from "node:test";

import {
  isProductionHost,
  robotsText,
} from "./seoRobots";
import {normalizeProductionOrigin} from "./seoUrls";

test("production robots allows public content and announces one sitemap", () => {
  const body = robotsText(true);
  assert.match(body, /User-agent: \*/);
  assert.match(body, /Allow: \//);
  assert.doesNotMatch(body, /^Disallow: \/$/m);
  assert.match(body, /Disallow: \/ja\/settings/);
  assert.match(body, /Sitemap: https:\/\/tier-online\.web\.app\/sitemap\.xml/);
  assert.equal(body.match(/^Sitemap:/gm)?.length, 1);
});

test("preview and staging hosts are blocked without production sitemap", () => {
  assert.equal(isProductionHost("tier-online.web.app"), true);
  assert.equal(isProductionHost("tier-online.web.app:443"), true);
  assert.equal(isProductionHost("tier-online--preview-123.web.app"), false);
  assert.equal(isProductionHost("localhost:5000"), false);
  const body = robotsText(false);
  assert.match(body, /^Disallow: \/$/m);
  assert.doesNotMatch(body, /Sitemap:/);
});

test("production sitemap origin rejects localhost and non-HTTPS URLs", () => {
  assert.throws(() => normalizeProductionOrigin("http://tier-online.web.app"));
  assert.throws(() => normalizeProductionOrigin("https://localhost:5000"));
  assert.equal(
    normalizeProductionOrigin("https://tier-online.web.app/"),
    "https://tier-online.web.app",
  );
});
