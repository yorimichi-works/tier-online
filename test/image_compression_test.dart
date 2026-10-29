import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tier_table_online/bingo/models/bingo_models.dart';
import 'package:tier_table_online/services/image_processing_service.dart';

/// A large photo full of noise (the worst case for JPEG) with camera EXIF.
Uint8List _noisyPhoto({int width = 2400, int height = 1600}) {
  final random = Random(7);
  final photo = img.Image(width: width, height: height);
  for (final pixel in photo) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  photo.exif.imageIfd['Make'] = img.IfdValueAscii('TestCamera');
  photo.exif.imageIfd.orientation = 6;
  return Uint8List.fromList(img.encodeJpg(photo, quality: 95));
}

void main() {
  const bingo = ImageProcessingService(
    maxDimension: BingoImagePolicy.pixels,
    quality: BingoImagePolicy.jpegQuality,
    maxBytes: BingoImagePolicy.maxUploadBytes,
    stripMetadata: true,
  );

  test('ビンゴの画像は400px以下の正方形JPEGに縮小し、容量上限まで圧縮する', () async {
    final source = _noisyPhoto();
    expect(source.length, greaterThan(1024 * 1024));

    final output = await bingo.prepareTierCard(source);
    expect(output.length, lessThanOrEqualTo(BingoImagePolicy.maxUploadBytes));
    // Storage rules reject anything at or above 200KB.
    expect(output.length, lessThan(200 * 1024));

    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, decoded.height);
    expect(decoded.width, lessThanOrEqualTo(BingoImagePolicy.pixels));
    expect(decoded.width, greaterThanOrEqualTo(160));
  });

  test('ビンゴの画像からはカメラ情報などのEXIFを取り除く', () async {
    final output = await bingo.prepareTierCard(
      _noisyPhoto(width: 600, height: 500),
    );
    final decoded = img.decodeJpg(output)!;
    expect(decoded.exif.imageIfd['Make'], isNull);
    expect(decoded.exif.imageIfd.hasOrientation, isFalse);
  });

  test('写真らしい画像は解像度を保ったまま上限内に収まる', () async {
    final gradient = img.Image(width: 1200, height: 900);
    for (final pixel in gradient) {
      pixel
        ..r = pixel.x * 255 ~/ 1200
        ..g = pixel.y * 255 ~/ 900
        ..b = 128;
    }
    final output = await bingo.prepareTierCard(
      Uint8List.fromList(img.encodeJpg(gradient, quality: 95)),
    );
    expect(output.length, lessThanOrEqualTo(BingoImagePolicy.maxUploadBytes));
    expect(img.decodeJpg(output)!.width, BingoImagePolicy.pixels);
  });

  test('Tierの既定設定（512px・容量上限なし）は変わらない', () async {
    final output = await const ImageProcessingService().prepareTierCard(
      _noisyPhoto(width: 800, height: 600),
    );
    expect(img.decodeJpg(output)!.width, 512);
  });
}
