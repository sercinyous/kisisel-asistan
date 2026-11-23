import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_source.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../data/health_repository.dart';
import 'health_format.dart';
import 'health_widgets.dart';
import 'providers/targets_providers.dart';
import 'providers/week_deficit_providers.dart';
import 'today/today_common.dart';
import 'trend_providers.dart' show trendClockProvider;
import 'workouts_section.dart';

/// Haftalık detayda seçilebilen ölçüler.
enum WeeklyMetric {
  kcal('Kalori'),
  deficit('Açık'),
  protein('Protein'),
  steps('Adım'),
  sleep('Uyku'),
  workouts('Antrenman');

  const WeeklyMetric(this.label);

  final String label;
}

/// Seçilebilen aralıklar (gün).
const List<int> weeklyDetailRanges = [7, 30, 90];

/// Detay ekranının bir günü.
class DetailDay {
  const DetailDay({
    required this.date,
    required this.intakeKcal,
    required this.deficit,
    required this.expenditure,
    required this.proteinG,
    required this.steps,
    required this.sleepMinutes,
    required this.workouts,
  });

  final DateTime date;

  /// Öğün girilmediyse `null`.
  final double? intakeKcal;

  /// Harcama − alım (pozitif = açık); hesaplanamıyorsa `null`.
  final double? deficit;
  final int? expenditure;
  final double? proteinG;
  final int? steps;
  final int? sleepMinutes;
  final int workouts;

  double? value(WeeklyMetric m) => switch (m) {
        WeeklyMetric.kcal => intakeKcal,
        WeeklyMetric.deficit => deficit,
        WeeklyMetric.protein => proteinG,
        WeeklyMetric.steps => steps?.toDouble(),
        WeeklyMetric.sleep => sleepMinutes?.toDouble(),
        WeeklyMetric.workouts => workouts.toDouble(),
      };

  /// Açık güvenli sınırı aşıyor (min(%25 harcama, 1.000)).
  bool get deficitTooHigh {
    final d = deficit;
    final e = expenditure;
    return d != null && e != null && d > deficitCap(e);
  }
}

/// Bugünle biten son [days] günün verisi (eskiden yeniye). Kalori, açık ve
/// adım tek modelden ([healthDaysProvider]); protein, uyku ve antrenman
/// depodan.
final weeklyDetailDaysProvider =
    FutureProvider.autoDispose.family<List<DetailDay>, int>((ref, days) async {
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  final from = AppDates.addDays(today, -(days - 1));
  final repository = ref.watch(healthRepositoryProvider);
  final healthRead =
      ref.watch(healthDaysProvider((from: from, to: today)).future);
  final nutritionRead =
      repository.fetchNutritionTotals(from, AppDates.endOfDay(today));
  final metricsRead = repository.fetchDailyMetrics(from, today,
      source: ref.watch(healthSourceProvider));
  final workoutsRead =
      repository.fetchWorkouts(from, AppDates.addDays(today, 1));
  await Future.wait<Object>(
      [healthRead, nutritionRead, metricsRead, workoutsRead]);
  final health = {
    for (final d in (await healthRead).days) AppDates.startOfDay(d.date): d,
  };
  final nutrition = {
    for (final n in await nutritionRead) AppDates.startOfDay(n.day): n,
  };
  final metrics = {
    for (final m in await metricsRead) AppDates.startOfDay(m.day): m,
  };
  final workouts = <DateTime, int>{};
  for (final w in await workoutsRead) {
    final day = AppDates.startOfDay(w.loggedAt);
    workouts[day] = (workouts[day] ?? 0) + 1;
  }
  return [
    for (var i = 0; i < days; i++)
      () {
        final day = AppDates.addDays(from, i);
        final h = health[day];
        final n = nutrition[day];
        final m = metrics[day];
        final logged = (n?.entryCount ?? 0) > 0;
        return DetailDay(
          date: day,
          intakeKcal: logged ? n!.calories : null,
          deficit: h?.deficit,
          expenditure: h?.expenditureKcal,
          proteinG: logged ? n!.proteinG : null,
          steps: (m?.steps ?? 0) > 0 ? m!.steps : null,
          sleepMinutes: (m?.sleepMinutes ?? 0) > 0 ? m!.sleepMinutes : null,
          workouts: workouts[day] ?? 0,
        );
      }(),
  ];
});

Color weeklyMetricColor(WeeklyMetric m) => switch (m) {
      WeeklyMetric.kcal => AppColors.nutrition,
      WeeklyMetric.deficit => AppColors.accent,
      WeeklyMetric.protein => AppColors.fitness,
      WeeklyMetric.steps => AppColors.ops,
      WeeklyMetric.sleep => AppColors.sleep,
      WeeklyMetric.workouts => AppColors.fitness,
    };

String formatWeeklyValue(WeeklyMetric m, double v) => switch (m) {
      WeeklyMetric.kcal => HealthFormat.kcal(v),
      WeeklyMetric.deficit => TodayFormat.deficit(v),
      WeeklyMetric.protein => '${HealthFormat.count(v)} g',
      WeeklyMetric.steps => HealthFormat.count(v),
      WeeklyMetric.sleep => KokpitFormat.sleep(v.round()),
      WeeklyMetric.workouts => '${v.round()}',
    };

/// Haftalık detay: kalori, açık, protein, adım, uyku ve antrenman tek ekranda
/// (eski Enerji dengesi ve Trend ekranlarının yerine).
class WeeklyDetailScreen extends ConsumerStatefulWidget {
  const WeeklyDetailScreen({
    super.key,
    this.initialMetric = WeeklyMetric.kcal,
    this.initialRange = 7,
  });

