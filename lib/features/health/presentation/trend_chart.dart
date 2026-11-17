import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../domain/goal_rules.dart';
import '../domain/trend_stats.dart';
import 'health_format.dart';
import 'health_widgets.dart';

/// Metriğin vurgu rengi (etkin temadan okunur; `const` içinde kullanılmaz).
Color trendMetricColor(TrendMetric metric) => switch (metric) {
      TrendMetric.steps => AppColors.ops,
      TrendMetric.sleep => AppColors.accent,
      TrendMetric.calories => AppColors.nutrition,
    };

IconData trendMetricIcon(TrendMetric metric) => switch (metric) {
      TrendMetric.steps => Icons.directions_walk_rounded,
      TrendMetric.sleep => Icons.bedtime_rounded,
      TrendMetric.calories => Icons.local_fire_department_rounded,
    };

String trendMetricLabel(TrendMetric metric) => switch (metric) {
      TrendMetric.steps => 'Adım',
      TrendMetric.sleep => 'Uyku',
      TrendMetric.calories => 'Kalori',
    };

/// Günlük değeri metriğin biriminde yazar: "10.500", "7 sa 12 dk", "1.960 kcal".
String formatTrendValue(TrendMetric metric, double value) => switch (metric) {
      TrendMetric.steps => HealthFormat.count(value),
      TrendMetric.sleep => KokpitFormat.sleep(value.round()),
      TrendMetric.calories => HealthFormat.kcal(value),
    };

/// Grafikteki çizgi ya da bandın açıklaması; eşikler [GoalRules] sabitlerinden
/// gelir ("kesikli çizgi: hedef", "bant: hedefin %85–%110'u").
String trendGoalCaption(TrendMetric metric, int target) {
  switch (metric) {
    case TrendMetric.steps:
      return 'Kesikli çizgi: hedef (${HealthFormat.count(target)} adım)';
    case TrendMetric.sleep:
      final line = target * GoalRules.sleepMinPercent / 100;
      return 'Kesikli çizgi: hedefin %${GoalRules.sleepMinPercent}\'ı '
          '(${KokpitFormat.sleep(line.round())})';
    case TrendMetric.calories:
      final low = target * GoalRules.caloriesMinPercent / 100;
      final high = target * GoalRules.caloriesMaxPercent / 100;
      return 'Bant: hedefin %${GoalRules.caloriesMinPercent}–'
          '%${GoalRules.caloriesMaxPercent}\'u '
          '(${HealthFormat.count(low)}–${HealthFormat.count(high)} kcal)';
  }
}

