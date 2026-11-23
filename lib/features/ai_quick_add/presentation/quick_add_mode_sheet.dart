import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/quick_add_mode.dart';

/// Giriş alanlarının arayüzdeki simge ve rengi.
extension QuickAddModeStyle on QuickAddMode {
  IconData get icon => switch (this) {
        QuickAddMode.work => Icons.work_outline_rounded,
        QuickAddMode.health => Icons.monitor_heart_rounded,
      };

  Color get color => switch (this) {
        QuickAddMode.work => AppColors.ops,
        QuickAddMode.health => AppColors.nutrition,
      };
}

/// Hangi alanın açılacağı sekmeden anlaşılmadığında (Kokpit, Raporlar)
/// gösterilen iki seçenekli sayfa.
class QuickAddModeSheet extends StatelessWidget {
  const QuickAddModeSheet({super.key});

  /// Seçilen alanı döndürür; vazgeçilirse `null`.
  static Future<QuickAddMode?> show(BuildContext context) {
    return showModalBottomSheet<QuickAddMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => const QuickAddModeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Ne eklemek istersin?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 14),
              for (final mode in QuickAddMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ModeOption(
                    mode: mode,
                    onTap: () => Navigator.of(context).pop(mode),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.onTap});

  final QuickAddMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.inner),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadii.inner),
                ),
                child: Icon(mode.icon, color: mode.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      mode.scopeHint,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
