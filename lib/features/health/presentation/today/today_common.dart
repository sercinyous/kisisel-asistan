import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/fat_loss_plan.dart' show formatTrDecimal2;
import '../health_format.dart';

/// Bugün ve detay ekranlarının ortak biçimleri ve küçük çizim parçaları.
abstract final class TodayFormat {
  /// Açık pozitifken "−420 kcal"; fazla alımda "+180 kcal".
  static String deficit(num kcal) => kcal >= 0
      ? '−${HealthFormat.count(kcal)} kcal'
      : '+${HealthFormat.count(-kcal)} kcal';

  /// "≈ 0,37 kg" (yağ karşılığı; 7.700 kcal ≈ 1 kg).
  static String kg(double kg) => '≈ ${formatTrDecimal2(kg.abs())} kg';

  /// Pazartesiden başlayan kısa gün adları.
  static const List<String> weekdayShort = [
    'Pt',
    'Sa',
    'Ça',
    'Pe',
    'Cu',
    'Ct',
    'Pz',
  ];

  /// Pazartesiden başlayan tam gün adları.
  static const List<String> weekdayLong = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
}

/// Günlük çubuk grafiği. Değeri `null` olan gün yalnızca soluk zemin;
/// negatif değer (ör. kalori fazlası) taban çizgisinin altına uyarı rengiyle
/// çizilir. [highlightIndex] günün çubuğu taralı (henüz kesinleşmedi).
class DayBarChart extends StatelessWidget {
  const DayBarChart({
    super.key,
    required this.values,
    required this.color,
    this.labels,
    this.highlightIndex,
    this.target,
    this.height = 120,
    this.semanticsLabel,
  });

  final List<double?> values;
  final Color color;
  final List<String>? labels;
  final int? highlightIndex;

  /// Kesikli hedef çizgisi (aynı birimde); `null` ise çizilmez.
  final double? target;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted);
    final chart = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _DayBarPainter(
          values: values,
          color: color,
          negativeColor: AppColors.warning,
          trackColor: AppColors.surfaceHigh,
          lineColor: AppColors.textMuted,
          highlightIndex: highlightIndex,
          target: target,
        ),
      ),
    );
    final labels = this.labels;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chart,
          if (labels != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: i == highlightIndex
                          ? labelStyle?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            )
                          : labelStyle,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayBarPainter extends CustomPainter {
  _DayBarPainter({
    required this.values,
    required this.color,
    required this.negativeColor,
    required this.trackColor,
    required this.lineColor,
    required this.highlightIndex,
    required this.target,
  });

  final List<double?> values;
  final Color color;
  final Color negativeColor;
  final Color trackColor;
  final Color lineColor;
  final int? highlightIndex;
  final double? target;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final known = values.whereType<double>();
    final maxPos = math.max(
      known.fold<double>(0, (m, v) => math.max(m, v)),
      target ?? 0,
    );
    final maxNeg = known.fold<double>(0, (m, v) => math.max(m, -v));
    final span = maxPos + maxNeg;
    final scale = span <= 0 ? 0.0 : size.height / span;
    final baseline = maxPos * scale;
    final slot = size.width / values.length;
    final barWidth = math.max(2.0, math.min(slot * 0.62, 28.0));
    final radius = Radius.circular(math.min(barWidth / 2, 6));

    final track = Paint()..color = trackColor;
    for (var i = 0; i < values.length; i++) {
      final x = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, barWidth, size.height),
          radius,
        ),
        track..color = trackColor.withValues(alpha: 0.5),
      );
      final v = values[i];
      if (v == null || v == 0 || scale == 0) continue;
      final h = math.max(2.0, v.abs() * scale);
      final rect = v > 0
          ? Rect.fromLTWH(x, baseline - h, barWidth, h)
          : Rect.fromLTWH(x, baseline, barWidth, h);
      final fill = v > 0 ? color : negativeColor;
      final rrect = RRect.fromRectAndRadius(rect, radius);
      if (i == highlightIndex) {
        _hatch(canvas, rrect, fill);
      } else {
        canvas.drawRRect(rrect, Paint()..color = fill);
      }
    }

    final t = target;
    if (t != null && t > 0 && scale > 0) {
      final y = baseline - t * scale;
      final dash = Paint()
        ..color = lineColor
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
      }
    }
  }

  /// Taralı çubuk: ince çerçeve + çapraz çizgiler.
  void _hatch(Canvas canvas, RRect rrect, Color fill) {
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRRect(rrect, Paint()..color = fill.withValues(alpha: 0.22));
    final stripe = Paint()
      ..color = fill
      ..strokeWidth = 2;
    final r = rrect.outerRect;
    for (var d = -r.height; d < r.width + r.height; d += 6) {
      canvas.drawLine(
        Offset(r.left + d, r.bottom),
        Offset(r.left + d + r.height, r.top),
        stripe,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_DayBarPainter old) =>
      old.values != values ||
      old.color != color ||
      old.highlightIndex != highlightIndex ||
      old.target != target ||
      old.trackColor != trackColor;
}

/// Halka: [progress] 0–1 (taşma ayrı renkte), ortada metin.
class KcalRing extends StatelessWidget {
  const KcalRing({
    super.key,
    required this.progress,
    required this.color,
    required this.center,
    this.caption,
    this.size = 116,
  });

  final double progress;
  final Color color;
  final String center;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress,
          color: color,
          overColor: AppColors.warning,
          track: AppColors.surfaceHigh,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.overColor,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color overColor;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base..color = track);
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawArc(
          arcRect, -math.pi / 2, math.pi * 2 * p, false, base..color = color);
    }
    if (progress > 1) {
      final over = (progress - 1).clamp(0.0, 1.0);
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * over, false,
          base..color = overColor);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// İnce ilerleme çubuğu (yuvarlak uçlu).
class SlimBar extends StatelessWidget {
  const SlimBar({super.key, required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: AppColors.surfaceHigh,
          color: color,
        ),
      );
}
