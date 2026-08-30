import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/theme/app_theme.dart';

void main() {
  const multilingualText = <String>[
    'Tier表オンライン',
    '最強キャラクターランキング',
    '竈門炭治郎',
    '髙橋 齊藤 推しキャラ',
    '티어표 온라인',
    '최강 캐릭터 랭킹',
    '한국어 테스트',
    'Tier Online',
    'Best Character Ranking',
    'Create Your Tier List',
    'ONE PIECE 最強 캐릭터 Tier',
    'K-POP 推しランキング',
    'Pokémon 포켓몬 最強Tier',
    '髙 﨑 邊 邉 齊 齋 神 福',
  ];

  test('日英韓とOSフォントのfallback順を保持する', () {
    expect(appFontFamilyFallback.take(2), const [
      'TierNotoSansJP',
      'TierNotoSansKR',
    ]);
    expect(
      appFontFamilyFallback,
      containsAll(const ['Meiryo', 'Malgun Gothic']),
    );
    expect(appFontFamilyFallback.last, 'sans-serif');
    expect(
      buildDarkAppTheme().textTheme.bodyMedium?.fontFamilyFallback,
      appFontFamilyFallback,
    );
    expect(
      buildLightAppTheme().textTheme.bodyMedium?.fontFamilyFallback,
      appFontFamilyFallback,
    );
  });

  testWidgets('日英韓と混在テキストを同じ画面で描画できる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [for (final text in multilingualText) Text(text)],
          ),
        ),
      ),
    );

    for (final text in multilingualText) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test('Web初期表示はローカルフォントとOS fallbackを使う', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('NotoSansJP-TierSubset.ttf'));
    expect(html, contains('NotoSansKR-TierSubset.ttf'));
    expect(html, contains('flutter-first-frame'));
    expect(html, contains('rel="preload"'));
    expect(html, contains('NotoSansJP-TierSubset.ttf'));
    expect(html, contains('NotoSansKR-TierSubset.ttf'));
    expect(html, isNot(contains('fonts.googleapis.com')));
    expect(html, isNot(contains('fonts.gstatic.com')));

    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('document.fonts.load'));
    expect(bootstrap, contains('withStartupTimeout(waitForTierFonts()'));
    expect(bootstrap, contains('Promise.allSettled'));
    expect(bootstrap, contains("canvasKitBaseUrl: 'canvaskit/'"));
    expect(bootstrap, contains('_flutter.loader.load'));
  });
}
