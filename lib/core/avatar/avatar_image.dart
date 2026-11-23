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
  final oriented = _stripExif(img.bakeOrientation(decoded));
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

/// İlerleme fotoğrafının uzun kenarı (piksel) ve JPEG kalitesi.
const int progressPhotoMaxEdge = 1600;
const int progressPhotoQuality = 80;

/// Görüntüyü EXIF yönüne göre çevirir, uzun kenarı en çok [maxEdge] piksele
/// küçültür (büyütmez), EXIF'i (konum, cihaz) tamamen siler ve JPEG'e
/// çevirir. Çözülemezse [FormatException].
Uint8List progressPhotoJpeg(
  Uint8List input, {
  int maxEdge = progressPhotoMaxEdge,
  int quality = progressPhotoQuality,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('Görüntü okunamadı.');
  }
  final oriented = _stripExif(img.bakeOrientation(decoded));
  final longEdge =
      oriented.width > oriented.height ? oriented.width : oriented.height;
  final resized = longEdge <= maxEdge
      ? oriented
      : oriented.width >= oriented.height
          ? img.copyResize(oriented,
              width: maxEdge, interpolation: img.Interpolation.average)
          : img.copyResize(oriented,
              height: maxEdge, interpolation: img.Interpolation.average);
  return img.encodeJpg(_stripExif(resized), quality: quality);
}

/// [progressPhotoJpeg] arka planda.
Future<Uint8List> prepareProgressPhotoJpeg(Uint8List input) =>
    compute(_prepareProgress, input);

Uint8List _prepareProgress(Uint8List input) => progressPhotoJpeg(input);

/// Konum ve cihaz bilgisi yüklenmesin: EXIF bloğu boşaltılır.
img.Image _stripExif(img.Image image) {
  image.exif = img.ExifData();
  return image;
}
