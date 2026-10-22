import {FieldPath, getFirestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {
  hreflang,
  isSupportedLocale,
  localeFromAcceptLanguage,
  normalizeLocale,
  resolveLocalizedValue,
  SUPPORTED_LOCALES,
  SupportedLocale,
} from "./internationalization";
import {
  genericPresetMeta,
  isGenericPresetTopic,
} from "./presets";
import {
  baseTopicIndexability,
  indexableTopicLocales,
  localeTopicIndexability,
} from "./seoIndexability";
import {
  buildSitemapBundle,
  SitemapBundle,
  SitemapTopicDocument,
  sitemapIndexXml,
} from "./seoSitemaps";
import {isProductionHost, robotsText} from "./seoRobots";
import {
  canonicalPageUrl,
  localizedHomePath,
  localizedHomeUrl,
  localizedTopicPath,
  localizedTopicUrl,
  SITE_ORIGIN,
} from "./seoUrls";

const ADSENSE_PUBLISHER_ID = "ca-pub-3186852093801241";
const NOINDEX_HEAD = "  <meta name=\"robots\" content=\"noindex,follow\">";

export function robotsHead(indexable: boolean, path?: string): string {
  if (!indexable) return NOINDEX_HEAD;
  const pathAttribute = path == null ? "" :
    ` data-indexable-path="${escapeHtml(path)}"`;
  return `  <meta name="robots" content="index,follow"${pathAttribute}>`;
}

const HTML_LANG: Record<SupportedLocale, string> = {
  ja: "ja",
  en: "en",
  ko: "ko",
  "zh-tw": "zh-TW",
  "pt-br": "pt-BR",
};

const OG_LOCALE: Record<SupportedLocale, string> = {
  ja: "ja_JP",
  ko: "ko_KR",
  "zh-tw": "zh_TW",
  "pt-br": "pt_BR",
  en: "en_US",
};

const DEFAULT_META: Record<SupportedLocale, {title: string; description: string}> = {
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

const HOME_PUBLISHER_COPY: Record<SupportedLocale, string> = {
  ja: "Tier Onlineは、好きなテーマのTier表を無料で作成・共有し、みんなのランキングと自分の評価を比較できるサービスです。公開Tierを探して参加したり、自分だけのランキングを作れます。",
  en: "Tier Online is a free service for creating and sharing tier lists, discovering public topics, and comparing your ranking with the community.",
  ko: "Tier Online은 티어표를 무료로 만들고 공유하며, 공개 주제를 찾고 내 순위를 커뮤니티 결과와 비교할 수 있는 서비스입니다.",
  "zh-tw": "Tier Online 是可免費建立與分享 Tier 排名、探索公開主題，並將自己的排名與社群結果比較的服務。",
  "pt-br": "O Tier Online é um serviço gratuito para criar e compartilhar Tier Lists, descobrir temas públicos e comparar seu ranking com o da comunidade.",
};

const TOPIC_STATS_LABEL: Record<SupportedLocale, (participants: number, items: number) => string> = {
  ja: (participants, items) => `${participants}人が参加・${items}項目`,
  en: (participants, items) => `${participants} participants · ${items} items`,
  ko: (participants, items) => `참여자 ${participants}명 · 항목 ${items}개`,
  "zh-tw": (participants, items) => `${participants} 人參與・${items} 個項目`,
  "pt-br": (participants, items) => `${participants} participantes · ${items} itens`,
};

const DEFAULT_IMAGE = `${SITE_ORIGIN}/icons/Icon-512.png`;
const HOME_IMAGE: Record<SupportedLocale, string> = {
  ja: `${SITE_ORIGIN}/og-image-ja.png`,
  ko: `${SITE_ORIGIN}/og-image-ko.png`,
  "zh-tw": `${SITE_ORIGIN}/og-image-en.png`,
  "pt-br": `${SITE_ORIGIN}/og-image-en.png`,
  en: `${SITE_ORIGIN}/og-image-en.png`,
};

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function parseLocale(value: string | undefined): SupportedLocale {
  return isSupportedLocale(value) ? value : "ja";
}

// index.htmlの静的シェルと同等のhead/body(base href、viewport、背景色CSS、
// Google Sign-In用meta、起動スクリプト)を複製したもの。以前はこれらを省略
// していたため、<base href>が無いことでFlutterエンジンが自身のアセット
// (AssetManifest/canvaskit等)を現在の深いパス基準で誤って解決してしまい、
// 個別Tierページ等に直接アクセスすると背景色すら付かない白紙のまま起動に
// 失敗していた。
export function renderShell(
  locale: SupportedLocale,
  head: string,
  publisherContent = "",
  includeAdSense = true,
): string {
  return `<!DOCTYPE html>
<html lang="${HTML_LANG[locale]}">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover, interactive-widget=resizes-content">
  <meta name="theme-color" content="#0D0D0F">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="Tier Online">
  <meta name="google-site-verification" content="5I_WtmhnHQHh60JoHFQLwKtk6Fs0yuMyVGyLN5Ghki4">
  <meta name="google-signin-client_id" content="553966867727-fufba9jquashagb7gg8haf52ap99att3.apps.googleusercontent.com">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">
  <link rel="icon" type="image/png" href="/favicon.png"/>
  <link rel="manifest" href="/manifest.json">
  <link rel="preload" href="/assets/assets/fonts/NotoSansJP-TierSubset.ttf" as="font" type="font/ttf" crossorigin>
  <link rel="preload" href="/assets/assets/fonts/NotoSansKR-TierSubset.ttf" as="font" type="font/ttf" crossorigin>
  ${includeAdSense ? `<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_PUBLISHER_ID}" crossorigin="anonymous"></script>` : ""}
  <style>
    @font-face {
      font-family: "TierNotoSansJP";
      src: url("/assets/assets/fonts/NotoSansJP-TierSubset.ttf") format("truetype");
      font-display: swap;
      font-style: normal;
      font-weight: 500;
    }
    @font-face {
      font-family: "TierNotoSansKR";
      src: url("/assets/assets/fonts/NotoSansKR-TierSubset.ttf") format("truetype");
      font-display: swap;
      font-style: normal;
      font-weight: 500;
    }
    html, body {
      height: 100%;
      background: #0D0D0F;
      font-family: "TierNotoSansJP", "TierNotoSansKR", "Noto Sans",
        "Noto Sans TC", "Noto Sans JP", "Noto Sans KR", "PingFang TC",
        "Microsoft JhengHei", "Yu Gothic", YuGothic,
        "Yu Gothic UI", "Hiragino Kaku Gothic ProN", Meiryo,
        "Apple SD Gothic Neo", "Malgun Gothic", Arial, Helvetica, sans-serif;
      margin: 0;
    }
    #app-loading {
      align-items: center;
      background: #0D0D0F;
      color: #F4F4F7;
      display: flex;
      inset: 0;
      justify-content: center;
      position: fixed;
      z-index: 2147483647;
    }
    #app-loading[hidden] { display: none; }
    #ssr-publisher-content {
      box-sizing: border-box;
      color: #F4F4F7;
      line-height: 1.7;
      margin: 0 auto;
      max-width: 960px;
      padding: 32px 24px 96px;
    }
    #ssr-publisher-content h1 { line-height: 1.35; }
    #ssr-publisher-content li { margin: 6px 0; }
    .app-loading-content {
      align-items: center;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .app-loading-mark {
      animation: loading-pulse 1s ease-in-out infinite alternate;
      background: linear-gradient(135deg, #5AC8D8, #8B7CFF);
      border-radius: 12px;
      height: 8px;
      width: 72px;
    }
    .app-loading-label {
      font-family: Arial, "PingFang TC", "Microsoft JhengHei",
        "Yu Gothic", YuGothic, Meiryo,
        "Apple SD Gothic Neo", "Malgun Gothic", sans-serif;
      font-size: 16px;
      font-weight: 700;
      letter-spacing: .02em;
    }
    @keyframes loading-pulse {
      from { opacity: .45; transform: scaleX(.72); }
      to { opacity: 1; transform: scaleX(1); }
    }
    @media (prefers-reduced-motion: reduce) {
      .app-loading-mark { animation: none; }
    }
  </style>
${head}
</head>
<body>
  ${publisherContent}
  <div id="app-loading" role="status" aria-live="polite">
    <div class="app-loading-content">
      <div class="app-loading-mark" aria-hidden="true"></div>
      <div class="app-loading-label" id="app-loading-label">Tier Online</div>
    </div>
  </div>
  <script>
    window.addEventListener('flutter-first-frame', () => {
      window.setTimeout(() => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            document.getElementById('app-loading')?.setAttribute('hidden', '');
            document.getElementById('ssr-publisher-content')?.remove();
          });
        });
      }, 500);
    }, { once: true });
  </script>
  <script>
    (() => {
      const robots = document.querySelector('meta[name="robots"]');
      if (!robots) return;
      const updateRobots = () => {
        const path = location.pathname;
        const serverApprovedPath = robots.dataset.indexablePath;
        const indexable = serverApprovedPath === path;
        robots.content = indexable ? 'index,follow' : 'noindex,follow';
      };
      for (const method of ['pushState', 'replaceState']) {
        const original = history[method].bind(history);
        history[method] = (...args) => {
          const result = original(...args);
          updateRobots();
          return result;
        };
      }
      addEventListener('popstate', updateRobots);
      updateRobots();
    })();
  </script>
  <script>
    (async () => {
      if ('serviceWorker' in navigator) {
        try {
          const registrations = await navigator.serviceWorker.getRegistrations();
          await Promise.all(
            registrations.map((registration) => registration.unregister()),
          );
          if ('caches' in window) {
            const keys = await caches.keys();
            await Promise.all(
              keys
                .filter((key) => key.startsWith('flutter-app-cache'))
                .map((key) => caches.delete(key)),
            );
          }
        } catch (_) {
          // Always continue to Flutter, even when browser storage is blocked.
        }
      }
      const bootstrap = document.createElement('script');
      bootstrap.src = \`/flutter_bootstrap.js?v=\${Date.now()}\`;
      bootstrap.async = true;
      document.body.appendChild(bootstrap);
    })();
  </script>
</body>
</html>`;
}

function homePublisherContent(locale: SupportedLocale): string {
  const meta = DEFAULT_META[locale];
  return `<main id="ssr-publisher-content">
    <article>
      <h1>${escapeHtml(meta.title)}</h1>
      <p>${escapeHtml(meta.description)}</p>
      <p>${escapeHtml(HOME_PUBLISHER_COPY[locale])}</p>
    </article>
  </main>`;
}

function topicPublisherContent(
  locale: SupportedLocale,
  title: string,
  description: string,
  participants: number,
  items: Array<{name: string; rank?: string}>,
): string {
  const list = items.length === 0 ? "" : `<h2>Tier ranking</h2><ol>${items
    .map((item) => `<li>${item.rank ? `<strong>${escapeHtml(item.rank)}</strong> ` : ""}${escapeHtml(item.name)}</li>`)
    .join("")}</ol>`;
  return `<main id="ssr-publisher-content">
    <article>
      <h1>${escapeHtml(title)}</h1>
      <p>${escapeHtml(description)}</p>
      <p>${escapeHtml(TOPIC_STATS_LABEL[locale](participants, items.length))}</p>
      ${list}
    </article>
  </main>`;
}

export function canonicalLocalePath(path: string): string | null {
  if (path === "/zh-TW" || path.startsWith("/zh-TW/")) {
    return `/zh-tw${path.slice(6)}`;
  }
  if (path === "/pt-BR" || path.startsWith("/pt-BR/")) {
    return `/pt-br${path.slice(6)}`;
  }
  return null;
}

export const canonicalLocaleRedirect = onRequest((req, res) => {
  const targetPath = canonicalLocalePath(req.path);
  if (!targetPath) {
    res.status(404).send("Not found");
    return;
  }
  const queryIndex = req.originalUrl.indexOf("?");
  const query = queryIndex >= 0 ? req.originalUrl.slice(queryIndex) : "";
  res.redirect(301, `${targetPath}${query}`);
});

export const isSeoEligibleTopic = (
  data: Record<string, unknown>,
  itemCountOverride?: number,
): boolean => baseTopicIndexability(data, itemCountOverride).indexable;

export const seoEligibleTopicDocuments = <T extends {
  data: () => Record<string, unknown>;
}>(documents: T[]): T[] => documents.filter(
  (document) => isSeoEligibleTopic(document.data()),
);

export const isAdEligibleHomePath = (path: string): boolean => {
  const segments = path.split("/").filter(Boolean);
  return segments.length === 0 ||
    (segments.length === 1 && isSupportedLocale(segments[0]));
};

export const isIndexableHomePath = (path: string): boolean => {
  const segments = path.split("/").filter(Boolean);
  return segments.length === 1 && isSupportedLocale(segments[0]) &&
    path.endsWith("/");
};

export const sitemapStaticPaths = (): string[] =>
  SUPPORTED_LOCALES.map((locale) => `/${locale}/`);

export function isKnownHomeShellPath(path: string): boolean {
  const segments = path.split("/").filter(Boolean);
  if (segments.length === 0) return true;
  if (!isSupportedLocale(segments[0])) return false;
  const remainder = segments.slice(1);
  if (remainder.length === 0) return true;
  if (remainder.length === 1) {
    return [
      "search",
      "create",
      "template",
      "user",
      "settings",
      "terms",
      "privacy",
      "contact",
    ].includes(remainder[0]);
  }
  return remainder.length === 2 &&
    remainder[0] === "auth" && remainder[1] === "action";
}

// ルート("/")および対応言語配下(tier個別ページを除く)の共有プレビュー用。
// SNS/検索エンジンのクローラーはJavaScriptを実行しないため、静的index.html
// に埋め込んだメタタグは常に固定言語になってしまう。このハンドラで言語ごとに
// 正しいtitle/description/og:imageを返しつつ、実利用者には通常どおり
// flutter_bootstrap.jsでアプリ本体を読み込ませる。
export const renderHome = onRequest(async (req, res) => {
  const segments = req.path.split("/").filter(Boolean);
  const pathLocale = isSupportedLocale(segments[0])
    ? segments[0]
    : null;
  const locale = pathLocale ?? localeFromAcceptLanguage(req.get("accept-language"));
  if (!isKnownHomeShellPath(req.path)) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }
  // Auto Ads can place units anywhere the loader is present. Only the public
  // home itself is unconditionally content-rich at SSR time; action routes,
  // auth/settings and searches with an unknown result count remain ad-free.
  const production = isProductionHost(requestHost(req));
  const includeAdSense = production && isAdEligibleHomePath(req.path);
  const indexable = production && isIndexableHomePath(req.path);
  if (!production) res.set("X-Robots-Tag", "noindex, nofollow");
  const meta = DEFAULT_META[locale];
  const canonical = pathLocale == null ? localizedHomeUrl(locale) :
    canonicalPageUrl(locale, segments.slice(1));

  const alternates = indexable ? SUPPORTED_LOCALES.map(
    (code) => `  <link rel="alternate" hreflang="${hreflang(code)}" href="${localizedHomeUrl(code)}">`,
  ).join("\n") : "";

  const head = `  <title>${escapeHtml(meta.title)}</title>
  <meta name="description" content="${escapeHtml(meta.description)}">
${robotsHead(indexable, indexable ? localizedHomePath(locale) : undefined)}
  <link rel="canonical" href="${canonical}">
${alternates}
${indexable ? `  <link rel="alternate" hreflang="x-default" href="${localizedHomeUrl("ja")}">` : ""}
  <meta property="og:type" content="website">
  <meta property="og:title" content="${escapeHtml(meta.title)}">
  <meta property="og:description" content="${escapeHtml(meta.description)}">
  <meta property="og:image" content="${HOME_IMAGE[locale]}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="summary_large_image">`;

  res.set("Cache-Control", "public, max-age=0, s-maxage=600");
  res.status(200).send(renderShell(
    locale,
    head,
    homePublisherContent(locale),
    includeAdSense,
  ));
});

