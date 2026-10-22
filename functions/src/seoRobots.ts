import {SUPPORTED_LOCALES} from "./internationalization";
import {sitemapIndexUrl} from "./seoUrls";

const DEFAULT_PRODUCTION_HOSTS = [
  "tier-online.web.app",
  "tier-online.firebaseapp.com",
];

export function productionHosts(): Set<string> {
  const configured = process.env.SEO_PRODUCTION_HOSTS
    ?.split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);
  return new Set(configured?.length ? configured : DEFAULT_PRODUCTION_HOSTS);
}

export function normalizedRequestHost(value: string | undefined): string {
  return (value ?? "")
    .split(",")[0]
    .trim()
    .toLowerCase()
    .replace(/:\d+$/, "");
}

export function isProductionHost(value: string | undefined): boolean {
  return productionHosts().has(normalizedRequestHost(value));
}

export function robotsText(production: boolean): string {
  if (!production) {
    return "User-agent: *\nDisallow: /\n";
  }
  const privatePaths = SUPPORTED_LOCALES.flatMap((locale) => [
    `Disallow: /${locale}/create`,
    `Disallow: /${locale}/settings`,
    `Disallow: /${locale}/user`,
    `Disallow: /${locale}/auth/`,
  ]);
  return [
    "User-agent: *",
    "Allow: /",
    "Disallow: /admin/",
    "Disallow: /api/",
    ...privatePaths,
    `Sitemap: ${sitemapIndexUrl()}`,
    "",
  ].join("\n");
}
