import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import '../health_widgets.dart';
import '../providers/body_providers.dart';
import 'body_format.dart';
import 'measurement_form_sheet.dart';

/// Grafik penceresi: son 4 hafta, son 12 hafta ya da tümü.
enum MeasurementRange {
  weeks4('4 hafta', 4),
  weeks12('12 hafta', 12),
  all('Tümü', null);

  const MeasurementRange(this.label, this.weeks);
  final String label;
  final int? weeks;
}

/// ÖlçülerScreen: başlangıç + son 4 giriş tablosu, alan seçince çizgi
/// grafik (4/12/Tümü) ve geçmiş girişler.
class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key, this.initialField});

  final BodyField? initialField;

  static Future<void> open(BuildContext context, {BodyField? field}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MeasurementsScreen(initialField: field),
      ));

  @override
  ConsumerState<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends ConsumerState<MeasurementsScreen> {
  late BodyField _field = widget.initialField ?? BodyField.waist;
  MeasurementRange _range = MeasurementRange.weeks12;

  Future<void> _delete(BodyMeasurement m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ölçümü sil'),
        content:
            Text('${BodyFormat.longDate(m.measuredOn)} ölçümü silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || m.id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(bodyRepositoryProvider).deleteMeasurement(m.id!);
      ref.invalidate(measurementsProvider);
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text(healthDeleteError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final measurements = ref.watch(measurementsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ölçüler'),
        actions: [
          IconButton(
            key: const Key('measurements-add'),
            tooltip: 'Ölç',
            onPressed: () => MeasurementFormSheet.show(context),
            icon: const Icon(Icons.add_outlined),
          ),
        ],
      ),
      body: measurements.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: HealthCompactMessage(
            text: 'Ölçüler yüklenemedi.',
            onRetry: () => ref.invalidate(measurementsProvider),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return _Empty(onAdd: () => MeasurementFormSheet.show(context));
          }
          final fields = [
            for (final f in BodyField.values)
              if (entries.any((e) => e[f] != null)) f,
          ];
          final field = fields.contains(_field) ? _field : fields.first;
          final newestFirst = [...entries]
            ..sort((a, b) => b.measuredOn.compareTo(a.measuredOn));
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, AppSpacing.s, AppSpacing.page, 120),
            children: [
              BentoCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                child: MeasurementTable(
                  entries: entries,
                  selected: field,
                  onSelect: (f) => setState(() => _field = f),
                ),
              ),
              const SizedBox(height: AppSpacing.grid),
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in fields) ...[
                            ChoiceChip(
                              key: Key('field-chip-${f.name}'),
                              label: Text(f.label),
                              selected: f == field,
                              onSelected: (_) => setState(() => _field = f),
                            ),
                            const SizedBox(width: AppSpacing.s),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    MeasurementChart(
                      entries: entries,
                      field: field,
                      range: _range,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Row(
                      children: [
                        for (final r in MeasurementRange.values) ...[
                          ChoiceChip(
                            key: Key('range-${r.name}'),
                            label: Text(r.label),
                            selected: r == _range,
                            onSelected: (_) => setState(() => _range = r),
                          ),
                          const SizedBox(width: AppSpacing.s),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              Text('Geçmiş', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.s),
              BentoCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  children: [
                    for (final m in newestFirst)
                      ListTile(
                        key:
                            Key('measurement-row-${dateOnlyIso(m.measuredOn)}'),
                        title: Text(BodyFormat.longDate(m.measuredOn)),
                        subtitle: Text(
                          [
                            for (final f in BodyField.values)
                              if (m[f] != null)
                                '${f.label} ${BodyFormat.cm(m[f]!)}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        onTap: () => MeasurementFormSheet.show(context,
                            date: m.measuredOn),
                        trailing: IconButton(
                          tooltip: 'Sil',
                          onPressed: () => _delete(m),
                          icon: Icon(Icons.delete_outline_outlined,
                              color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.straighten_outlined, size: 40, color: AppColors.accent),
            const SizedBox(height: AppSpacing.m),
            Text('Henüz ölçüm yok.', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.m),
            FilledButton(
              onPressed: onAdd,
              child: const Text('İlk ölçümü ekle'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satır = alan; sütunlar = Başlangıç, son 4 giriş, Δ (son − önceki,
/// hedef yönüne göre renkli). Satıra dokunmak alanı seçer.
class MeasurementTable extends StatelessWidget {
  const MeasurementTable({
    super.key,
    required this.entries,
    required this.selected,
    required this.onSelect,
  });

  final List<BodyMeasurement> entries;
  final BodyField selected;
  final ValueChanged<BodyField> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...entries]
      ..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
    final last4 =
        sorted.length <= 4 ? sorted : sorted.sublist(sorted.length - 4);
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: AppColors.textMuted, letterSpacing: 0.2);
    final cell = theme.textTheme.bodyMedium
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget box(Widget child, {double width = 62}) => SizedBox(
          width: width,
          height: 40,
          child: Align(alignment: Alignment.centerRight, child: child),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 72, child: Text('Alan', style: head)),
              box(Text('Başlangıç', style: head), width: 72),
              for (final m in last4)
                box(Text(BodyFormat.shortDate(m.measuredOn), style: head)),
              box(Text('Δ', style: head), width: 54),
            ],
          ),
          for (final f in BodyField.values)
            if (sorted.any((e) => e[f] != null))
              _row(context, f, sorted, last4, cell, box),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    BodyField f,
    List<BodyMeasurement> sorted,
    List<BodyMeasurement> last4,
    TextStyle? cell,
    Widget Function(Widget, {double width}) box,
  ) {
    final values = [
      for (final e in sorted)
        if (e[f] != null) e[f]!,
    ];
    final delta = values.length < 2
        ? null
        : roundCm(values.last - values[values.length - 2]);
    final isSelected = f == selected;
    return InkWell(
      key: Key('table-row-${f.name}'),
      borderRadius: BorderRadius.circular(AppRadii.chip),
      onTap: () => onSelect(f),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.10)
              : AppColors.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                f.label,
                style: cell?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
            ),
            box(Text(BodyFormat.cm(values.first), style: cell), width: 72),
            for (final m in last4)
              box(Text(
                m[f] == null ? '–' : BodyFormat.cm(m[f]!),
                style: cell?.copyWith(
                  color: m[f] == null ? AppColors.textMuted : null,
                ),
              )),
            box(
              Text(
                delta == null ? '–' : BodyFormat.delta(delta),
                style: cell?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: bodyDeltaColor(f, delta),
                ),
              ),
              width: 54,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seçili alanın çizgi grafiği.
class MeasurementChart extends StatelessWidget {
  const MeasurementChart({
    super.key,
    required this.entries,
    required this.field,
    required this.range,
    this.now,
  });

  final List<BodyMeasurement> entries;
  final BodyField field;
  final MeasurementRange range;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = AppDates.startOfDay(now ?? DateTime.now());
    final from =
        range.weeks == null ? null : AppDates.addDays(today, -range.weeks! * 7);
    final points = [
      for (final m in [
        ...entries
      ]..sort((a, b) => a.measuredOn.compareTo(b.measuredOn)))
        if (m[field] != null && (from == null || !m.measuredOn.isBefore(from)))
          (m.measuredOn, m[field]!),
    ];
    if (points.length < 2) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'Bu aralıkta ${field.label.toLowerCase()} ölçümü yok.'
                : 'Grafik için en az iki ölçüm gerekli.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final origin = points.first.$1;
    final spots = [
      for (final p in points)
        FlSpot(p.$1.difference(origin).inDays.toDouble(), p.$2),
    ];
    final ys = points.map((p) => p.$2);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.25).clamp(0.5, 10.0);
    final color = AppColors.accent;
    final change = roundCm(points.last.$2 - points.first.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              BodyFormat.cm(points.last.$2),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text('cm', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              '${BodyFormat.delta(change)} cm',
              key: const Key('chart-change'),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: bodyDeltaColor(field, change)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: minY - pad,
              maxY: maxY + pad,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: AppColors.border, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, meta) => Text(
                      BodyFormat.cm(roundCm(v)),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: spots.last.x <= 0 ? 1 : spots.last.x / 2,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        BodyFormat.shortDate(
                            AppDates.addDays(origin, v.round())),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.inverseSurface,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${BodyFormat.cm(s.y)} cm\n'
                        '${BodyFormat.shortDate(AppDates.addDays(origin, s.x.round()))}',
                        TextStyle(color: AppColors.onInverseSurface),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: color,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 3,
                      color: color,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.22),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
