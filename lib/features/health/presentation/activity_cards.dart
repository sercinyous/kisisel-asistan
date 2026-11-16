import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

String _weekdayLong(DateTime day) =>
    DateFormat('EEEE', AppDates.locale).format(day);

/// Bu haftanın antrenmanları: yapılan / planlı ve gün gün durum.
class WorkoutWeekCard extends ConsumerWidget {
  const WorkoutWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(weekWorkoutPlanProvider);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(
            icon: Icons.fitness_center_rounded,
            label: 'Antrenman',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 8),
          plan.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(),
            error: (_, __) => HealthCompactMessage(
              text: 'Antrenman planı yüklenemedi.',
              onRetry: () => ref.invalidate(weekWorkoutPlanProvider),
            ),
            data: (week) => _WorkoutWeekBody(week: week),
          ),
        ],
      ),
    );
  }
}

class _WorkoutWeekBody extends StatelessWidget {
  const _WorkoutWeekBody({required this.week});

  final WeekWorkoutPlan week;

  String _dayStatus(WorkoutPlanDay day) => day.isDone
      ? 'yapıldı'
      : day.isPlanned
          ? 'planlı'
          : 'boş';

  @override
  Widget build(BuildContext context) {
    final today = AppDates.startOfDay(DateTime.now());
    final hasPlan = week.plannedCount > 0;
    final summary = StringBuffer(
      hasPlan
          ? 'Bu hafta ${week.doneCount} antrenman yapıldı, '
              'plan ${week.plannedCount}. '
          : 'Bu hafta ${week.doneCount} antrenman yapıldı. ',
    )..writeAll(
        [for (final d in week.days) '${_weekdayLong(d.date)} ${_dayStatus(d)}'],
        ', ',
      );

    return Semantics(
      label: summary.toString(),
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HealthBigValue(
              key: const Key('workout-week-count'),
              value: '${week.doneCount}',
              unit: hasPlan ? '/ ${week.plannedCount} bu hafta' : 'bu hafta',
            ),
            if (!hasPlan && week.doneCount == 0) ...[
              const SizedBox(height: 4),
              Text(
                'Planlı antrenman yok.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (final day in week.days)
                  Expanded(
                    child: Column(
                      children: [
                        _DayMark(day: day),
                        const SizedBox(height: 6),
                        HealthWeekdayLabel(
                          day.date,
                          highlight: day.date == today,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Gün işareti. Durum yalnızca renkle değil biçimle de ayrılır: yapıldı =
/// dolu + onay, planlı = içi boş halka, boş = soluk nokta.
class _DayMark extends StatelessWidget {
  const _DayMark({required this.day});

  static const double _size = 16;

  final WorkoutPlanDay day;

  @override
  Widget build(BuildContext context) {
    if (day.isDone) {
      return const DecoratedBox(
        decoration:
            BoxDecoration(color: AppColors.fitness, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: _size,
          child: Icon(Icons.check_rounded, size: 12, color: AppColors.background),
        ),
      );
    }
    if (day.isPlanned) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.fitness, width: 1.5),
        ),
        child: const SizedBox.square(dimension: _size),
      );
    }
    return const SizedBox.square(
      dimension: _size,
      child: Center(
        child: DecoratedBox(
          decoration:
              BoxDecoration(color: AppColors.border, shape: BoxShape.circle),
          child: SizedBox.square(dimension: 6),
        ),
      ),
    );
  }
}

/// Bugünle biten 7 günün adımları: ortalama + gün başına çubuk.
class StepsWeekCard extends ConsumerWidget {
  const StepsWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(weekStepsProvider);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(
            icon: Icons.directions_walk_rounded,
            label: 'Adım',
            color: AppColors.ops,
            trailing: '7 gün',
          ),
          const SizedBox(height: 8),
          steps.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(),
            error: (_, __) => HealthCompactMessage(
              text: 'Adım verisi yüklenemedi.',
              onRetry: () => ref.invalidate(weekStepsProvider),
            ),
            data: (days) => _StepsBody(days: days),
          ),
        ],
      ),
    );
  }
}

class _StepsBody extends StatelessWidget {
  const _StepsBody({required this.days});

  static const double _chartHeight = 44;

  final List<DailyHealthMetric> days;

  @override
  Widget build(BuildContext context) {
    final average = averageSteps(days);
    if (average == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HealthBigValue(value: '—', unit: 'ort.'),
          SizedBox(height: 4),
          HealthCompactMessage(text: 'Son 7 günde adım verisi yok.'),
        ],
      );
    }

    final today = AppDates.startOfDay(DateTime.now());
    final peak = days.map((d) => d.steps).reduce(math.max);
    final summary = StringBuffer(
      'Son 7 günün adımları, ortalama ${HealthFormat.count(average)}. ',
    )..writeAll(
        [
          for (final d in days)
            '${_weekdayLong(d.day)} ${HealthFormat.count(d.steps)}',
        ],
        ', ',
      );

    return Semantics(
      label: summary.toString(),
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HealthBigValue(
              key: const Key('steps-average'),
              value: HealthFormat.count(average),
              unit: 'ort.',
            ),
            const SizedBox(height: 8),
            // Sabit yükseklik: Bento satırı içsel yükseklik ölçer, grafik
            // kendi başına ölçülemez.
            SizedBox(
              height: _chartHeight,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: 0,
                  maxY: peak.toDouble(),
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      fitInsideHorizontally: true,
                      getTooltipColor: (_) => AppColors.surfaceHigh,
                      getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                        '${DateFormat('EEE', AppDates.locale).format(days[group.x].day)}: '
                        '${HealthFormat.count(rod.toY)}',
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final (index, d) in days.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: d.steps.toDouble(),
                            width: 10,
                            borderRadius: BorderRadius.circular(4),
                            // Bugün henüz bitmedi: soluk çizilir.
                            color: d.day == today
                                ? AppColors.ops.withValues(alpha: 0.45)
                                : AppColors.ops,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final d in days)
                  Expanded(
                    child: HealthWeekdayLabel(d.day, highlight: d.day == today),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
