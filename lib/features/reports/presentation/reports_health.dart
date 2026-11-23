import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../health/domain/health_models.dart';
import '../../health/presentation/health_providers.dart'
    show weightSeriesProvider;
import '../../health/presentation/providers/body_providers.dart';
import '../../health/presentation/providers/streaks_providers.dart';
import '../../health/presentation/providers/week_deficit_providers.dart';
import '../../health/presentation/weekly_detail_screen.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';

/// İçgörü'nün kilo farkı için baktığı gün sayısı.
const int reportsWeightLookbackDays = 120;

final NumberFormat _oneDecimal = NumberFormat('0.0', 'tr_TR');

/// "−3.100 kcal" (açık) ya da "+400 kcal" (fazla). Sıfıra yakınsa "0 kcal".
String deficitLabel(double kcal) {
  final rounded = kcal.round();
  if (rounded == 0) return '0 kcal';
  final text = KokpitFormat.thousands.format(rounded.abs());
  return rounded > 0 ? '−$text kcal' : '+$text kcal';
}

/// "≈0,4 kg" — açık yoksa `null`.
String? deficitKgLabel(double kg) =>
    kg <= 0.05 ? null : '≈${_oneDecimal.format(kg)} kg';

/// [from, to] aralığında kilo farkı: aralıktaki son tartı − aralıktan önceki
/// son tartı (yoksa aralığın ilk tartısı). İki ölçüm yoksa `null`.
double? periodWeightChange(
  List<WeightEntry> series,
  DateTime from,
  DateTime to,
) {
  final start = AppDates.startOfDay(from);
  final end = AppDates.endOfDay(to);
  final sorted = [...series]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  final before = sorted.where((e) => e.loggedAt.isBefore(start)).toList();
  final inside = sorted
      .where((e) => !e.loggedAt.isBefore(start) && !e.loggedAt.isAfter(end))
      .toList();
  if (inside.isEmpty) return null;
  final base = before.isNotEmpty ? before.last : inside.first;
  if (identical(base, inside.last)) return null;
  return inside.last.weightKg - base.weightKg;
}

/// Bir ayın mezura farkı.
typedef MeasurementDelta = ({BodyField field, double deltaCm});

/// Ay içindeki son ölçü − aydan önceki son ölçü (yoksa ayın ilk ölçüsü).
/// Yalnızca iki ucu da olan alanlar; [BodyField] sırasıyla.
List<MeasurementDelta> monthMeasurementDeltas(
  List<BodyMeasurement> measurements,
  DateTime month,
) {
  final first = DateTime(month.year, month.month);
  final next = DateTime(month.year, month.month + 1);
  final sorted = [...measurements]
    ..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
  final result = <MeasurementDelta>[];
  for (final field in BodyField.values) {
    final withField = sorted.where((m) => m[field] != null).toList();
    final inside = withField
        .where(
            (m) => !m.measuredOn.isBefore(first) && m.measuredOn.isBefore(next))
        .toList();
    if (inside.isEmpty) continue;
    final before =
        withField.where((m) => m.measuredOn.isBefore(first)).toList();
    final base = before.isNotEmpty ? before.last : inside.first;
    if (identical(base, inside.last)) continue;
    final delta = inside.last[field]! - base[field]!;
    result.add((field: field, deltaCm: delta));
  }
  return result;
}

/// "Bel −2,5 cm"
String measurementDeltaLabel(MeasurementDelta d) {
  final abs = _oneDecimal.format(d.deltaCm.abs());
  final sign = d.deltaCm.abs() < 0.05
      ? '±'
      : d.deltaCm < 0
          ? '−'
          : '+';
  return '${d.field.label} $sign$abs cm';
}

// ------------------------------------------------------------------- hafta

/// Haftalık İçgörü'nün sağlık kartı: hedefe göre açık, seriler, kilo farkı.
/// Değerler Sağlık sekmesiyle aynı sağlayıcılardan gelir.
class ReportsHealthWeekCard extends ConsumerWidget {
  const ReportsHealthWeekCard({super.key, required this.weekStart});

