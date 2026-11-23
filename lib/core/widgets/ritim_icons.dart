import 'package:flutter/material.dart';

/// İnce, yuvarlak uçlu çizgi ikonlar (24×24 görünüm kutusu, çizgi 1.8).
///
/// Alt bar gibi markaya ait yüzeyler bu ikonları kullanır. Diğer yerlerde
/// Material ikonlarının `_rounded` / `_outlined` çeşitleri kullanılır; dolu
/// (`Icons.x` düz) çeşitler yalnızca seçili durumu belirtmek için kullanılmaz.
enum RitimGlyph { grid, list, plus, heart, chart }

class RitimLineIcon extends StatelessWidget {
  const RitimLineIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 1.8,
  });

  final RitimGlyph glyph;
  final double size;
  final Color? color;

  /// 24 birimlik görünüm kutusundaki çizgi kalınlığı.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color!;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GlyphPainter(glyph, c, strokeWidth)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.strokeWidth);

  final RitimGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);

    switch (glyph) {
      case RitimGlyph.grid:
        for (final o in const [
          Offset(3, 3),
          Offset(14, 3),
          Offset(3, 14),
          Offset(14, 14),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                o & const Size(7, 7), const Radius.circular(2)),
            paint,
          );
        }
      case RitimGlyph.list:
        for (final y in const [6.0, 12.0, 18.0]) {
          line(9, y, 20, y);
          line(4, y, 4.01, y);
        }
      case RitimGlyph.plus:
        line(12, 5, 12, 19);
        line(5, 12, 19, 12);
      case RitimGlyph.heart:
        final path = Path()
          ..moveTo(12, 20)
          ..cubicTo(12, 20, 5, 15.5, 5, 10)
          ..arcToPoint(const Offset(12, 7.4), radius: const Radius.circular(4))
          ..arcToPoint(const Offset(19, 10), radius: const Radius.circular(4))
          ..cubicTo(19, 15.5, 12, 20, 12, 20)
          ..close();
        canvas.drawPath(path, paint);
      case RitimGlyph.chart:
        line(4, 20, 4, 10);
        line(10, 20, 10, 4);
        line(16, 20, 16, 13);
        line(22, 20, 2, 20);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