/// Dönemin günlük çubuk grafiği.
///
/// Tutan gün vurgulu, tutmayan soluk, bugünün (henüz değerlendirilmeyen)
/// çubuğu içi boş çerçevedir; verisiz ve gelecek günlerde yalnızca soluk
/// zemin kalır. Hedef çizgisi (kalorilerde %85–%110 bandı) [GoalRules]
/// eşiklerinden çizilir. [target] günlük hedeftir (adım, dakika ya da kcal).
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({
    super.key,
    required this.stats,
    required this.target,
    required this.metric,
    this.today,
    this.height = 190,
  });

  final TrendStats stats;
  final int target;
  final TrendMetric metric;

  /// Verilirse alt etiketlerde bugün vurgulanır.
  final DateTime? today;
  final double height;

  bool get _isMonth => stats.days.length > 7;

  /// Eşik çizgisi (adım, uyku); kalorilerde `null`.
  double? get _line => switch (metric) {
        TrendMetric.steps => target * GoalRules.stepsMinPercent / 100,
        TrendMetric.sleep => target * GoalRules.sleepMinPercent / 100,
        TrendMetric.calories => null,
      };

  /// Kalori bandı; diğer metriklerde `null`.
  (double, double)? get _band => metric == TrendMetric.calories
      ? (
          target * GoalRules.caloriesMinPercent / 100,
          target * GoalRules.caloriesMaxPercent / 100,
        )
      : null;

  double get _maxY {
    var top = 0.0;
    for (final d in stats.days) {
      final v = d.value;
      if (v != null) top = math.max(top, v);
    }
    top = math.max(top, math.max(_line ?? 0, _band?.$2 ?? 0));
    return top <= 0 ? 1 : top * 1.12;
  }

  String _statusText(TrendDay d) => switch (d.status) {
        DayStatus.hit => 'hedefte',
        DayStatus.miss => 'hedef dışı',
        DayStatus.inProgress => 'devam ediyor',
        DayStatus.noData => 'veri yok',
        DayStatus.future => '',
      };

  String get _semanticsLabel {
    final buffer = StringBuffer('${trendMetricLabel(metric)} grafiği. ');
    if (stats.dataDays > 0) {
      buffer.write('${stats.hitDays} / ${stats.dataDays} gün hedefte. ');
    }
    final withValue = [
      for (final d in stats.days)
        if (d.value != null)
          '${DateFormat('d MMMM EEEE', AppDates.locale).format(d.day)} '
              '${formatTrendValue(metric, d.value!)}, ${_statusText(d)}',
    ];
    buffer.write(withValue.isEmpty ? 'Veri yok.' : withValue.join('. '));
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final color = trendMetricColor(metric);
    final maxY = _maxY;
    final days = stats.days;
    final barWidth = _isMonth ? 6.0 : 18.0;
    final radius = BorderRadius.circular(barWidth / 3);
    final trackColor = AppColors.surfaceHigh;
    final band = _band;
    final line = _line;
    final todayDay = today == null ? null : AppDates.startOfDay(today!);

    BackgroundBarChartRodData track() => BackgroundBarChartRodData(
          show: true,
          toY: maxY,
          color: trackColor,
        );

    BarChartRodData rod(TrendDay d) {
      final value = d.value ?? 0;
      return switch (d.status) {
        DayStatus.hit => BarChartRodData(
            toY: value,
            width: barWidth,
            borderRadius: radius,
            color: color,
            backDrawRodData: track(),
          ),
        DayStatus.miss => BarChartRodData(
            toY: value,
            width: barWidth,
            borderRadius: radius,
            color: color.withValues(alpha: 0.35),
            backDrawRodData: track(),
          ),
        DayStatus.inProgress => BarChartRodData(
            toY: value,
            width: barWidth,
            borderRadius: radius,
            color: color.withValues(alpha: 0.12),
            borderSide:
                BorderSide(color: color.withValues(alpha: 0.8), width: 1.5),
            backDrawRodData: track(),
          ),
        DayStatus.noData || DayStatus.future => BarChartRodData(
            toY: 0,
            width: barWidth,
            borderRadius: radius,
            color: color.withValues(alpha: 0),
            backDrawRodData: track(),
          ),
      };
    }

    Widget bottomTitle(double value, TitleMeta meta) {
      final index = value.round();
      if (index < 0 || index >= days.length) return const SizedBox.shrink();
      final day = days[index].day;
      final highlight = todayDay != null && day == todayDay;
      if (!_isMonth) {
        return SideTitleWidget(
          meta: meta,
          space: 6,
          child: HealthWeekdayLabel(day, highlight: highlight),
        );
      }
      // Ay görünümünde 31 sütunun etiketi sığmaz: 1, 5, 10, ... gösterilir.
      final show = day.day == 1 || day.day % 5 == 0;
      if (!show) return const SizedBox.shrink();
      return SideTitleWidget(
        meta: meta,
        space: 6,
        child: Text(
          '${day.day}',
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: highlight ? AppColors.textPrimary : AppColors.textMuted,
              ),
        ),
      );
    }

    return Semantics(
      label: _semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: bottomTitle,
                  ),
                ),
              ),
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  if (band != null)
                    HorizontalRangeAnnotation(
                      y1: band.$1,
                      y2: band.$2,
                      color: color.withValues(alpha: 0.16),
                    ),
                ],
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (line != null)
                    HorizontalLine(
                      y: line,
                      color: AppColors.textSecondary,
                      strokeWidth: 1,
                      dashArray: [5, 4],
                    ),
                ],
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => AppColors.inverseSurface,
                  getTooltipItem: (group, _, __, ___) {
                    final d = days[group.x];
                    if (d.status == DayStatus.future) return null;
                    final when = DateFormat('d MMM EEE', AppDates.locale)
                        .format(d.day);
                    final text = d.value == null
                        ? '$when\nveri yok'
                        : '$when\n${formatTrendValue(metric, d.value!)}'
                            ' · ${_statusText(d)}';
                    return BarTooltipItem(
                      text,
                      TextStyle(
                        color: AppColors.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final (index, d) in days.indexed)
                  BarChartGroupData(x: index, barRods: [rod(d)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
