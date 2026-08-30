{{flutter_js}}
{{flutter_build_config}}

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
  try {
    await clearLegacyFlutterWorker();
    await waitForTierFonts();
    document.documentElement.dataset.tierFontsReady = 'true';
  } catch (error) {
    // A local font failure must not leave the app permanently blocked. The
    // ThemeData OS font stack remains available as the final fallback.
    console.warn('Tier fonts could not be preloaded; using system fallback.', error);
  }

  await _flutter.loader.load();
})();
