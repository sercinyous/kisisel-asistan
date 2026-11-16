import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Instagram tarzı, etiketsiz 5 slotlu alt navigasyon.
///
/// Slotlar: Kokpit · Operasyon · **+** (AI giriş) · Sağlık · Raporlar.
/// [currentIndex] dört sekmeyi (0..3) gösterir; ortadaki + bir sekme değildir.
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

  static const double height = 56;

  static const List<_BarItem> _items = [
    _BarItem('Kokpit', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _BarItem('Operasyon', Icons.check_circle_outline_rounded,
        Icons.check_circle_rounded),
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

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
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
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          highlightShape: BoxShape.circle,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                key: ValueKey<bool>(selected),
                size: 28,
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
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
        child: InkResponse(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          radius: 32,
          child: Center(
            child: Container(
              width: 44,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 26,
                color: AppColors.background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
