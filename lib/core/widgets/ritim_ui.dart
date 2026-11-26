import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'bento.dart';

/// Kart zemininde, 3 px iç boşluklu bölmeli kontrol. Seçili parça yarı
/// saydam seçim dolgusu ve birincil metinle; diğerleri ikincil metinle çizilir.
class RitimSegmented<T> extends StatelessWidget {
  const RitimSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.itemKey,
  });

  /// Parça başına test/erişim anahtarı (isteğe bağlı).
  final Key Function(T value)? itemKey;

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
                key: itemKey?.call(value),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

/// Seçim dolgulu küçük bilgi kutusu: kalın değer + ince etiket ve isteğe
/// bağlı renkli durum satırı (ör. "✓ bugün" mint, "• bekliyor" gri).
class RitimChipTile extends StatelessWidget {
  const RitimChipTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.status,
    this.statusColor,
    this.onTap,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final String? status;

  /// Durum satırının rengi; verilmezse ikincil metin rengi.
  final Color? statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final st = status;
    return Material(
      color: AppColors.selection,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.chip,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.chipValue,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
              if (st != null)
                Text(
                  st,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: statusColor ?? AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [RitimChipTile]'ları 2 sütunlu ızgarada (boşluk 6) dizer.
class RitimChipGrid extends StatelessWidget {
  const RitimChipGrid({super.key, required this.children, this.columns = 2});

  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      if (i > 0) rows.add(const SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: gap),
                Expanded(
                  child: i + j < children.length
                      ? children[i + j]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// Kart içi liste satırı: solda başlık (+ gri alt metin), sağa yaslı değer
/// ve isteğe bağlı renkli fark (mint/şeftali). Satırlar arasında ince çizgi.
class RitimListRow extends StatelessWidget {
  const RitimListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.delta,
    this.deltaColor,
    this.leading,
    this.showDivider = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final String? delta;

  /// Fark rengi; ör. [AppColors.positive] ya da [AppColors.negative].
  final Color? deltaColor;
  final Widget? leading;

  /// Üstte ayırıcı çizgi çizilir (ilk satırda false verin).
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final v = value;
    final d = delta;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(top: BorderSide(color: AppColors.border))
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          height: 1.3,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (v != null || d != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (v != null)
                      Text(
                        v,
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    if (d != null)
                      Text(
                        d,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: deltaColor ?? AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kart içi bölüm başlığı + içerik: başlık kartın içinde, sağda küçük gri
/// eylem/meta. Kartın dışında büyük başlık kullanılmaz.
class RitimSectionCard extends StatelessWidget {
  const RitimSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.onTrailingTap,
    this.onTap,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BentoLabel(
            label: title,
            trailing: trailing,
            onTrailingTap: onTrailingTap,
          ),
          const SizedBox(height: 6),
          child,
        ],
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
    // Görünen kapsül küçük kalır; dokunma alanı en az 44 pt (Apple HIG).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: _pill(bg, fg),
        ),
      ),
    );
  }

  Widget _pill(Color bg, Color fg) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
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
          complete: value >= 1 ? AppColors.sunset : null,
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
    this.complete,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;

  /// %100'de halkayı gün batımı geçişiyle süpüren renkler.
  final List<Color>? complete;

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
        _arcPaint(paint, rect),
      );
    }
  }

  Paint _arcPaint(Paint paint, Rect rect) {
    final c = complete;
    if (c == null) return paint..color = color;
    return paint
      ..color = c.first
      ..shader = SweepGradient(
        colors: [...c, c.first],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      !listEquals(old.complete, complete) ||
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
        color: c == null ? AppColors.selection : c.withValues(alpha: 0.10),
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
