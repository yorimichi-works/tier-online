/**
 * Link previews (OGP) and sitemap for Bingo Online.
 *
 * Crawlers of X, LINE, Slack etc. do not run JavaScript, so the static
 * web_bingo/index.html would always show the generic Japanese metadata.
 * renderBingo serves the same shell with the `<!--bingo-meta-->` block
 * replaced by per-language and per-board metadata. Unlike Tier's seo.ts it
 * reuses the deployed index.html instead of duplicating it.
 */
import {getFirestore} from "firebase-admin/firestore";
import {defineString} from "firebase-functions/params";
import {onRequest} from "firebase-functions/v2/https";

import {
  hreflang,
  isSupportedLocale,
  localeFromAcceptLanguage,
  SUPPORTED_LOCALES,
  SupportedLocale,
} from "./internationalization";

export const bingoSiteOrigin = defineString("BINGO_SITE_ORIGIN", {
  default: "https://bingo-online.web.app",
});

const OG_LOCALE: Record<SupportedLocale, string> = {
  ja: "ja_JP",
  ko: "ko_KR",
  "zh-tw": "zh_TW",
  "pt-br": "pt_BR",
  en: "en_US",
};

// Keep in sync with web_bingo/index.html.
export const BINGO_META: Record<SupportedLocale, {
  name: string;
  separator: string;
  title: string;
  description: string;
  boardDescription: string;
}> = {
  ja: {
    name: "ビンゴオンライン",
    separator: "｜",
    title: "ビンゴオンライン｜ビンゴを作って、みんなで参加",
    description: "ビンゴを作って公開、みんなで参加。結果をコメントでシェアしよう。",
    boardDescription: "{size}×{size}のビンゴ。参加すると自分だけのカードが配られます。",
  },
  ko: {
    name: "빙고 온라인",
    separator: " | ",
    title: "빙고 온라인 | 빙고를 만들고 다 함께 참여",
    description: "빙고를 만들어 공개하고 다 함께 참여해 보세요. 결과는 댓글로 공유할 수 있어요.",
    boardDescription: "{size}×{size} 빙고. 참여하면 나만의 카드가 배부됩니다.",
  },
  "zh-tw": {
    name: "賓果線上版",
    separator: "｜",
    title: "賓果線上版｜製作賓果，大家一起參加",
    description: "製作並公開賓果，大家一起參加，還能在留言分享結果。",
    boardDescription: "{size}×{size} 賓果。參加後會發給你一張專屬卡片。",
  },
  "pt-br": {
    name: "Bingo Online",
    separator: " | ",
    title: "Bingo Online | Crie um bingo e jogue com todos",
    description:
      "Crie e publique bingos, jogue com todo mundo e compartilhe o resultado nos comentários.",
    boardDescription: "Bingo {size}×{size}. Participe e receba sua própria cartela.",
  },
  en: {
    name: "Bingo Online",
    separator: " | ",
    title: "Bingo Online | Make a bingo card and play together",
    description:
      "Create and publish bingo cards, play together and share your result in the comments.",
    boardDescription: "A {size}×{size} bingo. Join to get your own card.",
  },
};

export interface BingoPageBoard {
  id: string;
  title: string;
  description: string;
  size: number;
  imageUrl?: string;
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function isPreviewImage(url: unknown): url is string {
  if (typeof url !== "string") return false;
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    return parsed.protocol === "https:" && (
      host === "firebasestorage.googleapis.com" ||
      host === "mzstatic.com" || host.endsWith(".mzstatic.com")
    );
  } catch {
    return false;
  }
}

/** Board fields for a preview, or null when it must not be exposed. */
export function boardForPreview(
  id: string,
  data: Record<string, unknown> | undefined,
): BingoPageBoard | null {
  if (!data || data.listed !== true || data.deleting === true) return null;
  const cells = Array.isArray(data.cells) ? data.cells : [];
  const image = cells
    .map((cell) => (cell as {imageUrl?: unknown} | null)?.imageUrl)
    .find(isPreviewImage);
  return {
    id,
    title: typeof data.title === "string" ? data.title : "",
    description: typeof data.description === "string" ? data.description : "",
    size: Number(data.size) || 5,
    imageUrl: image,
  };
}

