import { mkdirSync } from 'node:fs';
import { expect, test } from '@playwright/test';

interface RouteDef {
  name: string;
  path: string;
  scrollAndReshot?: boolean;
}

// main.dart の onGenerateRoute / AppShell のタブ構成から拾った、
// 実際に到達可能な画面のみを対象にする(存在しない画面は追加しない)。
const routes: RouteDef[] = [
  { name: 'home', path: '/ja/' },
  { name: 'search', path: '/ja/search' },
  { name: 'create', path: '/ja/create' },
  { name: 'mytier', path: '/ja/user' },
  { name: 'settings', path: '/ja/settings' },
  { name: 'tier-detail', path: '/ja/tier/yokai', scrollAndReshot: true },
  { name: 'home-ko', path: '/ko/' },
  { name: 'home-en', path: '/en/' },
];

// ネットワーク由来(Firebase/Analytics/広告/外部API)の一時エラーはUIバグと区別する。
const ignoredPatterns = [
  /firestore\.googleapis\.com/i,
  /googleapis\.com/i,
  /googlesyndication/i,
  /doubleclick/i,
  /google-analytics/i,
  /gstatic\.com/i,
  /identitytoolkit/i,
  /net::ERR_INTERNET_DISCONNECTED/i,
  /net::ERR_NAME_NOT_RESOLVED/i,
  /net::ERR_CONNECTION_REFUSED/i, // ローカル環境でFirebaseに到達できない場合
];

const badPatterns = [
  /RenderFlex/i,
  /overflowed/i,
  /bottom overflowed/i,
  /right overflowed/i,
  /Failed assertion/i,
  /Uncaught \(in promise\)/i,
  /\bNaN\b/,
  /\bInfinity\b/,
  /Exception/i,
  /layout overflow/i,
];

function categoryForProject(projectName: string): string {
  if (projectName.startsWith('desktop')) return 'desktop';
  if (projectName.startsWith('laptop')) return 'laptop';
  if (projectName.startsWith('tablet')) return 'tablet';
  if (projectName.startsWith('mobile-small')) return 'mobile-small';
  return 'mobile';
}

for (const route of routes) {
  test(`crawl: ${route.name} (${route.path})`, async ({ page }, testInfo) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];
    const failedRequests: string[] = [];

    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => pageErrors.push(String(err)));
    page.on('requestfailed', (req) => {
      failedRequests.push(
        `${req.method()} ${req.url()} :: ${req.failure()?.errorText ?? 'unknown'}`,
      );
    });

    await page.goto(route.path, { waitUntil: 'load' });
    // web/index.html の #app-loading が hidden になるのを、Flutter初回描画完了
    // の確実なシグナルとして待つ(固定timeoutだと並列実行時のCPU競合で
    // 誤って「読み込み中」のまま撮影してしまうことがある)。
    await page
      .locator('#app-loading[hidden]')
      .waitFor({ state: 'attached', timeout: 45_000 })
      .catch(() => {});
    await page.waitForTimeout(1500);

    const category = categoryForProject(testInfo.project.name);
    const screenshotRoot =
      process.env.SCREENSHOT_DIR ?? '../artifacts/screenshots';
    const dir = `${screenshotRoot}/${category}`;
    mkdirSync(dir, { recursive: true });
    await page.screenshot({
      path: `${dir}/${route.name}-${category}.png`,
      fullPage: true,
    });

    if (route.scrollAndReshot) {
      for (let i = 0; i < 10; i++) {
        await page.mouse.wheel(0, 500);
        await page.waitForTimeout(150);
      }
      await page.waitForTimeout(500);
      await page.screenshot({
        path: `${dir}/${route.name}-scrolled-${category}.png`,
        fullPage: true,
      });
    }

    const meaningfulConsoleErrors = consoleErrors.filter(
      (entry) => !ignoredPatterns.some((pattern) => pattern.test(entry)),
    );
    const meaningfulFailedRequests = failedRequests.filter(
      (entry) => !ignoredPatterns.some((pattern) => pattern.test(entry)),
    );

    await testInfo.attach('console-errors.json', {
      body: JSON.stringify(meaningfulConsoleErrors, null, 2),
      contentType: 'application/json',
    });
    await testInfo.attach('page-errors.json', {
      body: JSON.stringify(pageErrors, null, 2),
      contentType: 'application/json',
    });
    await testInfo.attach('failed-requests.json', {
      body: JSON.stringify(meaningfulFailedRequests, null, 2),
      contentType: 'application/json',
    });

    const suspiciousConsole = meaningfulConsoleErrors.filter((entry) =>
      badPatterns.some((pattern) => pattern.test(entry)),
    );
    const suspiciousPageErrors = pageErrors.filter((entry) =>
      badPatterns.some((pattern) => pattern.test(entry)),
    );

    expect(
      suspiciousConsole.length === 0 && suspiciousPageErrors.length === 0,
      `疑わしいエラーを検出しました:\nconsole: ${JSON.stringify(suspiciousConsole)}\npageerror: ${JSON.stringify(suspiciousPageErrors)}`,
    ).toBeTruthy();
  });
}