export const renderTopic = onRequest(async (req, res) => {
  const segments = req.path.split("/").filter(Boolean);
  const locale = parseLocale(segments[0]);
  const routeKind = segments[1];
  const topicId = segments[2];
  const production = isProductionHost(requestHost(req));
  if (!production) res.set("X-Robots-Tag", "noindex, nofollow");
  if ((routeKind !== "tier" && routeKind !== "preset") || !topicId) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }

  if (isGenericPresetTopic(topicId) && !topicId.startsWith("preset-")) {
    if (routeKind !== "preset") {
      const queryIndex = req.originalUrl.indexOf("?");
      const query = queryIndex >= 0 ? req.originalUrl.slice(queryIndex) : "";
      res.redirect(301, `${localizedTopicPath(locale, topicId, true)}${query}`);
      return;
    }
    const meta = genericPresetMeta(locale);
    const canonical = localizedTopicUrl(locale, topicId, true);
    const alternates = production ? SUPPORTED_LOCALES.map(
      (code) => `  <link rel="alternate" hreflang="${hreflang(code)}" href="${localizedTopicUrl(code, topicId, true)}">`,
    ).join("\n") : "";
    const head = `  <title>${escapeHtml(meta.title)}</title>
  <meta name="description" content="${escapeHtml(meta.description)}">
${robotsHead(production, production ? localizedTopicPath(locale, topicId, true) : undefined)}
  <link rel="canonical" href="${canonical}">
${alternates}
${production ? `  <link rel="alternate" hreflang="x-default" href="${localizedTopicUrl("ja", topicId, true)}">` : ""}
  <meta property="og:type" content="article">
  <meta property="og:title" content="${escapeHtml(meta.title)}">
  <meta property="og:description" content="${escapeHtml(meta.description)}">
  <meta property="og:image" content="${DEFAULT_IMAGE}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="summary_large_image">`;
    res.set("Cache-Control", "public, max-age=0, s-maxage=600");
    res.status(200).send(renderShell(
      locale,
      head,
      topicPublisherContent(locale, meta.title, meta.description, 0, []),
      production,
    ));
    return;
  }

  if (routeKind !== "tier" && routeKind !== "preset") {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }

  const firestore = getFirestore();
  const topicRef = firestore.collection("topics").doc(topicId);
  const topicSnapshot = await topicRef.get();

  const data = topicSnapshot.data() ?? {};
  if (!topicSnapshot.exists) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }
  if (data.deleting === true || data.deleted === true || data.isDeleted === true) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(410).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }
  if (data.isPublic !== true ||
      (data.moderationStatus != null && data.moderationStatus !== "approved") ||
      data.hidden === true || data.isHidden === true || data.isSpam === true) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send(renderShell(locale, NOINDEX_HEAD, "", false));
    return;
  }
  const itemsSnapshot = await topicRef
    .collection("items")
    .orderBy("sortIndex")
    .limit(100)
    .get();

  type SeoTopicContent = {
    title: string;
    description?: string;
    itemNames?: Record<string, string>;
  };
  const sourceLocale = normalizeLocale(
    data.sourceLocale ?? data.sourceLanguage ?? data.contentLanguage,
    "ja",
  );
  const localizedContent: Partial<Record<SupportedLocale, SeoTopicContent>> = {
    [sourceLocale]: {
      title: (data.title as string | undefined) ?? DEFAULT_META[locale].title,
      description: data.description as string | undefined,
    },
  };
  const translations = data.translations;
  if (translations && typeof translations === "object") {
    for (const [rawLocale, rawValue] of Object.entries(translations)) {
      if (!rawValue || typeof rawValue !== "object") continue;
      const value = rawValue as Record<string, unknown>;
      if (value.status !== "completed" || typeof value.title !== "string") continue;
      localizedContent[normalizeLocale(rawLocale)] = {
        title: value.title,
        description: typeof value.description === "string" ?
          value.description : undefined,
        itemNames: value.itemNames && typeof value.itemNames === "object" ?
          value.itemNames as Record<string, string> : undefined,
      };
    }
  }
  const selectedContent = resolveLocalizedValue(locale, localizedContent) ??
    localizedContent[sourceLocale]!;
  const title = escapeHtml(selectedContent.title);
  const rawDescription = selectedContent.description?.trim();
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
  const canonical = localizedTopicUrl(
    locale,
    topicId,
    routeKind === "preset",
  );
  const community = data.community && typeof data.community === "object" ?
    data.community as Record<string, unknown> : {};
  const items = itemsSnapshot.docs.map((doc, index) => {
    const item = doc.data();
    const translatedName = selectedContent.itemNames?.[doc.id];
    const rawName = typeof translatedName === "string" ? translatedName :
      typeof item.name === "string" ? item.name : `Item ${index + 1}`;
    const rawRank = community[doc.id];
    const rank = typeof rawRank === "string" ? rawRank.toUpperCase() : undefined;
    return {name: rawName, rank};
  });
  const participants = typeof data.participants === "number" ?
    data.participants : 0;

  const indexableLocales = production ? indexableTopicLocales(data) : [];
  const localeIndexability = localeTopicIndexability(data, locale);
  const indexable = production && localeIndexability.indexable;
  const alternates = indexableLocales.map(
    (code) =>
      `  <link rel="alternate" hreflang="${hreflang(code)}" href="${localizedTopicUrl(code, topicId, routeKind === 'preset')}">`,
  ).join("\n");
  const xDefaultLocale = indexableLocales.includes(sourceLocale) ?
    sourceLocale : indexableLocales[0];

  const head = `  <title>${title}</title>
  <meta name="description" content="${description}">
${robotsHead(
    indexable,
    indexable ? localizedTopicPath(locale, topicId, routeKind === "preset") : undefined,
  )}
  <link rel="canonical" href="${canonical}">
${alternates}
${xDefaultLocale == null ? "" :
    `  <link rel="alternate" hreflang="x-default" href="${localizedTopicUrl(xDefaultLocale, topicId, routeKind === "preset")}">`}
  <meta property="og:type" content="article">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  <meta property="og:image" content="${image}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="summary_large_image">`;

  res.set("Cache-Control", "public, max-age=0, s-maxage=600");
  res.status(200).send(renderShell(
    locale,
    head,
    topicPublisherContent(
      locale,
      selectedContent.title,
      rawDescription && rawDescription.length > 0 ?
        rawDescription : DEFAULT_META[locale].description,
      participants,
      items,
    ),
    indexable,
  ));
});

