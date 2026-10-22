import {
  SUPPORTED_LOCALES,
  SupportedLocale,
} from "./internationalization";
import {GENERIC_PRESET_TOPIC_IDS} from "./presets";
import {
  localeTopicIndexability,
  SeoExclusionReason,
} from "./seoIndexability";
import {
  localeSitemapPageUrl,
  localizedHomeUrl,
  localizedTopicUrl,
} from "./seoUrls";

export const MAX_URLS_PER_SITEMAP = 50000;

export type SitemapTopicDocument = {
  id: string;
  data: Record<string, unknown>;
};

export type SitemapEntry = {
  loc: string;
  lastmod?: string;
};

export type SitemapStats = {
  includedByLocale: Record<SupportedLocale, number>;
  excludedByReason: Partial<Record<SeoExclusionReason, number>>;
  candidateDocuments: number;
};

export type SitemapBundle = {
  // `entries`/`xml` retain the first page for callers that consume the
  // historical per-locale sitemap URL.  New callers should use `pages`.
  entries: Record<SupportedLocale, SitemapEntry[]>;
  xml: Record<SupportedLocale, string>;
  pages: Record<SupportedLocale, SitemapPage[]>;
  stats: SitemapStats;
};

export type SitemapPage = {
  page: number;
  entries: SitemapEntry[];
  xml: string;
};

function incrementReason(
  reasons: Partial<Record<SeoExclusionReason, number>>,
  reason: SeoExclusionReason,
): void {
  reasons[reason] = (reasons[reason] ?? 0) + 1;
}

function lastmodOf(value: unknown): string | undefined {
  let date: Date | undefined;
  if (value instanceof Date) {
    date = value;
  } else if (typeof value === "string" || typeof value === "number") {
    date = new Date(value);
  } else if (typeof value === "object" && value !== null &&
      "toDate" in value && typeof value.toDate === "function") {
    date = value.toDate() as Date;
  }
  return date != null && !Number.isNaN(date.getTime()) ?
    date.toISOString() : undefined;
}

export function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export function sitemapUrlsetXml(entries: readonly SitemapEntry[]): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${entries.map((entry) => `  <url><loc>${escapeXml(entry.loc)}</loc>${
    entry.lastmod ? `<lastmod>${escapeXml(entry.lastmod)}</lastmod>` : ""
  }</url>`).join("\n")}
</urlset>`;
}

export function sitemapIndexXml(bundle?: SitemapBundle): string {
  const sitemapUrls = bundle == null ?
    SUPPORTED_LOCALES.map((locale) => localeSitemapPageUrl(locale, 1)) :
    SUPPORTED_LOCALES.flatMap((locale) =>
      bundle.pages[locale].map((page) => localeSitemapPageUrl(locale, page.page)),
    );
  return `<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${sitemapUrls.map(
    (url) => `  <sitemap><loc>${escapeXml(url)}</loc></sitemap>`,
  ).join("\n")}
</sitemapindex>`;
}

export function buildSitemapBundle(
  documents: readonly SitemapTopicDocument[],
): SitemapBundle {
  const entries = Object.fromEntries(SUPPORTED_LOCALES.map((locale) => [
    locale,
    [
      {loc: localizedHomeUrl(locale)},
      ...GENERIC_PRESET_TOPIC_IDS.map((topicId) => ({
        loc: localizedTopicUrl(locale, topicId, true),
      })),
    ],
  ])) as Record<SupportedLocale, SitemapEntry[]>;
  const excludedByReason: Partial<Record<SeoExclusionReason, number>> = {};
  const seenTopicIds = new Set<string>();

  for (const document of documents) {
    if (seenTopicIds.has(document.id)) {
      for (const _locale of SUPPORTED_LOCALES) {
        incrementReason(excludedByReason, "duplicate");
      }
      continue;
    }
    seenTopicIds.add(document.id);
    for (const locale of SUPPORTED_LOCALES) {
      const result = localeTopicIndexability(document.data, locale);
      if (!result.indexable) {
        incrementReason(
          excludedByReason,
          result.reason ?? "translation_incomplete",
        );
        continue;
      }
      entries[locale].push({
        loc: localizedTopicUrl(locale, document.id),
        lastmod: lastmodOf(document.data.updatedAt ?? document.data.createdAt),
      });
    }
  }

  const pages = Object.fromEntries(SUPPORTED_LOCALES.map((locale) => {
    const localeEntries = entries[locale];
    const localePages: SitemapPage[] = [];
    for (let start = 0; start < localeEntries.length; start += MAX_URLS_PER_SITEMAP) {
      const pageEntries = localeEntries.slice(start, start + MAX_URLS_PER_SITEMAP);
      localePages.push({
        page: localePages.length + 1,
        entries: pageEntries,
        xml: sitemapUrlsetXml(pageEntries),
      });
    }
    // Every locale always has a home URL, but retain a valid empty page if a
    // future locale intentionally has no bootstrap content.
    if (localePages.length === 0) {
      localePages.push({page: 1, entries: [], xml: sitemapUrlsetXml([])});
    }
    return [locale, localePages];
  })) as Record<SupportedLocale, SitemapPage[]>;
  const xml = Object.fromEntries(SUPPORTED_LOCALES.map((locale) => [
    locale,
    pages[locale][0].xml,
  ])) as Record<SupportedLocale, string>;
  return {
    entries,
    xml,
    pages,
    stats: {
      includedByLocale: Object.fromEntries(SUPPORTED_LOCALES.map((locale) => [
        locale,
        entries[locale].length,
      ])) as Record<SupportedLocale, number>,
      excludedByReason,
      candidateDocuments: documents.length,
    },
  };
}
