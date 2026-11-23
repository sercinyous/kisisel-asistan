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
            icon: Icons.calendar_view_week_rounded,
            label: 'Bu hafta',
            color: AppColors.accent,
            trailing: 'kalori açığı',
          ),
          const SizedBox(height: 12),
          week.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 150),
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
                    values: [for (final d in w.days) d.deficit],
                    color: AppColors.accent,
                    labels: TodayFormat.weekdayShort,
                    highlightIndex: todayIndex < 0 ? null : todayIndex,
                    height: 96,
                    semanticsLabel: 'Bu haftanın günlük kalori açığı',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    [
                      TodayFormat.deficit(w.totalKcal),
                      if (w.targetKcal > 0)
                        'hedef ${HealthFormat.count(w.targetKcal)} kcal',
                    ].join(' / '),
                    key: const Key('week-total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(TodayFormat.kg(w.kg), style: muted),
                  if (w.targetKcal > 0) ...[
                    const SizedBox(height: 8),
                    SlimBar(progress: w.progress, color: AppColors.accent),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Average(
                  icon: Icons.directions_walk_rounded,
                  color: AppColors.ops,
                  label: 'Ort. adım',
                  value: steps == null ? '—' : HealthFormat.count(steps),
                  valueKey: const Key('week-avg-steps'),
                ),
              ),
              Expanded(
                child: _Average(
                  icon: Icons.bedtime_rounded,
                  color: AppColors.sleep,
                  label: 'Ort. uyku',
                  value: sleep == null ? '—' : KokpitFormat.sleep(sleep),
                  valueKey: const Key('week-avg-sleep'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Average extends StatelessWidget {
  const _Average({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted)),
              Text(
                value,
                key: valueKey,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
