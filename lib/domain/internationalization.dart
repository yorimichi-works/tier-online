import 'package:flutter/widgets.dart';

/// The languages for which Tier Online ships a complete UI.
///
/// This is intentionally separate from a user's region and from the language
/// of a Tier's user-generated content. A single [AppLocale] can therefore be
/// used in any region, while Tier data keeps its own `contentLanguage`.
enum AppLocale { ja, ko, en, zhTw, ptBr }

@immutable
class LocaleProfile {
  const LocaleProfile({
    required this.locale,
    required this.code,
    required this.flutterLocale,
    required this.nativeName,
    required this.serviceName,
    required this.defaultRegion,
    required this.firebaseAuthCode,
    required this.hreflang,
    required this.ogLocale,
  });

  final AppLocale locale;

  /// Canonical lowercase code used by routes and Firestore.
  final String code;
  final Locale flutterLocale;
  final String nativeName;
  final String serviceName;
  final String defaultRegion;
  final String firebaseAuthCode;
  final String hreflang;
  final String ogLocale;
}

abstract final class InternationalizationConfig {
  static const localeProfiles = <LocaleProfile>[
    LocaleProfile(
      locale: AppLocale.ja,
      code: 'ja',
      flutterLocale: Locale('ja'),
      nativeName: '日本語',
      serviceName: 'tier表オンライン',
      defaultRegion: 'JP',
      firebaseAuthCode: 'ja',
      hreflang: 'ja',
      ogLocale: 'ja_JP',
    ),
    LocaleProfile(
      locale: AppLocale.ko,
      code: 'ko',
      flutterLocale: Locale('ko'),
      nativeName: '한국어',
      serviceName: '티어표 온라인',
      defaultRegion: 'KR',
      firebaseAuthCode: 'ko',
      hreflang: 'ko',
      ogLocale: 'ko_KR',
    ),
    LocaleProfile(
      locale: AppLocale.en,
      code: 'en',
      flutterLocale: Locale('en'),
      nativeName: 'English',
      serviceName: 'Tier Online',
      defaultRegion: 'GLOBAL',
      firebaseAuthCode: 'en',
      hreflang: 'en',
      ogLocale: 'en_US',
    ),
    LocaleProfile(
      locale: AppLocale.zhTw,
      code: 'zh-tw',
      flutterLocale: Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
      nativeName: '繁體中文',
      serviceName: 'Tier 表線上版',
      defaultRegion: 'TW',
      firebaseAuthCode: 'zh-TW',
      hreflang: 'zh-Hant-TW',
      ogLocale: 'zh_TW',
    ),
    LocaleProfile(
      locale: AppLocale.ptBr,
      code: 'pt-br',
      flutterLocale: Locale('pt', 'BR'),
      nativeName: 'Português',
      serviceName: 'Tier Online',
      defaultRegion: 'BR',
      firebaseAuthCode: 'pt-BR',
      hreflang: 'pt-BR',
      ogLocale: 'pt_BR',
    ),
  ];

  static LocaleProfile profileOf(AppLocale locale) =>
      localeProfiles.firstWhere((profile) => profile.locale == locale);

  static LocaleProfile? profileForCode(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll('_', '-');
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'zh' || normalized == 'zh-hant') {
      return profileOf(AppLocale.zhTw);
    }
    if (normalized == 'pt') return profileOf(AppLocale.ptBr);
    for (final profile in localeProfiles) {
      if (profile.code == normalized) return profile;
    }
    return null;
  }
}

extension AppLocaleValues on AppLocale {
  LocaleProfile get profile => InternationalizationConfig.profileOf(this);
  String get code => profile.code;
  String get nativeName => profile.nativeName;
  Locale get flutterLocale => profile.flutterLocale;
  String get serviceName => profile.serviceName;
  String get defaultRegion => profile.defaultRegion;
  String get firebaseAuthCode => profile.firebaseAuthCode;
  String get hreflang => profile.hreflang;
  String get ogLocale => profile.ogLocale;
}

abstract final class AppLocaleParser {
  static AppLocale? fromCode(String? value) =>
      InternationalizationConfig.profileForCode(value)?.locale;

  static AppLocale? fromPath(String path) {
    final segments = Uri.tryParse(path)?.pathSegments ?? const <String>[];
    return segments.isEmpty ? null : fromCode(segments.first);
  }

  static AppLocale fromDevice(Locale locale) {
    final language = locale.languageCode.toLowerCase();
    final region = locale.countryCode?.toUpperCase();
    final script = locale.scriptCode?.toLowerCase();
    if (region == 'KR' || language == 'ko') return AppLocale.ko;
    if (region == 'JP' || language == 'ja') return AppLocale.ja;
    if (region == 'TW' || region == 'HK' || script == 'hant') {
      return AppLocale.zhTw;
    }
    if (region == 'BR' || language == 'pt') return AppLocale.ptBr;
    return AppLocale.en;
  }
}

@immutable
class SupportedRegion {
  const SupportedRegion({required this.code, required this.localizationKey});

  final String code;
  final String localizationKey;

  static const values = <SupportedRegion>[
    SupportedRegion(code: 'JP', localizationKey: 'japan'),
    SupportedRegion(code: 'KR', localizationKey: 'korea'),
    SupportedRegion(code: 'TW', localizationKey: 'taiwan'),
    SupportedRegion(code: 'HK', localizationKey: 'hongKong'),
    SupportedRegion(code: 'US', localizationKey: 'unitedStates'),
    SupportedRegion(code: 'GB', localizationKey: 'unitedKingdom'),
    SupportedRegion(code: 'BR', localizationKey: 'brazil'),
    SupportedRegion(code: 'GLOBAL', localizationKey: 'globalOther'),
  ];

  static bool isSupported(String? value) =>
      values.any((region) => region.code == value?.trim().toUpperCase());

  static String normalize(String? value, {String fallback = 'GLOBAL'}) {
    final normalized = value?.trim().toUpperCase();
    return isSupported(normalized) ? normalized! : fallback;
  }
}

enum RankingScopeKind { global, region, language }

/// Identifies which population an aggregate ranking represents.
///
/// Firestore paths remain unchanged for now; [storageKey] provides a stable
/// value for a future `aggregate_rankings` collection.
@immutable
class RankingScope {
  const RankingScope._(this.kind, this.value);

  const RankingScope.global() : this._(RankingScopeKind.global, null);

  factory RankingScope.region(String region) => RankingScope._(
    RankingScopeKind.region,
    SupportedRegion.normalize(region),
  );

  factory RankingScope.language(AppLocale locale) =>
      RankingScope._(RankingScopeKind.language, locale.code);

  final RankingScopeKind kind;
  final String? value;

  String get storageKey => switch (kind) {
    RankingScopeKind.global => 'global',
    RankingScopeKind.region => 'region:$value',
    RankingScopeKind.language => 'language:$value',
  };

  @override
  bool operator ==(Object other) =>
      other is RankingScope && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}
