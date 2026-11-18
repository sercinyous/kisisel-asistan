import 'dart:ui';

/// Ritim topacının (uygulama simgesi) vektör geometrisi.
///
/// Üç şekil de 100x100 birimlik koordinat uzayında, kaynak simgeden
/// (1024 px) izlenmiştir; yol verisi yalnızca mutlak `M`, `L`, `C`, `Z`
/// komutlarını içerir. Aynı metinler önizleme sayfasında SVG olarak da
/// kullanılır.
abstract final class RitimTopGeometry {
  /// Koordinat uzayının kenarı.
  static const double viewBox = 100;

  /// Topacın yere değdiği uç; yalpalama bu noktanın çevresinde döner.
  static const Offset tip = Offset(44.0, 78.4);

  /// Yörünge halkası (kalın eliptik kenar; sapın arkasında kapanır).
  static const String ringData =
      'M 57.67 34.33 C 63.40 35.79 69.00 37.55 74.17 40.38 '
      'C 77.61 42.33 83.03 45.40 83.25 49.95 '
      'C 83.09 52.99 79.51 54.39 77.20 55.22 '
      'C 72.65 56.59 67.67 56.92 62.55 56.88 '
      'C 54.55 56.61 47.03 55.35 39.70 53.47 '
      'C 34.09 51.86 28.48 50.11 23.49 47.02 '
      'C 20.61 45.34 17.31 42.63 17.04 39.11 '
      'C 17.12 36.91 19.23 35.50 21.04 34.81 '
      'C 21.66 34.48 21.12 35.76 21.44 36.08 '
      'C 22.66 39.26 26.52 41.07 29.25 42.43 '
      'C 35.00 44.98 41.16 46.60 47.51 47.71 '
      'C 53.99 48.91 61.47 49.61 68.31 48.68 '
      'C 69.85 48.35 72.24 48.02 72.90 46.34 '
      'C 72.86 44.33 69.94 43.18 68.51 42.43 '
      'C 66.65 41.49 64.65 40.77 62.65 40.19 '
      'C 60.79 39.58 58.21 38.62 56.49 38.62 '
      'L 54.50 39.60 L 55.50 33.30 Z';

  /// Sağa yukarı yükselen yuvarlak uçlu sap.
  static const String handleData =
      'M 56.40 39.01 C 55.97 41.09 55.22 43.02 52.78 43.31 '
      'C 50.54 43.33 48.19 42.02 48.29 39.50 '
      'C 48.48 36.99 49.37 34.71 49.76 32.28 '
      'C 50.46 29.71 50.97 27.05 51.61 24.46 '
      'C 51.86 22.51 53.22 20.71 55.42 20.85 '
      'C 57.55 20.82 59.34 22.21 59.52 24.37 '
      'C 59.26 27.69 58.10 30.72 57.57 33.94 Z';

  /// Halkanın altındaki koni gövde; ucu altta, ortanın solunda.
  static const String coneData =
      'M 22.31 48.49 C 24.71 50.10 28.16 52.02 31.20 53.17 '
      'C 34.95 54.86 38.93 55.99 42.92 57.08 '
      'C 49.19 58.53 55.57 59.74 62.45 59.72 '
      'C 67.16 59.70 71.74 59.21 75.93 57.96 '
      'C 71.90 62.09 67.36 65.10 62.74 67.82 '
      'C 57.07 71.22 51.28 74.35 45.65 77.88 '
      'C 45.16 78.18 44.62 78.48 43.99 78.47 '
      'C 43.42 78.36 42.94 78.07 42.72 77.49 '
      'C 39.75 72.25 35.90 67.37 32.37 62.35 '
      'C 29.08 57.71 25.65 53.12 22.31 48.49 Z';

  /// Halka boşluğunun merkezi; ışık dilimi buradan açılır.
  static const Offset ringCenter = Offset(48, 43);

  /// Halka elipsinin eğimi (radyan, saat yönünde).
  static const double ringTilt = 0.1745;

  /// Halka elipsinin dikey/yatay oranı (perspektif basıklığı).
  static const double ringSquash = 0.3;

  /// Yer gölgesinin merkezi ve yarıçapları.
  static const Offset shadowCenter = Offset(44, 81.5);
  static const double shadowRadiusX = 13;
  static const double shadowRadiusY = 2.2;

  static final Path ring = parse(ringData);
  static final Path handle = parse(handleData);
  static final Path cone = parse(coneData);

  /// Mutlak `M`/`L`/`C`/`Z` komutlu yol metnini [Path] yapar.
  static Path parse(String data) {
    final tokens = data.trim().split(RegExp(r'[\s,]+'));
    final path = Path();
    var i = 0;
    double next() => double.parse(tokens[i++]);
    while (i < tokens.length) {
      final command = tokens[i++];
      switch (command) {
        case 'M':
          path.moveTo(next(), next());
        case 'L':
          path.lineTo(next(), next());
        case 'C':
          path.cubicTo(next(), next(), next(), next(), next(), next());
        case 'Z':
          path.close();
        default:
          throw FormatException('Desteklenmeyen yol komutu: $command');
      }
    }
    return path;
  }
}
