import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'share_image_downloader_stub.dart'
    if (dart.library.html) 'share_image_downloader_web.dart'
    as downloader;

abstract final class ShareImageService {
  static Future<void> captureAndDownload({
    required GlobalKey boundaryKey,
    required String fileName,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('共有画像を生成できませんでした。');
    }
    final image = await renderObject.toImage(pixelRatio: 2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('共有画像の変換に失敗しました。');
    }
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    downloader.downloadPng(bytes, _safeFileName(fileName));
  }

  static String _safeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return '${sanitized.isEmpty ? 'tier-result' : sanitized}.png';
  }
}