  /// Haftanın pazartesisi.
  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(kokpitClockProvider);
    final isCurrent = AppDates.weekStart(now) == weekStart;
    final deficit = ref.watch(weekDeficitProvider(weekStart));
    final streaks = isCurrent ? ref.watch(streaksProvider).valueOrNull : null;
    final weights =
        ref.watch(weightSeriesProvider(reportsWeightLookbackDays)).valueOrNull;
    final weightChange = weights == null
        ? null
        : periodWeightChange(
            weights, weekStart, AppDates.addDays(weekStart, 6));

    return deficit.when(
      skipLoadingOnRefresh: true,
      loading: () => const KokpitSkeletonCard(height: 168),
      // Sağlık verisi okunamazsa rapor ekranı kalabalıklaşmasın: kart
      // yalnızca açıklama satırına iner (yenileme Sağlık sekmesinde).
      error: (_, __) => const KokpitInlineMessage(
        icon: Icons.cloud_off_outlined,
        message: 'Haftalık açık şu an okunamadı.',
      ),
      data: (week) {
        final hasData = week.days.any((d) => d.deficit != null);
        final surplus = week.surplusGoal;
        final kgLabel = deficitKgLabel(surplus ? -week.kg : week.kg);
        final target = week.targetKcal;
        return BentoCard(
          key: const ValueKey('reports-health-week'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const WeeklyDetailScreen())),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.local_fire_department_outlined,
                label: surplus ? 'Haftalık fazla' : 'Haftalık açık',
                color: AppColors.nutrition,
                trailing: isCurrent ? 'şu ana kadar' : null,
              ),
              const SizedBox(height: AppSpacing.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      hasData
                          ? deficitLabel(week.totalKcal)
                          : KokpitFormat.none,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (hasData && kgLabel != null) ...[
                    const SizedBox(width: AppSpacing.s),
                    Text(
                      kgLabel,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
              if (target > 0) ...[
                const SizedBox(height: AppSpacing.md),
                KokpitBar(
                  value: hasData ? week.progress : 0,
                  color: AppColors.nutrition,
                  height: 8,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Hedef ${deficitLabel(surplus ? -target.toDouble() : target.toDouble())}'
                  '${hasData ? ' · %${(week.progress * 100).round().clamp(0, 999)}' : ''}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ] else if (!hasData) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Bu hafta için öğün ya da harcama verisi yok.',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final (i, cell) in [
                    for (final kind in StreakKind.values)
                      if (streaks?.of(kind) case final s?)
                        (
                          label: '${kind.label} serisi',
                          value: '${s.current} gün',
                        ),
                    (
                      label: 'Kilo',
                      value: weightChange == null
                          ? KokpitFormat.none
                          : KokpitFormat.weightChange(weightChange),
                    ),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.s),
                    Expanded(
                        child: _MiniStat(label: cell.label, value: cell.value)),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- ay

/// Ay görünümünde mezura farkları ("Bel −2,5 cm"). Ölçü yoksa çizilmez.
class ReportsMeasurementMonthCard extends ConsumerWidget {
  const ReportsMeasurementMonthCard({super.key, required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measurements = ref.watch(measurementsProvider).valueOrNull;
    if (measurements == null) return const SizedBox.shrink();
    final deltas = monthMeasurementDeltas(measurements, month);
    if (deltas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.grid),
      child: BentoCard(
        key: const ValueKey('reports-measurement-month'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BentoLabel(
              icon: Icons.straighten_outlined,
              label: 'Ölçü değişimi',
              trailing: '${deltas.length} ölçü',
            ),
            const SizedBox(height: 4),
            for (final (i, d) in deltas.indexed)
              RitimListRow(
                showDivider: i > 0,
                title: d.field.label,
                // Yalnızca azalan bel/kalça iyi sayılır (mint); artış
                // suçlanmaz, nötr gri kalır.
                delta: measurementDeltaLabel(d)
                    .substring(d.field.label.length + 1),
                deltaColor: d.field.lowerIsBetter &&
                        d.deltaCm < 0 &&
                        d.deltaCm.abs() >= 0.05
                    ? AppColors.positive
                    : AppColors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}
