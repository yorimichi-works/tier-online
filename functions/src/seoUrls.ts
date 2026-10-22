import {SupportedLocale} from "./internationalization";

const DEFAULT_SITE_ORIGIN = "https://tier-online.web.app";

export function normalizeProductionOrigin(value: string | undefined): string {
  const candidate = (value ?? DEFAULT_SITE_ORIGIN).trim().replace(/\/+$/, "");
  const url = new URL(candidate);
  if (url.protocol !== "https:" ||
      url.hostname === "localhost" ||
      url.hostname === "127.0.0.1") {
    throw new Error("SEO_SITE_ORIGIN must be a production HTTPS origin");
  }
  return url.origin;
}

export const SITE_ORIGIN = normalizeProductionOrigin(
  process.env.SEO_SITE_ORIGIN,
);

export const localizedHomePath = (locale: SupportedLocale): string =>
  `/${locale}/`;

export const localizedHomeUrl = (locale: SupportedLocale): string =>
  `${SITE_ORIGIN}${localizedHomePath(locale)}`;

export const localizedTopicPath = (
  locale: SupportedLocale,
  topicId: string,
  preset = false,
): string => `/${locale}/${preset ? "preset" : "tier"}/${encodeURIComponent(topicId)}`;

export const localizedTopicUrl = (
  locale: SupportedLocale,
  topicId: string,
  preset = false,
): string => `${SITE_ORIGIN}${localizedTopicPath(locale, topicId, preset)}`;

export const localeSitemapPath = (locale: SupportedLocale): string =>
  `/sitemap-${locale}.xml`;

export const localeSitemapUrl = (locale: SupportedLocale): string =>
  `${SITE_ORIGIN}${localeSitemapPath(locale)}`;

// The first page deliberately keeps the original URL.  This keeps submitted
// locale sitemap URLs stable while allowing a locale to grow beyond the 50k
// URL protocol limit.
export const localeSitemapPagePath = (
  locale: SupportedLocale,
  page: number,
): string => page <= 1 ? localeSitemapPath(locale) :
  `/sitemap-${locale}-${page}.xml`;

export const localeSitemapPageUrl = (
  locale: SupportedLocale,
  page: number,
): string => `${SITE_ORIGIN}${localeSitemapPagePath(locale, page)}`;

export const sitemapIndexUrl = (): string => `${SITE_ORIGIN}/sitemap.xml`;

export function canonicalPageUrl(
  locale: SupportedLocale,
  pathSegments: readonly string[],
): string {
  if (pathSegments.length === 0) return localizedHomeUrl(locale);
  const path = pathSegments.map(encodeURIComponent).join("/");
  return `${SITE_ORIGIN}/${locale}/${path}`;
}
