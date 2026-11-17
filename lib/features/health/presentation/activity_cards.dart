import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'trend_providers.dart';
import 'trend_screen.dart';

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
          BentoLabel(
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
      return DecoratedBox(
        decoration:
            BoxDecoration(color: AppColors.fitness, shape: BoxShape.circle),
        child: SizedBox.square(
          dimension: _size,
          child: Icon(Icons.check_rounded, size: 12, color: AppColors.onAccent),
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
    return SizedBox.square(
      dimension: _size,
      child: Center(
        child: DecoratedBox(
          decoration:
              BoxDecoration(color: AppColors.border, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 6),
        ),
      ),
    );
  }
}

/// Üç yedi günlük kartın (Adım, Uyku, Kalori) ortak içeriği: ortalama +
/// gün başına mini çubuk. [average] `null` ise boş durum metni gösterilir.
/// Değeri olmayan gün [values]'ta 0'dır ve çubuğu görünmez.
class _WeekMiniBody extends StatelessWidget {
  const _WeekMiniBody({
    required this.days,
    required this.values,
    required this.color,
    required this.valueKey,
    required this.average,
    required this.unit,
    required this.emptyText,
    required this.semanticsTitle,
    required this.formatValue,
  });

  static const double _chartHeight = 44;

  final List<DateTime> days;
  final List<double> values;
  final Color color;
  final Key valueKey;

  /// Biçimlenmiş ortalama ("9.300", "7 sa 12 dk"); veri yoksa `null`.
  final String? average;
  final String unit;
  final String emptyText;

  /// Ekran okuyucu başlığı ("Son 7 günün adımları").
  final String semanticsTitle;
  final String Function(double value) formatValue;

  @override
  Widget build(BuildContext context) {
    final avg = average;
    if (avg == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HealthBigValue(value: '—', unit: 'ort.'),
          const SizedBox(height: 4),
          HealthCompactMessage(text: emptyText),
        ],
      );
    }

    final today = AppDates.startOfDay(DateTime.now());
    final peak = math.max(values.reduce(math.max), 1.0);
    final summary = StringBuffer('$semanticsTitle, ortalama $avg. ')
      ..writeAll(
        [
          for (final (index, d) in days.indexed)
            '${_weekdayLong(d)} '
                '${values[index] > 0 ? formatValue(values[index]) : 'veri yok'}',
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
            // Yarım genişlikteki kartta büyük metin ölçeğinde taşmak yerine
            // küçülür.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: HealthBigValue(
                key: valueKey,
                value: avg,
                unit: unit,
                singleLine: true,
              ),
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
                  maxY: peak,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  // Dokunma kartındır (Trend açar): grafik kendi dokunma
                  // tanıyıcısıyla jesti yutmasın. Gün değerleri Semantics
                  // etiketinde ve Trend ekranında okunur.
                  barTouchData: const BarTouchData(enabled: false),
                  barGroups: [
                    for (final (index, d) in days.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: values[index],
                            width: 10,
                            borderRadius: BorderRadius.circular(4),
                            // Bugün henüz bitmedi: soluk çizilir.
                            color: d == today
                                ? color.withValues(alpha: 0.45)
                                : color,
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
                    child: HealthWeekdayLabel(d, highlight: d == today),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bugünle biten 7 günün adımları: ortalama + gün başına çubuk. Dokununca
/// trend ekranı açılır.
class StepsWeekCard extends ConsumerWidget {
  const StepsWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(weekStepsProvider);
    return BentoCard(
      onTap: () => TrendScreen.open(context, TrendMetric.steps),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
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
            data: (days) {
              final average = averageSteps(days);
              return _WeekMiniBody(
                days: [for (final d in days) d.day],
                values: [for (final d in days) d.steps.toDouble()],
                color: AppColors.ops,
                valueKey: const Key('steps-average'),
                average: average == null ? null : HealthFormat.count(average),
                unit: 'ort.',
                emptyText: 'Son 7 günde adım verisi yok.',
                semanticsTitle: 'Son 7 günün adımları',
                formatValue: HealthFormat.count,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Bugünle biten 7 günün uykusu: ortalama süre + gün başına çubuk. Veri,
/// adım kartıyla aynı günlük sağlık özetinden gelir. Dokununca trend ekranı
/// açılır.
class SleepWeekCard extends ConsumerWidget {
  const SleepWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(weekStepsProvider);
    return BentoCard(
      onTap: () => TrendScreen.open(context, TrendMetric.sleep),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.bedtime_rounded,
            label: 'Uyku',
            color: AppColors.accent,
            trailing: '7 gün',
          ),
          const SizedBox(height: 8),
          metrics.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(),
            error: (_, __) => HealthCompactMessage(
              text: 'Uyku verisi yüklenemedi.',
              onRetry: () => ref.invalidate(weekStepsProvider),
            ),
            data: (days) {
              final average = averageSleepMinutes(days);
              return _WeekMiniBody(
                days: [for (final d in days) d.day],
                values: [for (final d in days) d.sleepMinutes.toDouble()],
                color: AppColors.accent,
                valueKey: const Key('sleep-average'),
                average: average == null ? null : KokpitFormat.sleep(average),
                unit: 'ort.',
                emptyText: 'Son 7 günde uyku verisi yok.',
                semanticsTitle: 'Son 7 günün uykusu',
                formatValue: (v) => KokpitFormat.sleep(v.round()),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Bugünle biten 7 günün kalorisi: öğünü olan günlerin ortalaması + gün başına
/// çubuk. Öğün girilmeyen gün ortalamayı sıfıra çekmez. Dokununca trend ekranı
/// açılır.
class CaloriesWeekCard extends ConsumerWidget {
  const CaloriesWeekCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calories = ref.watch(weekCaloriesProvider);
    return BentoCard(
      onTap: () => TrendScreen.open(context, TrendMetric.calories),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.local_fire_department_rounded,
            label: 'Kalori',
            color: AppColors.nutrition,
            trailing: '7 gün',
          ),
          const SizedBox(height: 8),
          calories.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(),
            error: (_, __) => HealthCompactMessage(
              text: 'Kalori verisi yüklenemedi.',
              onRetry: () => ref.invalidate(weekCaloriesProvider),
            ),
            data: (days) {
              final average = averageCalories(days);
              return _WeekMiniBody(
                days: [for (final d in days) d.day],
                values: [
                  for (final d in days) d.entryCount > 0 ? d.calories : 0.0,
                ],
                color: AppColors.nutrition,
                valueKey: const Key('calories-average'),
                average: average == null ? null : HealthFormat.count(average),
                unit: 'kcal ort.',
                emptyText: 'Son 7 günde öğün kaydı yok.',
                semanticsTitle: 'Son 7 günün kalorisi',
                formatValue: HealthFormat.count,
              );
            },
          ),
        ],
      ),
    );
  }
}
