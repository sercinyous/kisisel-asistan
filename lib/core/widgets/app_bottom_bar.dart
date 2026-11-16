import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Yüzen cam kapsül biçiminde, etiketsiz 5 slotlu alt navigasyon.
///
/// Slotlar: Kokpit · Operasyon · **+** (AI giriş) · Sağlık · Raporlar.
/// [currentIndex] dört sekmeyi (0..3) gösterir; ortadaki + bir sekme değildir.
/// İçerik barın arkasından akar (Scaffold.extendBody) ve bulanık görünür;
/// seçili sekme, ikonun arkasındaki açık renkli kapsülle belirtilir.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCreate,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  /// Kapsülün yüksekliği.
  static const double height = 64;

  /// Kapsülün ekran kenarlarından ve alttan boşluğu.
  static const double margin = 16;
  static const double bottomGap = 8;

  static const List<_BarItem> _items = [
    _BarItem('Kokpit', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _BarItem(
      'Operasyon',
      Icons.check_circle_outline_rounded,
      Icons.check_circle_rounded,
    ),
    _BarItem('Sağlık', Icons.favorite_border_rounded, Icons.favorite_rounded),
    _BarItem('Raporlar', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  ];

  void _select(int index) {
    HapticFeedback.selectionClick();
    onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    Widget tab(int index) => Expanded(
          child: _TabButton(
            item: _items[index],
            selected: currentIndex == index,
            onTap: () => _select(index),
          ),
        );

    const radius = BorderRadius.all(Radius.circular(height / 2));

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: bottomGap),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(margin, 0, margin, bottomGap),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: radius,
                  border: Border.all(
                    color: AppColors.glassBorder,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    tab(0),
                    tab(1),
                    Expanded(child: _CreateButton(onTap: onCreate)),
                    tab(2),
                    tab(3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem {
  const _BarItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _BarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Etiket görünmez ama ekran okuyucu ve uzun basış ipucu için korunur.
    return Semantics(
      label: item.label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.navSelected
                    : AppColors.navSelected.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(26),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey<bool>(selected),
                  size: 28,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Yeni giriş',
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Yeni giriş',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Center(
            child: SizedBox(
              height: 52,
              child: Icon(
                Icons.add_circle_outline_rounded,
                size: 32,
                color: AppColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
