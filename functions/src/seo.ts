import {getFirestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";

// TODO: デプロイ前に実際の公開ドメインへ置き換える
const SITE_ORIGIN = "https://YOUR_DOMAIN";

const LOCALES = ["ja", "ko", "en"] as const;
type Locale = (typeof LOCALES)[number];

const OG_LOCALE: Record<Locale, string> = {
  ja: "ja_JP",
  ko: "ko_KR",
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
  en: {
    title: "Tier Online | Create and Share Tier Lists",
    description:
      "Create and share tier lists for free, then compare your ranking with the community.",
  },
};

const DEFAULT_IMAGE = `${SITE_ORIGIN}/icons/Icon-512.png`;

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

  if (!topicSnapshot.exists) {
    res.status(404).send(renderShell(""));
    return;
  }

  const data = topicSnapshot.data() ?? {};
  const title = escapeHtml((data.title as string | undefined) ?? DEFAULT_META[locale].title);
  const rawDescription = (data.description as string | undefined)?.trim();
  const description = escapeHtml(
    rawDescription && rawDescription.length > 0
      ? rawDescription
      : DEFAULT_META[locale].description,
  );
  const image = escapeHtml(
    (itemsSnapshot.docs[0]?.data()?.imageUrl as string | undefined) ?? DEFAULT_IMAGE,
  );
  const canonical = `${SITE_ORIGIN}/${locale}/tier/${topicId}`;

  const alternates = LOCALES.map(
    (code) =>
      `  <link rel="alternate" hreflang="${code}" href="${SITE_ORIGIN}/${code}/tier/${topicId}">`,
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
