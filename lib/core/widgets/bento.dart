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
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Kartı hafifçe renklendirir (ör. vurgulanan metrik).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    final color = tint == null
        ? AppColors.surface
        : Color.alphaBlend(tint!.withValues(alpha: 0.10), AppColors.surface);

    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Bento kartı başlığı: küçük ikon + etiket (+ isteğe bağlı sağ metin).
class BentoLabel extends StatelessWidget {
  const BentoLabel({
    super.key,
    required this.icon,
    required this.label,
    Color? color,
    this.trailing,
  }) : _color = color;

  final IconData icon;
  final String label;
  final Color? _color;
  final String? trailing;

  /// Verilmezse etkin temanın ikincil metin rengi.
  Color get color => _color ?? AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
      ],
    );
  }
}
