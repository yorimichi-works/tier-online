export const SUPPORTED_LOCALES = ["ja", "ko", "en", "zh-tw", "pt-br"] as const;

export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

export const SUPPORTED_REGION_CODES = [
  "JP",
  "KR",
  "TW",
  "HK",
  "US",
  "GB",
  "BR",
  "GLOBAL",
] as const;

export type SupportedRegionCode = (typeof SUPPORTED_REGION_CODES)[number];

export function isSupportedLocale(value: unknown): value is SupportedLocale {
  return typeof value === "string" &&
    (SUPPORTED_LOCALES as readonly string[]).includes(value);
}

export function normalizeLocale(
  value: unknown,
  fallback: SupportedLocale = "en",
): SupportedLocale {
  if (typeof value !== "string") return fallback;
  const normalized = value.trim().toLowerCase().replace(/_/g, "-");
  if (normalized === "zh" || normalized === "zh-hant") return "zh-tw";
  if (normalized === "pt") return "pt-br";
  return isSupportedLocale(normalized) ? normalized : fallback;
}

export function localeFromAcceptLanguage(
  header: string | undefined,
  fallback: SupportedLocale = "ja",
): SupportedLocale {
  if (!header) return fallback;
  const primary = header.split(",")[0]?.trim().toLowerCase() ?? "";
  if (primary.startsWith("ko")) return "ko";
  if (primary.startsWith("ja")) return "ja";
  if (primary.startsWith("zh-tw") || primary.startsWith("zh-hant")) return "zh-tw";
  if (primary.startsWith("pt")) return "pt-br";
  if (primary.startsWith("en")) return "en";
  return fallback;
}

export function hreflang(locale: SupportedLocale): string {
  if (locale === "zh-tw") return "zh-Hant-TW";
  if (locale === "pt-br") return "pt-BR";
  return locale;
}

export function wikipediaLanguage(value: unknown): string {
  const locale = normalizeLocale(value);
  if (locale === "zh-tw") return "zh";
  if (locale === "pt-br") return "pt";
  return locale;
}
