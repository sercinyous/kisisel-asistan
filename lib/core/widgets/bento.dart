import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// İki sütunlu Bento ızgarası. Her hücre 1 (yarım) ya da 2 (tam) sütun kaplar;
/// aynı satırdaki hücreler eşit yükseklikte olur.
class BentoGrid extends StatelessWidget {
  const BentoGrid({super.key, required this.children});

  final List<BentoCell> children;

  @override
  Widget build(BuildContext context) {
    final rows = <List<BentoCell>>[];
    BentoCell? pending;
    for (final cell in children) {
      if (cell.span >= 2) {
        if (pending != null) {
          rows.add([pending]);
          pending = null;
        }
        rows.add([cell]);
      } else if (pending == null) {
        pending = cell;
      } else {
        rows.add([pending, cell]);
        pending = null;
      }
    }
    if (pending != null) rows.add([pending]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.grid),
          if (row.length == 1)
            row.first.child
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: row[0].child),
                  const SizedBox(width: AppSpacing.grid),
                  Expanded(child: row[1].child),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// [BentoGrid] hücresi. [span] 1 = yarım genişlik, 2 = tam genişlik.
class BentoCell {
  const BentoCell({required this.child, this.span = 2})
      : assert(span == 1 || span == 2);

  final Widget child;
  final int span;
}

/// OLED siyah zemin üzerinde hafif yükseltilmiş Bento kartı.
class BentoCard extends StatelessWidget {
  const BentoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.onTap,
    this.onLongPress,
    this.tint,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Kartı hafifçe renklendirir (ör. vurgulanan metrik).
  final Color? tint;

  /// Verilirse kart zemini bu renkler arasında soldan sağa hafif geçişle
  /// boyanır (ör. ölçü günü banner'ı: mint → lavanta).
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    final g = gradient;
    if (g != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: AppColors.border),
          gradient: LinearGradient(
            colors: [
              for (final c in g)
                Color.alphaBlend(c.withValues(alpha: 0.14), AppColors.surface),
            ],
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }
    final color = tint == null
        ? AppColors.surface
        : Color.alphaBlend(tint!.withValues(alpha: 0.08), AppColors.surface);

    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Bento kartı başlığı: solda mürekkep renginde başlık, sağda küçük gri
/// meta/eylem metni (ör. "2 öğün", "Detay ›"). Önizlemedeki gibi ikon
/// çizilmez; [icon] geriye dönük uyumluluk için kabul edilir.
class BentoLabel extends StatelessWidget {
  const BentoLabel({
    super.key,
    this.icon,
    required this.label,
    Color? color,
    this.trailing,
    this.onTrailingTap,
    this.trailingColor,
  }) : _color = color;

  final IconData? icon;
  final String label;
  final Color? _color;
  final String? trailing;

  /// Verilirse sağ metin dokunulabilir bir eyleme dönüşür.
  final VoidCallback? onTrailingTap;

  /// Sağ metnin rengi; verilmezse ikincil metin rengi.
  final Color? trailingColor;

  /// Alan rengi (yalnızca veri/durum için; başlıkta kullanılmaz).
  Color get color => _color ?? AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final meta = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.cardTitle,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          if (meta != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTrailingTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  meta,
                  style: TextStyle(
                    color: trailingColor ?? AppColors.textSecondary,
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
