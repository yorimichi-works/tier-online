import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const _clientId = 'ca-pub-3186852093801241';

/// Flutter Web のプラットフォームビュー内に AdSense の広告ユニットを作る。
class AdSenseAd extends StatefulWidget {
  const AdSenseAd({super.key, required this.slot});

  final String slot;

  @override
  State<AdSenseAd> createState() => _AdSenseAdState();
}

class _AdSenseAdState extends State<AdSenseAd> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'adsense-${widget.slot}-${identityHashCode(this)}';
    if (widget.slot.isEmpty) return;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final container = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden';
      final ad = web.document.createElement('ins') as web.HTMLElement
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('data-ad-client', _clientId)
        ..setAttribute('data-ad-slot', widget.slot)
        ..setAttribute('data-ad-format', 'auto')
        ..setAttribute('data-full-width-responsive', 'true');
      container.append(ad);
      unawaited(Future<void>.delayed(Duration.zero, _requestAd));
      return container;
    });
  }

  void _requestAd() {
    final name = 'adsbygoogle'.toJS;
    final existing = globalContext.getProperty<JSAny?>(name);
    final queue = (existing ?? <JSAny?>[].toJS) as JSObject;
    globalContext.setProperty(name, queue);
    queue.callMethod<JSAny?>('push'.toJS, JSObject());
  }

  @override
  Widget build(BuildContext context) => widget.slot.isEmpty
      ? const SizedBox.shrink()
      : HtmlElementView(viewType: _viewType);
}
