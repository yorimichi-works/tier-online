import assert from "node:assert/strict";
import test from "node:test";

import {
  canonicalLocalePath,
  isAdEligibleHomePath,
  isIndexableHomePath,
  isKnownHomeShellPath,
  isSeoEligibleTopic,
  renderShell,
  robots,
  robotsHead,
  sitemap,
  seoEligibleTopicDocuments,
  sitemapStaticPaths,
} from "./seo";

async function invokeHttpFunction(
  fn: unknown,
  path: string,
  host: string,
): Promise<{status: number; headers: Record<string, string>; body: string}> {
  let status = 200;
  let body = "";
  const headers: Record<string, string> = {};
  const response = {
    set(name: string, value: string) {
      headers[name.toLowerCase()] = value;
      return response;
    },
    status(code: number) {
      status = code;
      return response;
    },
    send(value: string) {
      body = value;
      return response;
    },
  };
  const request = {
    path,
    get(name: string) {
      return name.toLowerCase() === "host" ? host : undefined;
    },
  };
  const runnable = fn as (
    req: unknown,
    res: unknown,
  ) => Promise<void> | void;
  await runnable(request, response);
  return {status, headers, body};
}

test("SSR shell emits one AdSense loader and the locale-specific html lang", () => {
  const expectations = {
    ja: "ja",
    en: "en",
    ko: "ko",
    "zh-tw": "zh-TW",
    "pt-br": "pt-BR",
  } as const;

  for (const [locale, htmlLang] of Object.entries(expectations)) {
    const html = renderShell(locale as keyof typeof expectations, "<title>test</title>");
    assert.match(html, new RegExp(`<html lang="${htmlLang}">`));
    assert.match(html, /name="google-site-verification"/);
    assert.equal(
      html.match(/pagead2\.googlesyndication\.com\/pagead\/js\/adsbygoogle\.js/g)?.length,
      1,
    );
    assert.equal(html.match(/ca-pub-3186852093801241/g)?.length, 1);
  }
});

test("SSR error and action shells can omit the AdSense loader", () => {
  const html = renderShell("ja", "<title>not found</title>", "", false);
  assert.doesNotMatch(html, /adsbygoogle\.js/);
  assert.doesNotMatch(html, /ca-pub-3186852093801241/);
});

test("robots meta distinguishes indexable and noindex SSR pages", () => {
  assert.equal(
    robotsHead(false),
    "  <meta name=\"robots\" content=\"noindex,follow\">",
  );
  assert.match(
    robotsHead(true, "/en/tier/topic"),
    /content="index,follow" data-indexable-path="\/en\/tier\/topic"/,
  );
  const html = renderShell("en", robotsHead(false), "", false);
  assert.match(html, /meta name="robots" content="noindex,follow"/);
  assert.match(html, /pushState/);
  assert.match(html, /popstate/);
});

test("only canonical public home paths are unconditionally ad eligible", () => {
  assert.equal(isAdEligibleHomePath("/"), true);
  for (const locale of ["ja", "en", "ko", "zh-tw", "pt-br"]) {
    assert.equal(isAdEligibleHomePath(`/${locale}/`), true);
    assert.equal(isAdEligibleHomePath(`/${locale}/create`), false);
    assert.equal(isAdEligibleHomePath(`/${locale}/settings`), false);
    assert.equal(isAdEligibleHomePath(`/${locale}/search`), false);
  }
  assert.equal(isAdEligibleHomePath("/login"), false);
});

test("only locale-prefixed canonical homes are indexable", () => {
  assert.equal(isIndexableHomePath("/"), false);
  assert.equal(isIndexableHomePath("/ja/"), true);
  assert.equal(isIndexableHomePath("/en/"), true);
  assert.equal(isIndexableHomePath("/ja"), false);
  assert.equal(isIndexableHomePath("/ja/search"), false);
});

test("known client routes render noindex shells and unknown routes return 404", () => {
  assert.equal(isKnownHomeShellPath("/en/settings"), true);
  assert.equal(isKnownHomeShellPath("/ko/auth/action"), true);
  assert.equal(isKnownHomeShellPath("/pt-br/search"), true);
  assert.equal(isKnownHomeShellPath("/fr/settings"), false);
  assert.equal(isKnownHomeShellPath("/en/not-existing"), false);
});

test("sitemap static URLs contain content-rich homes but not client-only search", () => {
  assert.deepEqual(sitemapStaticPaths(), [
    "/ja/",
    "/ko/",
    "/en/",
    "/zh-tw/",
    "/pt-br/",
  ]);
});

test("SEO and sitemap expose only approved public topics", () => {
  const approved = {
    isPublic: true,
    moderationStatus: "approved",
    title: "Topic",
    itemCount: 3,
  };
  assert.equal(isSeoEligibleTopic(approved), true);
  assert.equal(isSeoEligibleTopic({...approved, moderationStatus: "flagged"}), false);
  assert.equal(isSeoEligibleTopic({isPublic: true}), false);
  assert.equal(isSeoEligibleTopic({...approved, isPublic: false}), false);

  const documents = [
    {id: "approved", data: () => approved},
    {id: "flagged", data: () => ({...approved, moderationStatus: "flagged"})},
    {id: "legacy-unreviewed", data: () => ({isPublic: true})},
  ];
  assert.deepEqual(
    seoEligibleTopicDocuments(documents).map((document) => document.id),
    ["approved"],
  );
});

test("canonical locale redirects preserve the remainder of the URL", () => {
  assert.equal(canonicalLocalePath("/zh-TW/"), "/zh-tw/");
  assert.equal(
    canonicalLocalePath("/zh-TW/tier/example"),
    "/zh-tw/tier/example",
  );
  assert.equal(canonicalLocalePath("/pt-BR/search"), "/pt-br/search");
  assert.equal(canonicalLocalePath("/pt-br/search"), null);
});

test("sitemap index and robots handlers return correct status and content types", async (context) => {
  // Exercise HTTP output without a Firebase app or a connection to live data.
  const query = {
    where: () => query,
    orderBy: () => query,
    limit: () => query,
    select: () => query,
    get: async () => ({docs: [], size: 0}),
    count: () => ({get: async () => ({data: () => ({count: 0})})}),
  };
  context.mock.method(require("firebase-admin/firestore"), "getFirestore", () => ({
    collection: () => query,
  }));
  const sitemapResponse = await invokeHttpFunction(
    sitemap,
    "/sitemap.xml",
    "tier-online.web.app",
  );
  assert.equal(sitemapResponse.status, 200);
  assert.match(sitemapResponse.headers["content-type"], /^application\/xml/);
  assert.match(sitemapResponse.body, /<sitemapindex/);

  const robotsResponse = await invokeHttpFunction(
    robots,
    "/robots.txt",
    "tier-online.web.app",
  );
  assert.equal(robotsResponse.status, 200);
  assert.match(robotsResponse.headers["content-type"], /^text\/plain/);
  assert.match(robotsResponse.body, /Sitemap:/);

  const previewSitemap = await invokeHttpFunction(
    sitemap,
    "/sitemap.xml",
    "tier-online--preview.web.app",
  );
  assert.equal(previewSitemap.status, 404);
  assert.equal(previewSitemap.headers["x-robots-tag"], "noindex, nofollow");
});
