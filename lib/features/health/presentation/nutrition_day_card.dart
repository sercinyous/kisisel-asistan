import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import 'health_format.dart';
import 'health_widgets.dart';

/// Beslenme sekmesinin başı: günün kalorisi (hedefe göre) ve makrolar.
class NutritionDayCard extends ConsumerWidget {
  const NutritionDayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nutrition = ref.watch(todayNutritionProvider);
    final settings = ref.watch(settingsOrDefaultProvider);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.restaurant_rounded,
            label: 'Bugün',
            color: AppColors.nutrition,
            trailing:
                'hedef ${HealthFormat.count(settings.dailyCalories)} kcal',
          ),
          const SizedBox(height: 8),
          nutrition.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 72),
            error: (_, __) => HealthCompactMessage(
              text: 'Günün özeti yüklenemedi.',
              onRetry: () => ref.invalidate(todayNutritionProvider),
            ),
            data: (day) {
              final target = settings.dailyCalories;
              final progress =
                  target <= 0 ? 0.0 : (day.calories / target).clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HealthBigValue(
                    key: const Key('nutrition-day-calories'),
                    value: HealthFormat.count(day.calories),
                    unit: 'kcal',
                    large: true,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHigh,
                      color: AppColors.nutrition,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Protein ${HealthFormat.grams(day.proteinG)} / '
                    '${settings.dailyProteinG} g · '
                    'Karb ${HealthFormat.grams(day.carbsG)} · '
                    'Yağ ${HealthFormat.grams(day.fatG)}',
                    key: const Key('nutrition-day-macros'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
