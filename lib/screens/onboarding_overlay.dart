import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

String _localeAssetCode(AppLocale locale) => switch (locale) {
  AppLocale.ja => 'ja',
  AppLocale.ko => 'ko',
  AppLocale.zhTw => 'zhtw',
  AppLocale.ptBr => 'ptbr',
  AppLocale.en => 'en',
};

List<String> _imagesFor(AppLocale locale) {
  final code = _localeAssetCode(locale);
  return [
    'assets/onboarding/$code-1.png',
    'assets/onboarding/$code-2.png',
    'assets/onboarding/$code-3.png',
  ];
}

/// 匿名アカウントでのホーム画面初回起動時に一度だけ表示する導入オーバーレイ。
/// 各言語で用意したスライド画像(assets/onboarding/)をそのまま表示し、画面の
/// どこをタップしても次のスライドへ進む(最終スライドでは閉じる)。右下にも
/// 同じ操作を行える明示的なボタンを置く。
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.appState});
  final AppState appState;

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _index = 0;
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _advance() {
    final images = _imagesFor(widget.appState.locale);
    if (_index >= images.length - 1) {
      widget.appState.markOnboardingSeen();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _imagesFor(widget.appState.locale);
    final isLast = _index == images.length - 1;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) =>
                      Image.asset(images[index], fit: BoxFit.contain),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .5),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: widget.appState.markOnboardingSeen,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < images.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _index ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == _index
                                    ? AppColors.purple
                                    : Colors.white.withValues(alpha: .4),
                                borderRadius: BorderRadius.circular(99),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: FilledButton.icon(
                          onPressed: _advance,
                          icon: Icon(
                            isLast
                                ? Icons.auto_awesome_rounded
                                : Icons.arrow_forward_rounded,
                            size: 19,
                          ),
                          label: Text(
                            isLast
                                ? context.l10n.t('onboardingJoin')
                                : context.l10n.t('onboardingNext'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(99),
                            ),
                            elevation: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
