import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/bento.dart';
import '../../../kokpit/presentation/kokpit_format.dart';
import '../health_format.dart';
import '../health_providers.dart';
import '../health_widgets.dart';
import '../providers/week_deficit_providers.dart';
import '../trend_providers.dart' show averageSleepMinutes;
import '../weekly_detail_screen.dart';
import 'today_common.dart';

/// Bu hafta: Pazartesi–Pazar günlük gerçek açık (bugün taralı), toplam ve
/// adım/uyku ortalamaları. Dokununca Haftalık detay (açık) açılır.
class WeekCard extends ConsumerWidget {
  const WeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final week = ref.watch(currentWeekDeficitProvider);
    final metrics = ref.watch(weekStepsProvider).valueOrNull;
    final steps = metrics == null ? null : averageSteps(metrics);
    final sleep = metrics == null ? null : averageSleepMinutes(metrics);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return BentoCard(
      key: const Key('week-card'),
      onTap: () =>
          WeeklyDetailScreen.open(context, metric: WeeklyMetric.deficit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            label: 'Bu hafta',
            trailing: week.valueOrNull == null
                ? 'kalori açığı'
                : TodayFormat.weekTitle(week.valueOrNull!),
          ),
          const SizedBox(height: 8),
          week.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 110),
            error: (_, __) => HealthCompactMessage(
              text: 'Haftalık açık yüklenemedi.',
              onRetry: () => ref.invalidate(currentWeekDeficitProvider),
            ),
            data: (w) {
              final todayIndex = w.days.indexWhere((d) => d.isToday);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DayBarChart(
                    values: [
                      for (var i = 0; i < 7; i++)
                        i < w.days.length ? w.dayBalance(w.days[i]) : null,
                    ],
                    color: AppColors.accent,
                    labels: TodayFormat.weekdayShort,
                    highlightIndex: todayIndex < 0 ? null : todayIndex,
                    height: 64,
                    semanticsLabel:
                        'Bu haftanın günlük ${TodayFormat.weekTitle(w)}',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    [
                      TodayFormat.weekTotal(w),
                      if (w.targetKcal > 0)
                        TodayFormat.weekTarget(w.targetKcal,
                            surplus: w.surplusGoal),
                    ].join(' / '),
                    key: const Key('week-total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(TodayFormat.weekKg(w), style: muted),
                  if (w.targetKcal > 0) ...[
                    const SizedBox(height: 8),
                    SlimBar(progress: w.progress, color: AppColors.accent),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: muted,
            child: Wrap(
              children: [
                const Text('Ort. '),
                Text(
                  steps == null ? '—' : HealthFormat.count(steps),
                  key: const Key('week-avg-steps'),
                ),
                const Text(' adım · '),
                Text(
                  sleep == null ? '—' : KokpitFormat.sleep(sleep),
                  key: const Key('week-avg-sleep'),
                ),
                const Text(' uyku'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
