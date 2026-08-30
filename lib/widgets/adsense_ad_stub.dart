import 'package:flutter/widgets.dart';

/// Web 以外では AdSense の表示領域を作らない。
class AdSenseAd extends StatelessWidget {
  const AdSenseAd({super.key, required this.slot});

  final String slot;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
