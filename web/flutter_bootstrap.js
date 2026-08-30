{{flutter_js}}
{{flutter_build_config}}

function withStartupTimeout(promise, timeoutMs, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = window.setTimeout(
      () => reject(new Error(`${label} timed out after ${timeoutMs}ms`)),
      timeoutMs,
    );
  });
  return Promise.race([promise, timeout]).finally(() => {
    window.clearTimeout(timer);
  });
}

async function waitForTierFonts() {
  if (!document.fonts || typeof document.fonts.load !== 'function') {
    return;
  }

  // Warm the browser cache before CanvasKit initializes. Flutter registers
  // the same local font files from FontManifest.json, so they are available
  // on its first text layout instead of arriving one frame later.
  await Promise.all([
    document.fonts.load('500 16px "TierNotoSansJP"', 'Tier表オンライン 髙橋 齊藤'),
    document.fonts.load('500 16px "TierNotoSansKR"', '티어표 온라인 한국어 테스트'),
  ]);
  await document.fonts.ready;
}

async function clearLegacyFlutterWorker() {
  if (!('serviceWorker' in navigator)) return;
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
    // Cache cleanup must never prevent the app from starting.
  }
}

(async () => {
  let fontsReady = false;
  const startupResults = await Promise.allSettled([
    withStartupTimeout(clearLegacyFlutterWorker(), 1500, 'Cache cleanup'),
    withStartupTimeout(waitForTierFonts(), 2500, 'Tier font preload').then(() => {
      fontsReady = true;
    }),
  ]);
  if (fontsReady) {
    document.documentElement.dataset.tierFontsReady = 'true';
  }
  for (const result of startupResults) {
    if (result.status === 'rejected') {
      // Startup helpers are best-effort. Flutter must always be allowed to
      // render with its bundled or OS fallback fonts.
      console.warn('Tier startup helper was skipped.', result.reason);
    }
  }

  await _flutter.loader.load({
    config: {
      // The release build already ships CanvasKit under /canvaskit. Keeping
      // the engine local prevents ad blockers or restricted networks from
      // making the entire Flutter app fail before its first frame.
      canvasKitBaseUrl: 'canvaskit/',
    },
  });
})();