const SITEMAP_PAGE_SIZE = 500;
const SITEMAP_CACHE_MILLIS = 60 * 60 * 1000;
let cachedSitemaps: {expiresAt: number; bundle: SitemapBundle} | undefined;
let sitemapBuild: Promise<SitemapBundle> | undefined;

export async function loadSitemapCandidates(): Promise<SitemapTopicDocument[]> {
  const firestore = getFirestore();
  const documents: SitemapTopicDocument[] = [];
  let cursor: string | undefined;
  while (true) {
    // moderationStatus未設定の古いTierも候補に含めたいので、ここでは
    // isPublicだけで絞り込み、承認判定はbaseTopicIndexability側(moderation
    //未設定=approved扱い)に任せる。
    let query = firestore.collection("topics")
      .where("isPublic", "==", true)
      .orderBy(FieldPath.documentId())
      .limit(SITEMAP_PAGE_SIZE)
      .select(
        "title",
        "status",
        "itemCount",
        "contentVersion",
        "contentLanguage",
        "sourceLanguage",
        "sourceLocale",
        "translations",
        "moderationStatus",
        "isPublic",
        "hidden",
        "isHidden",
        "deleting",
        "deleted",
        "isDeleted",
        "deletedAt",
        "isSpam",
        "spam",
        "isDuplicate",
        "duplicateOf",
        "createdAt",
        "updatedAt",
      );
    if (cursor != null) query = query.startAfter(cursor);
    const snapshot = await query.get();
    documents.push(...snapshot.docs.map((document) => ({
      id: document.id,
      data: document.data(),
    })));
    if (snapshot.size < SITEMAP_PAGE_SIZE) break;
    cursor = snapshot.docs.at(-1)?.id;
    if (cursor == null) break;
  }
  return documents;
}

