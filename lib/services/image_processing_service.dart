import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

class ImageProcessingService {
  const ImageProcessingService({this.maxDimension = 512, this.quality = 82});

  final int maxDimension;
  final int quality;

  Future<Uint8List> prepareTierCard(Uint8List source) =>
      compute(_prepare, _ImageProcessingRequest(source, maxDimension, quality));
}

class _ImageProcessingRequest {
  const _ImageProcessingRequest(this.bytes, this.maxDimension, this.quality);
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
}

Uint8List _prepare(_ImageProcessingRequest request) {
  final decoded = image.decodeImage(request.bytes);
  if (decoded == null) {
    throw const FormatException('画像を読み込めませんでした');
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
  final resized = extent > request.maxDimension
      ? image.copyResize(
          square,
          width: request.maxDimension,
          height: request.maxDimension,
          interpolation: image.Interpolation.average,
        )
      : square;
  return Uint8List.fromList(image.encodeJpg(resized, quality: request.quality));
}
