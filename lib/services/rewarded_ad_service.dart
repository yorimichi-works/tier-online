import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// リワード広告(作成上限ボーナス用)の読み込み・表示を担当する。
///
/// google_mobile_ads は Web をサポートしないため、Web上では常に利用不可
/// (`isSupported == false`)として扱う。
/// 広告ユニットIDはGoogle公式のテスト用IDを使用している。本番リリース前に
/// 実際の広告ユニットIDへ差し替えること。
class RewardedAdService {
  RewardedAdService();

  static const _testAndroidUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const _testIosUnitId = 'ca-app-pub-3940256099942544/1712485313';

  RewardedAd? _ad;
  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get _adUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? _testIosUnitId
      : _testAndroidUnitId;

  Future<void> _ensureInitialized() async {
    if (_initialized || !isSupported) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  Future<void> _load() async {
    if (!isSupported) return;
    await _ensureInitialized();
    final completer = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) => completer.complete(null),
      ),
    );
    _ad = await completer.future;
  }

  /// 広告を表示し、視聴完了(リワード獲得)まで待つ。
  /// 視聴完了で `true`、失敗・未対応・広告なしで `false` を返す。
  Future<bool> showAndAwaitReward() async {
    if (!isSupported) return false;
    if (_ad == null) await _load();
    final ad = _ad;
    if (ad == null) return false;
    _ad = null;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (loadedAd) {
        loadedAd.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (loadedAd, error) {
        loadedAd.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(
      onUserEarnedReward: (loadedAd, reward) {
        if (!completer.isCompleted) completer.complete(true);
      },
    );
    return completer.future;
  }
}
