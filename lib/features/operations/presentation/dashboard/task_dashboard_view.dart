import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import 'task_dashboard_providers.dart';
import 'task_dashboard_stats.dart';

/// Panonun Bento ızgarası (veriden bağımsız test edilebilir).
class TaskDashboardGrid extends StatelessWidget {
  const TaskDashboardGrid({super.key, required this.stats});

  final TaskDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = stats.weekChangePercent;
    final summaryColor = change == null || change == 0
        ? AppColors.textSecondary
        : (change > 0 ? AppColors.positive : AppColors.negative);
    final rate = stats.completionRate;
    final best = stats.bestWeekday;

    return BentoGrid(
      children: [
        BentoCell(
          child: BentoCard(
            child: Row(
              children: [
                Icon(
                  change != null && change < 0
                      ? Icons.trending_down_outlined
                      : Icons.trending_up_outlined,
                  color: summaryColor,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    stats.summary,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
        BentoCell(
          child: BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BentoLabel(
                  icon: Icons.bar_chart_outlined,
                  label: 'Haftalık tamamlanan',
                  color: AppColors.accent,
                  trailing: 'Bu hafta ${stats.thisWeek}',
                ),
                const SizedBox(height: AppSpacing.md),
                _WeeklyBarChart(weeks: stats.weeks),
              ],
            ),
          ),
        ),
        BentoCell(
          span: 1,
          child: _StatCard(
            icon: Icons.task_alt_outlined,
            label: 'Tamamlama',
            color: AppColors.accent,
            value: rate == null ? '—' : '%${(rate * 100).round()}',
            caption: rate == null
                ? 'Planlı görev yok'
                : '${stats.scheduledDone} / ${stats.scheduledCount} görev',
            progress: rate,
          ),
        ),
        BentoCell(
          span: 1,
          child: _StatCard(
            icon: Icons.schedule_outlined,
            label: 'Geciken',
            color:
                stats.overdueCount > 0 ? AppColors.danger : AppColors.textMuted,
            value: '${stats.overdueCount}',
            caption: stats.overdueCount == 0 ? 'Gecikme yok' : 'Termini geçmiş',
          ),
        ),
        BentoCell(
          child: BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BentoLabel(
                  icon: Icons.calendar_view_week_outlined,
                  label: 'En verimli gün',
                  color: AppColors.accent,
                  trailing: best == null ? null : turkishWeekday(best),
                ),
                const SizedBox(height: AppSpacing.md),
                _WeekdayStrip(counts: stats.weekdayCounts, best: best),
              ],
            ),
          ),
        ),
        BentoCell(
          child: BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BentoLabel(
                  icon: Icons.donut_small_outlined,
                  label: 'Kategori dağılımı',
                  color: AppColors.nutrition,
                ),
                const SizedBox(height: AppSpacing.md),
                if (stats.categories.isEmpty)
                  Text(
                    'Henüz görev yok',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  )
                else
                  _CategoryBars(categories: stats.categories),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.caption,
    this.progress,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String value;
  final String caption;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: icon, label: label, color: color),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: color,
                backgroundColor: AppColors.surfaceHigh,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  const _WeeklyBarChart({required this.weeks});

  final List<WeekCount> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = weeks.fold<int>(0, (m, w) => math.max(m, w.count));
    final maxY = top == 0 ? 1.0 : top * 1.15;
    final color = AppColors.accent;
    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted);
    final dayFormat = DateFormat('d MMM', AppDates.locale);

    return Semantics(
      label: 'Haftalık tamamlanan görev grafiği. ${[
        for (final w in weeks)
          '${dayFormat.format(w.weekStart)} haftası ${w.count}',
      ].join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 170,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= weeks.length || weeks[i].count == 0) {
                        return const SizedBox.shrink();
                      }
                      return Text('${weeks[i].count}', style: labelStyle);
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      final isLast = i == weeks.length - 1;
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          isLast
                              ? 'Bu hf.'
                              : dayFormat.format(weeks[i].weekStart),
                          style: isLast
                              ? labelStyle?.copyWith(
                                  color: AppColors.textPrimary)
                              : labelStyle,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(enabled: false),
              barGroups: [
                for (final (i, w) in weeks.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: w.count.toDouble(),
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                        color: i == weeks.length - 1
                            ? color
                            : color.withValues(alpha: 0.45),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY,
                          color: AppColors.surfaceHigh,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip({required this.counts, required this.best});

  final List<int> counts;
  final int? best;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = counts.fold<int>(0, math.max);
    const short = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor:
                              top == 0 ? 0.06 : math.max(0.06, counts[i] / top),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: best == i + 1
                                  ? AppColors.accent
                                  : AppColors.surfaceHigh,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.chip / 2),
                            ),
                            child: const SizedBox(width: double.infinity),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      short[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: best == i + 1
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.categories});

  final List<MapEntry<String, int>> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = categories.fold<int>(0, (s, e) => s + e.value);
    final palette = [
      AppColors.accent,
      AppColors.accent,
      AppColors.nutrition,
      AppColors.fitness,
      AppColors.warning,
    ];
    return Column(
      children: [
        for (final (i, e) in categories.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  e.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  child: LinearProgressIndicator(
                    value: e.value / total,
                    minHeight: 8,
                    color: palette[i % palette.length],
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 64,
                child: Text(
                  '${e.value} · %${(e.value * 100 / total).round()}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Kaydırma kabı olmadan gömülebilen pano (İçgörü > Ayrıntılar > İş ayrıntısı).
class TaskDashboardSection extends ConsumerWidget {
  const TaskDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taskDashboardProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => BentoCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Pano yüklenemedi',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(taskDashboardProvider),
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
      data: (stats) => TaskDashboardGrid(stats: stats),
    );
  }
}
