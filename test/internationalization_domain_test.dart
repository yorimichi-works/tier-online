import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/domain/internationalization.dart';

void main() {
  test('対応言語の保存・URLコードは一意で安定している', () {
    final codes = InternationalizationConfig.localeProfiles
        .map((profile) => profile.code)
        .toList();

    expect(codes, ['ja', 'ko', 'en', 'zh-tw', 'pt-br']);
    expect(codes.toSet(), hasLength(codes.length));
    expect(AppLocale.zhTw.hreflang, 'zh-Hant-TW');
    expect(AppLocale.zhTw.storageCode, 'zh-TW');
    expect(AppLocale.ptBr.storageCode, 'pt-BR');
    expect(AppLocale.ptBr.firebaseAuthCode, 'pt-BR');
  });

  test('UI言語はコード・URL・端末情報から同じ規則で解決できる', () {
    expect(AppLocaleParser.fromCode('zh_Hant'), AppLocale.zhTw);
    expect(AppLocaleParser.fromCode('pt'), AppLocale.ptBr);
    expect(AppLocaleParser.fromPath('/pt-br/tier/example'), AppLocale.ptBr);
    expect(
      AppLocaleParser.fromDevice(const Locale('zh', 'HK')),
      AppLocale.zhTw,
    );
    expect(
      AppLocaleParser.fromDevice(const Locale('zh', 'MO')),
      AppLocale.zhTw,
    );
  });

  test('地域コードは許可リストへ正規化する', () {
    expect(SupportedRegion.normalize(' hk '), 'HK');
    expect(SupportedRegion.normalize('us'), 'US');
    expect(SupportedRegion.normalize('unknown'), 'GLOBAL');
    expect(SupportedRegion.normalize(null, fallback: 'JP'), 'JP');
  });

  test('世界・地域・言語の集計範囲を混同しない', () {
    expect(const RankingScope.global().storageKey, 'global');
    expect(RankingScope.region('jp').storageKey, 'region:JP');
    expect(RankingScope.language(AppLocale.zhTw).storageKey, 'language:zh-tw');
  });
}
