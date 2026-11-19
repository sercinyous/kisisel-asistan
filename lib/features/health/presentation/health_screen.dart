import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'activity_cards.dart';
import 'energy_card.dart';
import 'health_providers.dart';
import 'health_segment.dart';
import 'healthkit_card.dart';
import 'meals_section.dart';
import 'nutrition_day_card.dart';
import 'water_card.dart';
import 'week_summary_card.dart';
import 'weight_card.dart';
import 'workouts_section.dart';

export 'health_segment.dart' show HealthSegment, healthSegmentProvider;

/// Sağlık sekmesi: üstte Özet / Beslenme / Hareket seçimi; her görünüm
/// yaklaşık bir ekran. Kaynak (HealthKit / Google Health) yalnızca sorun
/// varken tek satır uyarı olarak görünür.
///
/// Başka bir ekrandan belirli görünümü açmak için [healthSegmentProvider]
/// ayarlanır (ör. Kokpit'ten Beslenme).
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _refresh(ProviderContainer container) async {
    invalidateHealthData(container);
    await resyncHealthKit(container);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final segment = ref.watch(healthSegmentProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              12,
              AppSpacing.page,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sağlık', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 12),
                _SegmentBar(
                  selected: segment,
                  onSelected: (value) =>
                      ref.read(healthSegmentProvider.notifier).state = value,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  _refresh(ProviderScope.containerOf(context, listen: false)),
              child: SingleChildScrollView(
                key: PageStorageKey('health-${segment.name}'),
                physics: const AlwaysScrollableScrollPhysics(),
                // Alt bar içeriğin üstüne bindiği için altta pay bırakılır.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  120,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HealthSourceBanner(),
                    switch (segment) {
                      HealthSegment.summary => const _SummaryView(),
                      HealthSegment.nutrition => const _NutritionView(),
                      HealthSegment.movement => const _MovementView(),
                    },
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView();

  @override
  Widget build(BuildContext context) => const BentoGrid(
        children: [
          BentoCell(child: WeightCard()),
          BentoCell(child: EnergyNetCard()),
          BentoCell(child: WeekSummaryCard()),
        ],
      );
}

class _NutritionView extends StatelessWidget {
  const _NutritionView();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoGrid(
            children: [
              BentoCell(child: NutritionDayCard()),
              BentoCell(child: WaterCard()),
            ],
          ),
          MealsSection(),
          SizedBox(height: AppSpacing.grid),
          BentoGrid(children: [BentoCell(child: CaloriesWeekCard())]),
        ],
      );
}

class _MovementView extends StatelessWidget {
  const _MovementView();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoGrid(
            children: [
              BentoCell(child: WorkoutWeekCard()),
              BentoCell(span: 1, child: StepsWeekCard()),
              BentoCell(span: 1, child: SleepWeekCard()),
            ],
          ),
          WorkoutsSection(),
        ],
      );
}

/// Kapsül biçimli üçlü seçim; seçili parça vurgu rengiyle doludur.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.selected, required this.onSelected});

  final HealthSegment selected;
  final ValueChanged<HealthSegment> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final segment in HealthSegment.values)
              Expanded(
                child: Semantics(
                  selected: segment == selected,
                  button: true,
                  child: Material(
                    key: Key('health-segment-${segment.name}'),
                    color: segment == selected
                        ? AppColors.accent
                        : AppColors.surface.withValues(alpha: 0),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelected(segment),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              segment.label,
                              maxLines: 1,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: segment == selected
                                    ? AppColors.onAccent
                                    : AppColors.textSecondary,
                                fontWeight: segment == selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
