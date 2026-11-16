import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import 'reports_providers.dart';

/// Günlük tamamlama grafiği: gün başına iş ve form çubukları.
/// Seriler renk + lejant etiketiyle ayrılır; her çubuğun değeri üstünde yazar.
class ReportDailyCompletionCard extends StatelessWidget {
  const ReportDailyCompletionCard({super.key, required this.days});

  /// Eskiden yeniye (Pazartesi → Pazar).
  final List<DayMetrics> days;

  static const double _rodWidth = 14;
  static const double _rodGap = 6;

  String _semanticsLabel() {
    String value(int? rate) =>
        rate == null ? 'veri yok' : KokpitFormat.percent(rate);
    final parts = [
      for (final day in days)
        '${KokpitFormat.weekdayShort(day.date)}: iş ${value(day.workRate)}, '
            'form ${value(day.formRate)}',
    ];
    return 'Günlük iş ve form tamamlama yüzdeleri. ${parts.join('; ')}.';
  }

  BarChartRodData _rod(int? rate, Color color) => BarChartRodData(
        toY: (rate ?? 0).toDouble(),
        color: color,
        width: _rodWidth,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        label: BarChartRodLabel(
          show: rate != null,
          text: '${rate ?? ''}',
          offset: const Offset(0, 2),
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.bar_chart_rounded,
            label: 'Günlük tamamlama',
            color: AppColors.ops,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Legend(color: AppColors.ops, label: 'İş'),
              _Legend(color: AppColors.fitness, label: 'Form'),
            ],
          ),
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Bu rapor için gün gün döküm yok.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            Semantics(
              container: true,
              label: _semanticsLabel(),
              child: ExcludeSemantics(
                // Çubuk üstü etiketler için 44pt'lik gün sütununda yer sınırlı;
                // grafik içi yazı en çok 1.15 kat büyür (sayılar ekran okuyucu
                // özetinde ve kartlarda da var).
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: Padding(
                    // 100'lük çubuğun etiketi çizim alanının üstüne taşar.
                    padding: const EdgeInsets.only(top: 18),
                    child: SizedBox(
                      height: 140,
                      child: BarChart(
                        BarChartData(
                          minY: 0,
                          maxY: 100,
                          alignment: BarChartAlignment.spaceAround,
                          barTouchData: const BarTouchData(enabled: false),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(
                            border: Border(
                              bottom: BorderSide(color: AppColors.border),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            leftTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 26,
                                getTitlesWidget: (value, meta) {
                                  final index = value.round();
                                  if (index < 0 || index >= days.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return SideTitleWidget(
                                    meta: meta,
                                    space: 6,
                                    child: Text(
                                      KokpitFormat.weekdayShort(
                                        days[index].date,
                                      ),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (final (index, day) in days.indexed)
                              BarChartGroupData(
                                x: index,
                                barsSpace: _rodGap,
                                barRods: [
                                  _rod(day.workRate, AppColors.ops),
                                  _rod(day.formRate, AppColors.fitness),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
