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
  return parseSupportedLocale(value) ?? fallback;
}

export function parseSupportedLocale(
  value: unknown,
): SupportedLocale | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase().replace(/_/g, "-");
  if (normalized === "zh" || normalized === "zh-hant") return "zh-tw";
  if (normalized === "pt") return "pt-br";
  if (isSupportedLocale(normalized)) return normalized;
  const language = normalized.split("-")[0];
  if (language === "ja" || language === "ko" || language === "en") {
    return language;
  }
  if (language === "zh") return "zh-tw";
  if (language === "pt") return "pt-br";
  return undefined;
}

export function resolveLocalizedValue<T>(
  requested: SupportedLocale,
  values: Partial<Record<SupportedLocale, T>>,
): T | undefined {
  if (values[requested] !== undefined) return values[requested];
  const language = requested.split("-")[0];
  for (const locale of SUPPORTED_LOCALES) {
    if (locale.split("-")[0] === language && values[locale] !== undefined) {
      return values[locale];
    }
  }
  return values.en ?? values.ja ??
    SUPPORTED_LOCALES.map((locale) => values[locale])
      .find((value) => value !== undefined);
}

export function localeFromAcceptLanguage(
  header: string | undefined,
  fallback: SupportedLocale = "ja",
): SupportedLocale {
  if (!header) return fallback;
  const primary = header.split(",")[0]?.trim().toLowerCase() ?? "";
  if (primary.startsWith("ko")) return "ko";
  if (primary.startsWith("ja")) return "ja";
  if (primary.startsWith("zh")) return "zh-tw";
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

export function firestoreLanguage(value: unknown): string {
  const locale = normalizeLocale(value);
  if (locale === "zh-tw") return "zh-TW";
  if (locale === "pt-br") return "pt-BR";
  return locale;
}