async function loadPrefilteredExclusionCounts(): Promise<{
  private: number;
  moderation: number;
}> {
  const topics = getFirestore().collection("topics");
  try {
    const [all, publicTopics, approvedPublicTopics] = await Promise.all([
      topics.count().get(),
      topics.where("isPublic", "==", true).count().get(),
      topics
        .where("isPublic", "==", true)
        .where("moderationStatus", "==", "approved")
        .count()
        .get(),
    ]);
    const allCount = all.data().count;
    const publicCount = publicTopics.data().count;
    const approvedCount = approvedPublicTopics.data().count;
    return {
      private: Math.max(0, allCount - publicCount),
      moderation: Math.max(0, publicCount - approvedCount),
    };
  } catch (error) {
    console.warn("sitemap exclusion counts unavailable", error);
    return {private: 0, moderation: 0};
  }
}

export async function generateSitemapBundle(): Promise<SitemapBundle> {
  const [documents, prefiltered] = await Promise.all([
    loadSitemapCandidates(),
    loadPrefilteredExclusionCounts(),
  ]);
  const bundle = buildSitemapBundle(documents);
  bundle.stats.excludedByReason.private =
    (bundle.stats.excludedByReason.private ?? 0) +
    prefiltered.private * SUPPORTED_LOCALES.length;
  bundle.stats.excludedByReason.moderation =
    (bundle.stats.excludedByReason.moderation ?? 0) +
    prefiltered.moderation * SUPPORTED_LOCALES.length;
  return bundle;
}

