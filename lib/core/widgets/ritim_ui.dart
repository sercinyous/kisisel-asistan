import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Kart zemininde, 3 px iç boşluklu bölmeli kontrol. Seçili parça yarı
/// saydam seçim dolgusu ve birincil metinle; diğerleri ikincil metinle çizilir.
class RitimSegmented<T> extends StatelessWidget {
  const RitimSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  /// Değer → etiket.
  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: value, value: label) in segments.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (value == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == selected
                          ? AppColors.selection
                          : AppColors.selection.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(AppRadii.segment),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value == selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Seçim dolgulu küçük bilgi kutusu: kalın değer + ince etiket.
class RitimChipTile extends StatelessWidget {
  const RitimChipTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.onTap,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.selection,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.chipValue,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.chip,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tam yuvarlak kapsül buton. [ghost] seçim dolgulu ikincil çeşit.
class RitimPillButton extends StatelessWidget {
  const RitimPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.ghost = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool ghost;

  /// Dolu çeşidin zemini; verilmezse vurgu rengi.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = ghost ? AppColors.selection : (color ?? AppColors.accent);
    final fg = ghost ? AppColors.textPrimary : AppColors.onAccent;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.chip,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 6 px yüksekliğinde, iz renkli yatay ilerleme çubuğu.
class RitimStatBar extends StatelessWidget {
  const RitimStatBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  /// 0..1 arası; dışındaki değerler kırpılır.
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(AppRadii.bar);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.track),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color ?? AppColors.accent,
                  borderRadius: radius,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Yuvarlak uçlu ilerleme halkası; ortasına [child] yerleşir.
class RitimRing extends StatelessWidget {
  const RitimRing({
    super.key,
    required this.value,
    this.size = 76,
    this.stroke = 8,
    this.color,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
          stroke: stroke,
          color: color ?? AppColors.accent,
          track: AppColors.track,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

/// Küçük kapsül rozet. [color] verilirse o renkte yazı + %16 dolgu.
class RitimBadge extends StatelessWidget {
  const RitimBadge(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c == null ? AppColors.selection : c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: AppType.badge,
          fontWeight: FontWeight.w500,
          color: c ?? AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Küçük durum noktası (7 px).
class RitimDot extends StatelessWidget {
  const RitimDot({super.key, this.color, this.size = 7});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? AppColors.textSecondary,
          shape: BoxShape.circle,
        ),
      );
}
