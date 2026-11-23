import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../settings/presentation/settings_providers.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'weight_sheets.dart';

/// Kilo grafiğinde seçili pencere (gün). Sekme değişse de korunur.
final weightWindowProvider =
    StateProvider<int>((ref) => weightSeriesWindows.first);

/// Kilo ayrıntı ekranının kartı: son ölçüm, aylık değişim, hedefe kalan,
/// 30/90 gün seçimi, hedef çizgili grafik, ölçümler ve kilo ekle.
class WeightHistoryCard extends ConsumerWidget {
  const WeightHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(weightWindowProvider);
    final series = ref.watch(weightSeriesProvider(window));
    final settings = ref.watch(settingsOrDefaultProvider);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.monitor_weight_outlined,
            label: 'Kilo',
            color: AppColors.accent,
            trailing: 'son $window gün',
          ),
          const SizedBox(height: 8),
          series.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 120),
            error: (_, __) => HealthCompactMessage(
              text: 'Kilo ölçümleri yüklenemedi.',
              onRetry: () => ref.invalidate(weightSeriesProvider),
            ),
            data: (entries) {
              final now = DateTime.now();
              final trend = WeightTrend.from(
                entries,
                startKg: settings.startWeightKg,
                targetKg: settings.targetWeightKg,
                now: now,
              );
              if (trend == null) {
                return Text(
                  'Son $window günde kilo ölçümü yok. İlk ölçümünü ekle.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                );
              }
              return _WeightBody(
                entries: entries,
                trend: trend,
                window: window,
                targetKg: settings.targetWeightKg,
                now: now,
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, days) in weightSeriesWindows.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('$days gün'),
                      showCheckmark: false,
                      selected: days == window,
                      onSelected: (_) =>
                          ref.read(weightWindowProvider.notifier).state = days,
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => WeightHistorySheet.show(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(healthMinTouch, healthMinTouch),
                    ),
                    child: const Text('Ölçümler'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    onPressed: () => WeightFormSheet.show(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(healthMinTouch, healthMinTouch),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: Theme.of(context).textTheme.labelLarge,
                    ),
                    child: const Text('Kilo ekle'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightBody extends StatelessWidget {
  const _WeightBody({
    required this.entries,
    required this.trend,
    required this.window,
    required this.targetKg,
    required this.now,
  });

  final List<WeightEntry> entries;
  final WeightTrend trend;
  final int window;
  final double targetKg;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final monthChange = trend.monthChangeKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthBigValue(
          key: const Key('weight-latest'),
          value: HealthFormat.kg(trend.latestKg),
          unit: 'kg',
          large: true,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (monthChange != null)
              HealthChip(
                '${KokpitFormat.weightChange(monthChange)} bu ay',
                color: AppColors.accent,
              ),
            HealthChip(
              trend.reached
                  ? 'Hedefe ulaşıldı'
                  : 'Hedefe ${HealthFormat.kg(trend.remainingKg)} kg',
            ),
          ],
        ),
        // Üstte ve altta pay: doğrudan etiketler grafiğin dışına taşabilir.
        const SizedBox(height: 28),
        _WeightChart(
          entries: entries,
          window: window,
          targetKg: targetKg,
          now: now,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Çizgi grafik. Eksen yazısı yoktur; ilk ve son değer ile hedef çizgisi
/// doğrudan etiketlenir, böylece hiçbir bilgi yalnızca renge bağlı kalmaz.
class _WeightChart extends StatelessWidget {
  const _WeightChart({
    required this.entries,
    required this.window,
    required this.targetKg,
    required this.now,
  });

  static const double height = 132;

  final List<WeightEntry> entries;
  final int window;
  final double targetKg;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = AppDates.addDays(AppDates.startOfDay(now), -(window - 1));
    double xOf(DateTime at) => at.difference(start).inMinutes / 1440;

    final spots = [
      for (final e in entries) FlSpot(xOf(e.loggedAt), e.weightKg),
    ];
    final values = [targetKg, for (final e in entries) e.weightKg];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final pad = math.max(0.5, (high - low) * 0.12);
    final minY = low - pad;
    final maxY = high + pad;
    final maxX = window.toDouble();

    final first = entries.first;
    final last = entries.last;
    final dayFormat = DateFormat('d MMM', AppDates.locale);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final data = LineChartData(
      minX: 0,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: targetKg,
            color: AppColors.warning,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ],
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipColor: (_) => AppColors.inverseSurface,
          getTooltipItems: (touched) => [
            for (final spot in touched)
              LineTooltipItem(
                '${dayFormat.format(start.add(Duration(minutes: (spot.x * 1440).round())))}\n'
                '${HealthFormat.kg(spot.y)} kg',
                TextStyle(
                  color: AppColors.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AppColors.accent,
          barWidth: 2.2,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          belowBarData: BarAreaData(
            show: spots.length > 1,
            color: AppColors.accent.withValues(alpha: 0.10),
          ),
          dotData: FlDotData(
            // Yalnızca son nokta vurgulanır.
            checkToShowDot: (spot, bar) => spot == bar.spots.last,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              color: AppColors.accent,
              radius: 4,
              strokeWidth: 0,
            ),
          ),
        ),
      ],
    );

    final summary = entries.length > 1
        ? 'Kilo grafiği: son $window günde ${HealthFormat.kg(first.weightKg)} '
            'kilodan ${HealthFormat.kg(last.weightKg)} kiloya. '
            'Hedef çizgisi ${HealthFormat.plain(targetKg)} kilo.'
        : 'Kilo grafiği: son ölçüm ${HealthFormat.kg(last.weightKg)} kilo. '
            'Hedef çizgisi ${HealthFormat.plain(targetKg)} kilo.';

    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double px(DateTime at) => xOf(at) / maxX * width;
              double py(double kg) => (maxY - kg) / (maxY - minY) * height;

              final lastX = px(last.loggedAt);
              final firstX = px(first.loggedAt);
              final targetBelow = targetKg <= last.weightKg;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: LineChart(data)),
                  // İlk değer, son etiketle çakışmayacak kadar uzaktaysa.
                  if (lastX - firstX > 96)
                    Positioned(
                      left: firstX,
                      bottom: height - py(first.weightKg) + 6,
                      child: Text(
                        HealthFormat.kg(first.weightKg),
                        style: labelStyle,
                      ),
                    ),
                  Positioned(
                    right: math.max(0, width - lastX - 4),
                    bottom: height - py(last.weightKg) + 8,
                    child: Text(
                      HealthFormat.kg(last.weightKg),
                      key: const Key('weight-last-label'),
                      style: labelStyle?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: targetBelow ? py(targetKg) + 3 : null,
                    bottom: targetBelow ? null : height - py(targetKg) + 3,
                    child: Text(
                      'Hedef ${HealthFormat.plain(targetKg)} kg',
                      style: labelStyle?.copyWith(color: AppColors.warning),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
