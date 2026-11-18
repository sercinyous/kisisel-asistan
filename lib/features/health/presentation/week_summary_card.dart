import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_segment.dart';
import 'trend_providers.dart';
import 'trend_screen.dart';

/// Özet sekmesinin "Bu hafta" kartı: Adım, Uyku ve Antrenman tek kartta üç
/// satır; her satırda 7 günlük mini çubuk ve tek değer. Adım ve Uyku satırı
/// trend ekranını, Antrenman satırı Hareket görünümünü açar.
class WeekSummaryCard extends ConsumerWidget {
  const WeekSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final metrics = ref.watch(weekStepsProvider);
    final plan = ref.watch(weekWorkoutPlanProvider);
    final days = metrics.valueOrNull;
    final week = plan.valueOrNull;
    final avgSteps = days == null ? null : averageSteps(days);
    final avgSleep = days == null ? null : averageSleepMinutes(days);

    String metricValue(String? value) => metrics.hasError && days == null
        ? 'Yüklenemedi'
        : value ?? KokpitFormat.none;

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        AppSpacing.cardPadding,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bu hafta',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(
                'günlük ortalama',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _WeekRow(
            key: const Key('week-row-steps'),
            label: 'Adım',
            color: AppColors.fitness,
            values: [for (final d in days ?? const <DailyHealthMetric>[]) d.steps.toDouble()],
            valueKey: const Key('week-steps'),
            value: metricValue(
              avgSteps == null ? null : HealthFormat.count(avgSteps),
            ),
            onTap: () => TrendScreen.open(context, TrendMetric.steps),
          ),
          Divider(height: 1, color: AppColors.border),
          _WeekRow(
            key: const Key('week-row-sleep'),
            label: 'Uyku',
            color: AppColors.sleep,
            values: [
              for (final d in days ?? const <DailyHealthMetric>[]) d.sleepMinutes.toDouble(),
            ],
            valueKey: const Key('week-sleep'),
            value: metricValue(
              avgSleep == null ? null : KokpitFormat.sleep(avgSleep),
            ),
            onTap: () => TrendScreen.open(context, TrendMetric.sleep),
          ),
          Divider(height: 1, color: AppColors.border),
          _WeekRow(
            key: const Key('week-row-workouts'),
            label: 'Antrenman',
            color: AppColors.fitness,
            values: [
              for (final d in week?.days ?? const <WorkoutPlanDay>[])
                d.done.length.toDouble(),
            ],
            valueKey: const Key('week-workouts'),
            value: plan.hasError && week == null
                ? 'Yüklenemedi'
                : week == null
                    ? KokpitFormat.none
                    : week.plannedCount > 0
                        ? '${week.doneCount} / ${week.plannedCount}'
                        : '${week.doneCount}',
            onTap: () => ref.read(healthSegmentProvider.notifier).state =
                HealthSegment.movement,
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    super.key,
    required this.label,
    required this.color,
    required this.values,
    required this.valueKey,
    required this.value,
    required this.onTap,
  });

  final String label;
  final Color color;
  final List<double> values;
  final Key valueKey;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              _MiniBars(values: values, color: color),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 72),
                child: Text(
                  value,
                  key: valueKey,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 7 küçük çubuk; değeri olmayan gün ince soluk bir çizgidir.
class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values, required this.color});

  static const double _height = 20;
  static const double _barWidth = 6;

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final peak = values.fold<double>(0, math.max);
    return SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            _bar(i < values.length ? values[i] : 0, peak),
          ],
        ],
      ),
    );
  }

  Widget _bar(double value, double peak) {
    final empty = value <= 0 || peak <= 0;
    return SizedBox(
      width: _barWidth,
      height: empty ? 2 : math.max(4, _height * value / peak),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: empty ? AppColors.textMuted.withValues(alpha: 0.5) : color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