async function sitemapBundle(): Promise<SitemapBundle> {
  if (cachedSitemaps != null && cachedSitemaps.expiresAt > Date.now()) {
    return cachedSitemaps.bundle;
  }
  sitemapBuild ??= generateSitemapBundle()
    .then((bundle) => {
      cachedSitemaps = {
        expiresAt: Date.now() + SITEMAP_CACHE_MILLIS,
        bundle,
      };
      console.info("sitemap generated", bundle.stats);
      return bundle;
    })
    .finally(() => {
      sitemapBuild = undefined;
    });
  return sitemapBuild;
}

function requestHost(req: {get: (name: string) => string | undefined}): string | undefined {
  return req.get("x-forwarded-host") ?? req.get("host");
}

function rejectNonProductionSeo(
  req: {get: (name: string) => string | undefined},
  res: {set: (name: string, value: string) => unknown; status: (code: number) => {
    send: (body: string) => unknown;
  }},
): boolean {
  if (isProductionHost(requestHost(req))) return false;
  res.set("X-Robots-Tag", "noindex, nofollow");
  res.status(404).send("Not found");
  return true;
}

export const sitemap = onRequest(async (req, res) => {
  if (rejectNonProductionSeo(req, res)) return;
  res.set("Content-Type", "application/xml; charset=utf-8");
  res.set("Cache-Control", "public, max-age=0, s-maxage=21600, stale-while-revalidate=86400");
  res.status(200).send(sitemapIndexXml(await sitemapBundle()));
});

