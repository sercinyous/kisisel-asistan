import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Yüklenen avatarın kenar uzunluğu (piksel).
const int avatarPixelSize = 512;

/// Görüntüyü EXIF yönüne göre çevirir, ortadan kare kırpar, [size] piksele
/// küçültür ve JPEG'e çevirir. Çözülemezse [FormatException].
Uint8List squareAvatarJpeg(Uint8List input, {int size = avatarPixelSize}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('Görüntü okunamadı.');
  }
  final oriented = img.bakeOrientation(decoded);
  final side = oriented.width < oriented.height ? oriented.width : oriented.height;
  final square = img.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = side == size
      ? square
      : img.copyResize(
          square,
          width: size,
          height: size,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(resized, quality: 85);
}

/// [squareAvatarJpeg] arka planda (ana iş parçacığını kilitlemez).
Future<Uint8List> prepareAvatarJpeg(Uint8List input) =>
    compute(_prepare, input);

Uint8List _prepare(Uint8List input) => squareAvatarJpeg(input);