export function bingoMetaHead(params: {
  origin: string;
  locale: SupportedLocale;
  path: string;
  board?: BingoPageBoard | null;
  notFound?: boolean;
}): string {
  const {origin, locale, board} = params;
  const meta = BINGO_META[locale];
  const title = board ? `${board.title}${meta.separator}${meta.name}` : meta.title;
  const description = board ?
    (board.description.trim() ||
      meta.boardDescription.replace(/\{size\}/g, String(board.size))) :
    meta.description;
  const image = board?.imageUrl ?? `${origin}/og-image-${locale}.png`;
  const canonicalPath = board ? `/${locale}/bingo/${board.id}` : params.path;
  const canonical = `${origin}${canonicalPath}`;
  const alternatePath = (code: SupportedLocale) =>
    board ? `/${code}/bingo/${board.id}` : `/${code}/`;
  const alternates = board || params.path === `/${locale}/` ?
    SUPPORTED_LOCALES.map((code) =>
      `  <link rel="alternate" hreflang="${hreflang(code)}" href="${origin}${alternatePath(code)}">`,
    ).join("\n") + "\n" :
    "";
  // A square jacket reads best as a small card; the generic image is wide.
  const card = board?.imageUrl ? "summary" : "summary_large_image";
  return `<!--bingo-meta-->
  <meta name="bingo-rendered" content="1">
  <title>${escapeHtml(title)}</title>
  <meta name="description" content="${escapeHtml(description)}">
${params.notFound ? "  <meta name=\"robots\" content=\"noindex\">\n" : ""}\
  <link rel="canonical" href="${escapeHtml(canonical)}">
${alternates}\
  <meta property="og:site_name" content="${escapeHtml(meta.name)}">
  <meta property="og:type" content="${board ? "article" : "website"}">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(description)}">
  <meta property="og:image" content="${escapeHtml(image)}">
  <meta property="og:url" content="${escapeHtml(canonical)}">
  <meta property="og:locale" content="${OG_LOCALE[locale]}">
  <meta name="twitter:card" content="${card}">
  <!--/bingo-meta-->`;
}

/** Replaces the marked metadata block of the shell (or appends to head). */
export function injectBingoMeta(shell: string, head: string): string {
  const start = shell.indexOf("<!--bingo-meta-->");
  const endMarker = "<!--/bingo-meta-->";
  const end = shell.indexOf(endMarker);
  if (start >= 0 && end > start) {
    return shell.slice(0, start) + head + shell.slice(end + endMarker.length);
  }
  return shell.replace("</head>", `${head}\n</head>`);
}

function fallbackShell(): string {
  return `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>html,body{margin:0;height:100%;background:#fff}</style>
</head>
<body>
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;
}

let shellCache: {origin: string; html: string; fetchedAt: number} | null = null;
const SHELL_TTL_MS = 10 * 60 * 1000;

async function loadShell(origin: string): Promise<string> {
  const now = Date.now();
  if (shellCache && shellCache.origin === origin &&
    now - shellCache.fetchedAt < SHELL_TTL_MS) {
    return shellCache.html;
  }
  try {
    const response = await fetch(`${origin}/index.html`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const html = await response.text();
    shellCache = {origin, html, fetchedAt: now};
    return html;
  } catch (error) {
    console.error("renderBingo: falling back to a minimal shell", error);
    return shellCache?.html ?? fallbackShell();
  }
}

export const renderBingo = onRequest(async (req, res) => {
  const origin = bingoSiteOrigin.value().replace(/\/+$/, "");
  const segments = req.path.split("/").filter(Boolean);
  const pathLocale = isSupportedLocale(segments[0]) ? segments[0] : null;
  const locale = pathLocale ??
    localeFromAcceptLanguage(req.get("accept-language"));
  const shell = await loadShell(origin);

  let board: BingoPageBoard | null = null;
  let notFound = false;
  if (segments[1] === "bingo" && segments[2]) {
    const id = segments[2];
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
      notFound = true;
    } else {
      const snapshot = await getFirestore().collection("bingos").doc(id).get();
      board = boardForPreview(id, snapshot.data());
      notFound = board === null && !id.startsWith("sample-");
    }
  }

  const head = bingoMetaHead({
    origin,
    locale,
    path: pathLocale ? `/${locale}/${segments.slice(1).join("/")}` : `/${locale}/`,
    board,
    notFound,
  });
  res.set("Cache-Control", "public, max-age=0, s-maxage=600");
  res.status(notFound ? 404 : 200).send(injectBingoMeta(shell, head));
});

export const bingoSitemap = onRequest(async (_req, res) => {
  const origin = bingoSiteOrigin.value().replace(/\/+$/, "");
  const snapshot = await getFirestore()
    .collection("bingos")
    .where("listed", "==", true)
    .orderBy("createdAt", "desc")
    .limit(5000)
    .select("contentLanguage")
    .get();
  const urls = [
    ...SUPPORTED_LOCALES.map((locale) => `${origin}/${locale}/`),
    ...snapshot.docs.map((doc) => {
      const language = doc.get("contentLanguage");
      const locale = isSupportedLocale(language) ? language : "ja";
      return `${origin}/${locale}/bingo/${doc.id}`;
    }),
  ];
  res.set("Content-Type", "application/xml; charset=utf-8");
  res.set("Cache-Control", "public, max-age=0, s-maxage=3600");
  res.status(200).send(`<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((url) => `  <url><loc>${escapeHtml(url)}</loc></url>`).join("\n")}
</urlset>`);
});