  final WeeklyMetric initialMetric;
  final int initialRange;

  static Future<void> open(
    BuildContext context, {
    WeeklyMetric metric = WeeklyMetric.kcal,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WeeklyDetailScreen(initialMetric: metric),
        ),
      );

  @override
  ConsumerState<WeeklyDetailScreen> createState() => _WeeklyDetailScreenState();
}

class _WeeklyDetailScreenState extends ConsumerState<WeeklyDetailScreen> {
  late WeeklyMetric _metric = widget.initialMetric;
  late int _range = widget.initialRange;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(weeklyDetailDaysProvider(_range));
    return Scaffold(
      appBar: AppBar(title: const Text('Haftalık detay')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 120),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in WeeklyMetric.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('weekly-metric-${m.name}'),
                      label: Text(m.label),
                      selected: m == _metric,
                      onSelected: (_) => setState(() => _metric = m),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              key: const Key('weekly-range'),
              showSelectedIcon: false,
              segments: [
                for (final r in weeklyDetailRanges)
                  ButtonSegment(value: r, label: Text('$r gün')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          const SizedBox(height: AppSpacing.grid),
          data.when(
            skipLoadingOnReload: true,
            loading: () => const HealthCardLoading(height: 220),
            error: (_, __) => BentoGrid(children: [
              BentoCell(
                child: BentoCard(
                  child: HealthCompactMessage(
                    text: 'Veriler yüklenemedi.',
                    onRetry: () =>
                        ref.invalidate(weeklyDetailDaysProvider(_range)),
                  ),
                ),
              ),
            ]),
            data: (days) => _DetailBody(metric: _metric, days: days),
          ),
          if (_metric == WeeklyMetric.workouts) const WorkoutsSection(),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.metric, required this.days});

  final WeeklyMetric metric;
  final List<DetailDay> days;

  double? _target(DailyTargets t, double? dailyDeficit) => switch (metric) {
        WeeklyMetric.kcal => t.kcal.toDouble(),
        WeeklyMetric.deficit => dailyDeficit,
        WeeklyMetric.protein => t.proteinG.toDouble(),
        WeeklyMetric.steps => t.steps.toDouble(),
        WeeklyMetric.sleep => t.sleepMinutes.toDouble(),
        WeeklyMetric.workouts => null,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(targetsProvider);
    final resolved = ref.watch(resolvedTargetsProvider).valueOrNull;
    final planned =
        resolved == null || resolved.deficit <= 0 ? null : resolved.deficit;
    final target = _target(targets, planned?.toDouble());
    final values = [for (final d in days) d.value(metric)];
    final known = values.whereType<double>().toList();
    final total = known.fold<double>(0, (s, v) => s + v);
    final average = known.isEmpty ? null : total / known.length;
    final color = weeklyMetricColor(metric);
    final short = days.length <= 7;
    final labels = short
        ? [for (final d in days) TodayFormat.weekdayShort[d.date.weekday - 1]]
        : null;
    final tooHigh = metric == WeeklyMetric.deficit &&
        days.take(days.length - 1).any((d) => d.deficitTooHigh);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return BentoGrid(children: [
      BentoCell(
        child: BentoCard(
          key: const Key('weekly-chart-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.insights_rounded,
                label: metric.label,
                color: color,
                trailing: 'son ${days.length} gün',
              ),
              const SizedBox(height: 12),
              Text(
                average == null
                    ? 'Veri yok'
                    : metric == WeeklyMetric.workouts ||
                            metric == WeeklyMetric.deficit
                        ? 'Toplam ${formatWeeklyValue(metric, total)}'
                        : 'Ortalama ${formatWeeklyValue(metric, average)}',
                key: const Key('weekly-headline'),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (metric == WeeklyMetric.deficit && known.isNotEmpty)
                Text(
                  TodayFormat.kg(total / 7700),
                  style: muted,
                ),
              const SizedBox(height: 14),
              DayBarChart(
                values: values,
                color: color,
                labels: labels,
                highlightIndex: days.length - 1,
                target: target,
                height: 150,
                semanticsLabel:
                    '${metric.label} grafiği, son ${days.length} gün',
              ),
              if (!short) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_date(days.first.date), style: muted),
                    const Spacer(),
                    Text('Bugün', style: muted),
                  ],
                ),
              ],
              if (target != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Kesikli çizgi: günlük hedef '
                  '(${formatWeeklyValue(metric, target)})',
                  style: muted,
                ),
              ],
              if (metric == WeeklyMetric.deficit) ...[
                const SizedBox(height: 4),
                Text(
                  'Bugünün çubuğu taralı: gün bitmeden kesinleşmez. '
                  'Turuncu çubuk: harcamadan fazla yenen gün.',
                  style: muted,
                ),
              ],
              if (tooHigh) ...[
                const SizedBox(height: 10),
                Row(
                  key: const Key('weekly-deficit-too-high'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Çok yüksek açık: bazı günler güvenli sınırın '
                        '(harcamanın %25\'i, en çok 1.000 kcal) üstünde. '
                        'Kas kaybını önlemek için biraz daha ye.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      if (short)
        BentoCell(
          child: BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BentoLabel(
                  icon: Icons.list_alt_rounded,
                  label: 'Günler',
                  color: color,
                ),
                const SizedBox(height: 8),
                for (final d in days.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${TodayFormat.weekdayLong[d.date.weekday - 1]} '
                            '${_date(d.date)}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          d.value(metric) == null
                              ? '—'
                              : formatWeeklyValue(metric, d.value(metric)!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: d.deficitTooHigh &&
                                    metric == WeeklyMetric.deficit
                                ? AppColors.warning
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    ]);
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
