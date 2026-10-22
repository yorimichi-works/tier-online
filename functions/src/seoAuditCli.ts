import {
  hreflang,
  SUPPORTED_LOCALES,
  SupportedLocale,
} from "./internationalization";
import {GENERIC_PRESET_TOPIC_IDS} from "./presets";
import {SITE_ORIGIN} from "./seoUrls";

type AuditResult = {
  url: string;
  issues: string[];
};

function option(name: string): string | undefined {
  const prefix = `--${name}=`;
  return process.argv.find((argument) => argument.startsWith(prefix))
    ?.slice(prefix.length);
}

function normalizedOrigin(value: string): string {
  return value.replace(/\/+$/, "");
}

function escapedPattern(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function containsMeta(html: string, name: string, expected: string): boolean {
  const tag = new RegExp(`<meta[^>]+${name}=["']${escapedPattern(expected)}["'][^>]*>`, "i");
  return tag.test(html);
}

function containsRobots(html: string, content: string): boolean {
  return /<meta\b[^>]*>/gi.test(html) && [...html.matchAll(/<meta\b[^>]*>/gi)]
    .some((tag) => /\bname=["']robots["']/i.test(tag[0]) &&
      new RegExp(`\\bcontent=["']${escapedPattern(content)}["']`, "i").test(tag[0]));
}

function containsLink(html: string, rel: string, href: string, hreflang?: string): boolean {
  const attributes = [
    `(?=[^>]*\\brel=["']${escapedPattern(rel)}["'])`,
    `(?=[^>]*\\bhref=["']${escapedPattern(href)}["'])`,
    hreflang == null ? "" : `(?=[^>]*\\bhreflang=["']${escapedPattern(hreflang)}["'])`,
  ].join("");
  return new RegExp(`<link${attributes}[^>]*>`, "i").test(html);
}

function htmlIssues(
  html: string,
  url: string,
  locale: SupportedLocale,
): string[] {
  const issues: string[] = [];
  const lang = locale === "zh-tw" ? "zh-TW" : locale === "pt-br" ? "pt-BR" : locale;
  if (!new RegExp(`<html\\s+lang=["']${escapedPattern(lang)}["']`, "i").test(html)) {
    issues.push(`html lang must be ${lang}`);
  }
  if (!/<title>[^<]+<\/title>/i.test(html)) issues.push("missing title");
  if (!containsMeta(html, "name", "description")) issues.push("missing description");
  if (!containsRobots(html, "index,follow")) {
    issues.push("robots is not index,follow");
  }
  if (!containsLink(html, "canonical", url)) issues.push("canonical mismatch");
  for (const alternateLocale of SUPPORTED_LOCALES) {
    const alternate = url.replace(
      new RegExp(`/${escapedPattern(locale)}/`),
      `/${alternateLocale}/`,
    );
    const language = hreflang(alternateLocale);
    if (!containsLink(html, "alternate", alternate, language)) {
      issues.push(`missing hreflang ${language}`);
    }
  }
  return issues;
}

async function auditHtml(url: string, locale: SupportedLocale): Promise<AuditResult> {
  try {
    const response = await fetch(url, {redirect: "manual"});
    const body = await response.text();
    const issues = response.status === 200 ? htmlIssues(body, url, locale) :
      [`HTTP ${response.status}`];
    return {url, issues};
  } catch (error) {
    return {url, issues: [error instanceof Error ? error.message : String(error)]};
  }
}

async function auditText(url: string, predicate: (body: string) => string[]): Promise<AuditResult> {
  try {
    const response = await fetch(url, {redirect: "manual"});
    const body = await response.text();
    return {
      url,
      issues: response.status === 200 ? predicate(body) : [`HTTP ${response.status}`],
    };
  } catch (error) {
    return {url, issues: [error instanceof Error ? error.message : String(error)]};
  }
}

async function main(): Promise<void> {
  const origin = normalizedOrigin(option("base-url") ?? SITE_ORIGIN);
  const presetIds = GENERIC_PRESET_TOPIC_IDS.slice(0, 3);
  const tierId = option("tier");
  const results: AuditResult[] = [];

  results.push(await auditText(`${origin}/robots.txt`, (body) => {
    const issues: string[] = [];
    if (!/^User-agent:\s*\*/mi.test(body)) issues.push("missing User-agent");
    if (!new RegExp(`Sitemap:\\s*${escapedPattern(`${origin}/sitemap.xml`)}`, "i").test(body)) {
      issues.push("missing sitemap declaration");
    }
    if (/^Disallow:\s*\/$/mi.test(body)) issues.push("production is fully blocked");
    return issues;
  }));
  results.push(await auditText(`${origin}/sitemap.xml`, (body) => {
    const issues: string[] = [];
    if (!/<sitemapindex\b/i.test(body)) issues.push("not a sitemap index");
    for (const locale of SUPPORTED_LOCALES) {
      if (!body.includes(`${origin}/sitemap-${locale}.xml`)) {
        issues.push(`missing sitemap ${locale}`);
      }
    }
    return issues;
  }));

  for (const locale of SUPPORTED_LOCALES) {
    results.push(await auditHtml(`${origin}/${locale}/`, locale));
    for (const presetId of presetIds) {
      results.push(await auditHtml(
        `${origin}/${locale}/preset/${encodeURIComponent(presetId)}`,
        locale,
      ));
    }
    if (tierId != null) {
      results.push(await auditHtml(
        `${origin}/${locale}/tier/${encodeURIComponent(tierId)}`,
        locale,
      ));
    }
  }

  let failed = 0;
  for (const result of results) {
    if (result.issues.length === 0) {
      console.log(`PASS ${result.url}`);
    } else {
      failed += 1;
      console.log(`FAIL ${result.url} - ${result.issues.join("; ")}`);
    }
  }
  console.log(`SEO audit: ${results.length - failed}/${results.length} passed`);
  if (failed > 0) process.exitCode = 1;
}

void main();
