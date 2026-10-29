import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class ImageProcessingService {
  const ImageProcessingService({
    this.maxDimension = 512,
    this.quality = 82,
    this.maxBytes,
    this.minQuality = 50,
    this.stripMetadata = false,
  });

  final int maxDimension;
  final int quality;

  /// Optional size budget. When set, JPEG quality is lowered step by step
  /// (down to [minQuality]) and then the image is scaled down until the
  /// encoded file fits.
  final int? maxBytes;
  final int minQuality;

  /// Applies the EXIF orientation to the pixels and drops all metadata
  /// (camera, GPS, thumbnails) before encoding.
  final bool stripMetadata;

  // Web版はcompute()(Web Worker経由)を使わない: iOS Safariなど一部の
  // モバイルブラウザで、ワーカーの起動に失敗しても例外が伝播せず、Futureが
  // 永久に解決しないまま無反応になる不具合が確認されているため。画像1枚
  // あたりの処理は軽量なので、メインアイソレートで直接実行しても体感できる
  // ほどのジャンクは生じない。
  Future<Uint8List> prepareTierCard(Uint8List source) {
    final request = _ImageProcessingRequest(
      source,
      maxDimension,
      quality,
      maxBytes,
      minQuality,
      stripMetadata,
    );
    return kIsWeb
        ? Future(() => _prepare(request))
        : compute(_prepare, request);
  }
}

class _ImageProcessingRequest {
  const _ImageProcessingRequest(
    this.bytes,
    this.maxDimension,
    this.quality,
    this.maxBytes,
    this.minQuality,
    this.stripMetadata,
  );
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  final int? maxBytes;
  final int minQuality;
  final bool stripMetadata;
}

Uint8List _prepare(_ImageProcessingRequest request) {
  var decoded = image.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('画像を読み込めませんでした');
  }
  if (request.stripMetadata) {
    decoded = image.bakeOrientation(decoded);
  }
  final extent = decoded.width < decoded.height
      ? decoded.width
      : decoded.height;
  final square = image.copyCrop(
    decoded,
    x: (decoded.width - extent) ~/ 2,
    y: (decoded.height - extent) ~/ 2,
    width: extent,
    height: extent,
  );
  var resized = _fit(square, request.maxDimension);
  if (request.stripMetadata) resized.exif = image.ExifData();

  var encoded = image.encodeJpg(resized, quality: request.quality);
  final budget = request.maxBytes;
  if (budget == null) return Uint8List.fromList(encoded);

  var quality = request.quality;
  while (encoded.length > budget && quality - 8 >= request.minQuality) {
    quality -= 8;
    encoded = image.encodeJpg(resized, quality: quality);
  }
  // Very detailed photos can still exceed the budget at the minimum quality;
  // shrink them instead of degrading quality further.
  while (encoded.length > budget && resized.width > 160) {
    resized = _fit(resized, (resized.width * .8).round());
    if (request.stripMetadata) resized.exif = image.ExifData();
    encoded = image.encodeJpg(resized, quality: quality);
  }
  return Uint8List.fromList(encoded);
}

image.Image _fit(image.Image square, int maxDimension) =>
    square.width > maxDimension
    ? image.copyResize(
        square,
        width: maxDimension,
        height: maxDimension,
        interpolation: image.Interpolation.average,
      )
    : square;
