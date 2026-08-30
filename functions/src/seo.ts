import {getFirestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";

const SITE_ORIGIN = "https://tier-online.web.app";

const LOCALES = ["ja", "ko", "en", "zh-tw", "pt-br"] as const;
type Locale = (typeof LOCALES)[number];

const OG_LOCALE: Record<Locale, string> = {
  ja: "ja_JP",
  ko: "ko_KR",
  "zh-tw": "zh_TW",
  "pt-br": "pt_BR",
  en: "en_US",
};

const DEFAULT_META: Record<Locale, {title: string; description: string}> = {
  ja: {
    title: "tier表オンライン｜無料でTier表を作成・共有",
    description: "無料でTier表を作成・共有。みんなのランキングと自分の結果を比べよう。",
  },
  ko: {
    title: "티어표 온라인 | 무료 티어표 만들기",
    description: "무료로 티어표를 만들고 공유하고, 모두의 랭킹과 비교해 보세요.",
  },
  "zh-tw": {
    title: "Tier 表線上版｜免費建立與分享 Tier 排名",
    description: "免費建立並分享 Tier 排名表，和大家的排名結果互相比較。",
  },
  "pt-br": {
    title: "Tier Online | Crie e compartilhe Tier Lists",
    description:
      "Crie e compartilhe Tier Lists gratuitamente e compare seu ranking com a comunidade.",
  },
  en: {
    title: "Tier Online | Create and Share Tier Lists",
    description:
      "Create and share tier lists for free, then compare your ranking with the community.",
  },
};

const DEFAULT_IMAGE = `${SITE_ORIGIN}/icons/Icon-512.png`;
const HOME_IMAGE: Record<Locale, string> = {
  ja: `${SITE_ORIGIN}/og-image-ja.png`,
  ko: `${SITE_ORIGIN}/og-image-ko.png`,
  "zh-tw": `${SITE_ORIGIN}/og-image-en.png`,
  "pt-br": `${SITE_ORIGIN}/og-image-en.png`,
  en: `${SITE_ORIGIN}/og-image-en.png`,
};

function localeFromAcceptLanguage(header: string | undefined): Locale {
  if (!header) return "ja";
  const primary = header.split(",")[0]?.trim().toLowerCase() ?? "";
  if (primary.startsWith("ko")) return "ko";
  if (primary.startsWith("ja")) return "ja";
  if (primary.startsWith("zh-tw") || primary.startsWith("zh-hant")) return "zh-tw";
  if (primary.startsWith("pt")) return "pt-br";
  if (primary.startsWith("en")) return "en";
  return "ja";
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function parseLocale(value: string | undefined): Locale {
  return (LOCALES as readonly string[]).includes(value ?? "")
    ? (value as Locale)
    : "ja";
}

function renderShell(head: string): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="theme-color" content="#0D0D0F">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="Tier Online">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">
  <link rel="icon" type="image/png" href="/favicon.png"/>
  <link rel="manifest" href="/manifest.json">
${head}
</head>
<body>
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;
}

function hreflang(locale: Locale): string {
  if (locale === "zh-tw") return "zh-Hant-TW";
  if (locale === "pt-br") return "pt-BR";
  return locale;
}

// ルート("/")および対応言語配下(tier個別ページを除く)の共有プレビュー用。
// SNS/検索エンジンのクローラーはJavaScriptを実行しないため、静的index.html
// に埋め込んだメタタグは常に固定言語になってしまう。このハンドラで言語ごとに
// 正しいtitle/description/og:imageを返しつつ、実利用者には通常どおり
// flutter_bootstrap.jsでアプリ本体を読み込ませる。
export const renderHome = onRequest(async (req, res) => {
  const segments = req.path.split("/").filter(Boolean);
  const pathLocale = (LOCALES as readonly string[]).includes(segments[0] ?? "")
    ? (segments[0] as Locale)
    : null;
  const locale = pathLocale ?? localeFromAcceptLanguage(req.get("accept-language"));
  const meta = DEFAULT_META[locale];
  const canonical = `${SITE_ORIGIN}/${locale}/`;

  const alternates = LOCALES.map(
    (code) => `  <link rel="alternate" hreflang="${hreflang(code)}" href="${SITE_ORIGIN}/${code}/">`,
  ).join("\n");

  const head = `  <title>${escapeHtml(meta.title)}</title>
  <meta name="description" content="${escapeHtml(meta.description)}">
  <link rel="canonical" href="${canonical}">
${alternates}
  <link rel="alternate" hreflang="x-default" href="${SITE_ORIGIN}/ja/">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${escapeHtml(meta.title)}">
  <meta property="og:description" content="${escapeHtml(meta.description)}">
  <meta property="og:image" content="${HOME_IMAGE[locale]}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="summary_large_image">`;

  res.set("Cache-Control", "public, max-age=0, s-maxage=600");
  res.status(200).send(renderShell(head));
});

export const renderTopic = onRequest(async (req, res) => {
  const segments = req.path.split("/").filter(Boolean);
  const locale = parseLocale(segments[0]);
  const topicId = segments[2];
  if (segments[1] !== "tier" || !topicId) {
    res.status(404).send(renderShell(""));
    return;
  }

  const firestore = getFirestore();
  const topicRef = firestore.collection("topics").doc(topicId);
  const [topicSnapshot, itemsSnapshot] = await Promise.all([
    topicRef.get(),
    topicRef
      .collection("items")
      .orderBy("sortIndex")
      .limit(1)
      .get(),
  ]);

  const data = topicSnapshot.data() ?? {};
  if (!topicSnapshot.exists || data.isPublic === false) {
    res.status(404).send(renderShell(""));
    return;
  }

  const title = escapeHtml((data.title as string | undefined) ?? DEFAULT_META[locale].title);
  const rawDescription = (data.description as string | undefined)?.trim();
  const description = escapeHtml(
    rawDescription && rawDescription.length > 0
      ? rawDescription
      : DEFAULT_META[locale].description,
  );
  const rawImage = itemsSnapshot.docs[0]?.data()?.imageUrl as string | undefined;
  // og:image must be an absolute URL. Starter/seeded items store paths
  // relative to the Flutter asset bundle (e.g. "assets/foo.jpg"), which
  // Flutter web serves at "/assets/assets/foo.jpg" (the bundle's own
  // "assets/" root, nested under the web server's "/assets/" mount point).
  const image = escapeHtml(
    !rawImage ? DEFAULT_IMAGE :
      /^https?:\/\//.test(rawImage) ? rawImage :
      `${SITE_ORIGIN}/assets/${rawImage.replace(/^\/+/, "")}`,
  );
  const canonical = `${SITE_ORIGIN}/${locale}/tier/${topicId}`;

  const alternates = LOCALES.map(
    (code) =>
      `  <link rel="alternate" hreflang="${hreflang(code)}" href="${SITE_ORIGIN}/${code}/tier/${topicId}">`,
  ).join("\n");

  const head = `  <title>${title}</title>
  <meta name="description" content="${description}">
  <link rel="canonical" href="${canonical}">
${alternates}
  <meta property="og:type" content="article">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:image" content="${image}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="summary_large_image">`;

  res.set("Cache-Control", "public, max-age=0, s-maxage=600");
  res.status(200).send(renderShell(head));
});

export const sitemap = onRequest(async (_req, res) => {
  const firestore = getFirestore();
  const snapshot = await firestore
    .collection("topics")
    .where("isPublic", "==", true)
    .orderBy("createdAt", "desc")
    .limit(5000)
    .select("contentLanguage")
    .get();

  const staticPaths = LOCALES.flatMap((locale) => [
    `/${locale}/`,
    `/${locale}/search`,
  ]);

  const urls = [
    ...staticPaths.map((path) => `${SITE_ORIGIN}${path}`),
    ...snapshot.docs.map((doc) => {
      const locale = parseLocale(doc.get("contentLanguage") as string | undefined);
      return `${SITE_ORIGIN}/${locale}/tier/${doc.id}`;
    }),
  ];

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((url) => `  <url><loc>${escapeHtml(url)}</loc></url>`).join("\n")}
</urlset>`;

  res.set("Content-Type", "application/xml; charset=utf-8");
  res.set("Cache-Control", "public, max-age=0, s-maxage=3600");
  res.status(200).send(body);
});
