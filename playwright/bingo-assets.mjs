// Generates Bingo Online's static images into web_bingo/:
//   og-image-{locale}.png (1200x630 share previews), favicon.png and
//   icons/Icon-{192,512}.png, icons/Icon-maskable-{192,512}.png.
//
//   npm --prefix playwright install
//   node playwright/bingo-assets.mjs
import {chromium} from 'playwright';
import {mkdirSync, readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'web_bingo');
const fonts = join(root, 'assets', 'fonts');

// Mirrors appName/tagline in lib/bingo/l10n/bingo_localizations.dart
// (with line breaks chosen for the image).
const copy = {
  ja: {name: 'ビンゴオンライン', tagline: 'つくって、くばって、<br>みんなでBINGO。', font: 'NotoJP'},
  ko: {name: '빙고 온라인', tagline: '만들고, 나누고,<br>다 함께 BINGO.', font: 'NotoKR'},
  en: {name: 'Bingo Online', tagline: 'Make it, deal it, BINGO together.', font: 'NotoJP'},
  'zh-tw': {name: '賓果線上版', tagline: '製作、發卡，<br>大家一起 BINGO。', font: 'WenQuanYi Zen Hei'},
  'pt-br': {name: 'Bingo Online', tagline: 'Crie, distribua e faça BINGO com todo mundo.', font: 'NotoJP'},
};

const colors = {
  primary: '#F2552C', primarySoft: '#FFE9E2', gold: '#FFB400', goldSoft: '#FFF4D6',
  blue: '#2F6BFF', surface: '#EDEFF4', ink: '#1B1C22', muted: '#656B78',
};

const fontFaces = `
  @font-face { font-family: NotoJP; src: url('${pathToFileURL(join(fonts, 'NotoSansJP-TierSubset.ttf'))}'); }
  @font-face { font-family: NotoKR; src: url('${pathToFileURL(join(fonts, 'NotoSansKR-TierSubset.ttf'))}'); }
`;

// 5x5 card: a completed diagonal (gold), some marks (orange), FREE center.
function card(size) {
  const line = new Set([0, 6, 12, 18, 24]);
  const marked = new Set([3, 8, 15, 21]);
  const cells = Array.from({length: 25}, (_, i) => {
    const free = i === 12;
    const bg = free || line.has(i) ? colors.goldSoft : marked.has(i) ? colors.primarySoft : '#fff';
    const border = line.has(i) && !free ? colors.gold : marked.has(i) ? colors.primary : '#E1E4EB';
    const ring = (line.has(i) && !free) || marked.has(i)
      ? `<div style="position:absolute;inset:16%;border-radius:50%;border:${size / 60}px solid ${line.has(i) ? colors.gold : colors.primary};opacity:.55"></div>`
      : '';
    const label = free ? `<span style="font:800 ${size / 16}px Arial;color:#8A5A00">FREE</span>` : '';
    return `<div style="position:relative;display:flex;align-items:center;justify-content:center;background:${bg};border:${line.has(i) || marked.has(i) ? 3 : 2}px solid ${border};border-radius:${size / 28}px">${ring}${label}</div>`;
  }).join('');
  return `<div style="display:grid;grid-template-columns:repeat(5,1fr);gap:${size / 55}px;width:${size}px;height:${size}px">${cells}</div>`;
}

function mark(size) {
  const fill = (i) => [0, 4, 8].includes(i) ? colors.primary : [2, 6].includes(i) ? colors.gold : colors.surface;
  const cells = Array.from({length: 9}, (_, i) => `<div style="background:${fill(i)};border-radius:${size / 9}px"></div>`).join('');
  return `<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:${size / 14}px;width:${size}px;height:${size}px">${cells}</div>`;
}

function ogHtml(locale) {
  const {name, tagline, font} = copy[locale];
  return `<!doctype html><html><head><meta charset="utf-8"><style>${fontFaces}
    html,body{margin:0;width:1200px;height:630px;background:#fff;font-family:'${font}','NotoJP','NotoKR','WenQuanYi Zen Hei',sans-serif;color:${colors.ink}}
  </style></head><body>
  <div style="position:absolute;inset:0;background:linear-gradient(135deg,#FFF4EF 0%,#FFFBEA 55%,#fff 100%)"></div>
  <div style="position:absolute;left:80px;top:0;bottom:0;width:560px;display:flex;flex-direction:column;justify-content:center;gap:28px">
    <div style="display:flex;align-items:center;gap:20px">${mark(72)}
      <div style="font-size:52px;font-weight:900;letter-spacing:-.5px">${name}</div></div>
    <div style="font-size:44px;font-weight:900;line-height:1.3">${tagline}</div>
    <div style="display:flex;gap:12px">
      <span style="padding:10px 22px;border-radius:999px;background:${colors.primary};color:#fff;font:800 26px Arial">BINGO!</span>
      <span style="padding:10px 22px;border-radius:999px;background:#E6EEFF;color:${colors.blue};font:800 26px Arial">5×5</span>
    </div>
  </div>
  <div style="position:absolute;right:90px;top:75px;padding:24px;background:#fff;border-radius:36px;border:3px solid ${colors.gold};box-shadow:0 18px 50px rgba(242,85,44,.15)">${card(430)}</div>
  </body></html>`;
}

function iconHtml(size, maskable) {
  const inner = maskable ? size * 0.62 : size * 0.78;
  return `<!doctype html><html><head><style>html,body{margin:0;width:${size}px;height:${size}px}</style></head><body>
    <div style="width:${size}px;height:${size}px;background:#fff;border-radius:${maskable ? 0 : size * 0.22}px;display:flex;align-items:center;justify-content:center">${mark(inner)}</div>
  </body></html>`;
}

mkdirSync(join(out, 'icons'), {recursive: true});
const browser = await chromium.launch();
const render = async (html, width, height, path, transparent = false) => {
  const page = await browser.newPage({viewport: {width, height}});
  await page.setContent(html, {waitUntil: 'networkidle'});
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({path, omitBackground: transparent});
  await page.close();
};
for (const locale of Object.keys(copy)) {
  await render(ogHtml(locale), 1200, 630, join(out, `og-image-${locale}.png`));
}
for (const size of [192, 512]) {
  await render(iconHtml(size, false), size, size, join(out, 'icons', `Icon-${size}.png`), true);
  await render(iconHtml(size, true), size, size, join(out, 'icons', `Icon-maskable-${size}.png`));
}
await render(iconHtml(64, false), 64, 64, join(out, 'favicon.png'), true);
await browser.close();
console.log('Bingo images written to', out, readFileSync(join(out, 'og-image-ja.png')).length > 0 ? '' : '(empty?)');