export const sitemapLocale = onRequest(async (req, res) => {
  if (rejectNonProductionSeo(req, res)) return;
  const match = /^\/sitemap-(ja|en|ko|zh-tw|pt-br)(?:-([1-9][0-9]*))?\.xml$/.exec(req.path);
  if (!match || !isSupportedLocale(match[1])) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send("Not found");
    return;
  }
  const locale = match[1];
  const requestedPage = match[2] == null ? 1 : Number(match[2]);
  const bundle = await sitemapBundle();
  const page = bundle.pages[locale][requestedPage - 1];
  if (page == null) {
    res.set("X-Robots-Tag", "noindex, follow");
    res.status(404).send("Not found");
    return;
  }
  res.set("Content-Type", "application/xml; charset=utf-8");
  res.set("Cache-Control", "public, max-age=0, s-maxage=21600, stale-while-revalidate=86400");
  res.set("X-Sitemap-Urls", String(page.entries.length));
  res.set("X-Sitemap-Page", String(requestedPage));
  res.set(
    "X-Sitemap-Excluded",
    String(Object.values(bundle.stats.excludedByReason)
      .reduce((sum, count) => sum + (count ?? 0), 0)),
  );
  res.status(200).send(page.xml);
});

export const robots = onRequest((req, res) => {
  const production = isProductionHost(requestHost(req));
  res.set("Content-Type", "text/plain; charset=utf-8");
  res.set("Cache-Control", "public, max-age=0, s-maxage=3600");
  if (!production) res.set("X-Robots-Tag", "noindex, nofollow");
  res.status(200).send(robotsText(production));
});
