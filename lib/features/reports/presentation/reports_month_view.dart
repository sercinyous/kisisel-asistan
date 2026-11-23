import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/domain/month_calendar.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import 'reports_health.dart';
import 'reports_state.dart';
import 'reports_widgets.dart';

/// İçinde bulunulan ay ve seçili ay (geleceğe gidilmez); ikisi de ayın 1'i.
({DateTime current, DateTime selected}) reportsMonthSelection(
  DateTime now,
  DateTime? picked,
) {
  final current = DateTime(now.year, now.month);
  if (picked == null) return (current: current, selected: current);
  final month = DateTime(picked.year, picked.month);
  return (
    current: current,
    selected: month.isAfter(current) ? current : month,
  );
}

/// Ay görünümü: ay seçici + ay özeti (rutin, görev, sağlık ortalamaları).
class ReportsMonthView extends ConsumerWidget {
  const ReportsMonthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:current, :selected) = reportsMonthSelection(
      ref.watch(kokpitClockProvider),
      ref.watch(reportsMonthProvider),
    );
    final overview = ref.watch(monthOverviewProvider(selected));

    void show(DateTime month) =>
        ref.read(reportsMonthProvider.notifier).state = month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportPeriodSwitcher(
          label: KokpitFormat.monthTitle(selected),
          caption: selected == current ? 'Bu ay' : null,
          previousTooltip: 'Önceki ay',
          nextTooltip: 'Sonraki ay',
          onPrevious: () => show(DateTime(selected.year, selected.month - 1)),
          onNext: selected.isBefore(current)
              ? () => show(DateTime(selected.year, selected.month + 1))
              : null,
        ),
        const SizedBox(height: 8),
        overview.when(
          loading: () => const KokpitSkeletonCard(height: 320),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Ay özeti yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(monthOverviewProvider(selected)),
          ),
          data: (value) => ReportsMonthSummary(overview: value),
        ),
        ReportsMeasurementMonthCard(month: selected),
      ],
    );
  }
}

/// Ay özeti ızgarası (Kokpit > Ay görünümündeki özetten taşındı).
class ReportsMonthSummary extends ConsumerWidget {
  const ReportsMonthSummary({super.key, required this.overview});

  final MonthOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(settingsOrDefaultProvider);
    final health = overview.health;
    final thousands = KokpitFormat.thousands;

    final routinePercent =
        completionPercent(overview.weeklyDone, overview.weeklyPlanned);
    final taskCount = overview.tasks.length;
    final taskPercent = completionPercent(overview.tasksDone, taskCount);
    final avgCalories = health.avgCalories;
    final weightChange = health.weightChangeKg;
    final hasHealth = health.avgSteps != null ||
        health.avgSleepMinutes != null ||
        avgCalories != null ||
        weightChange != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoGrid(
          children: [
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.repeat_outlined,
                color: AppColors.accent,
                label: 'Rutinler',
                value: routinePercent == null
                    ? KokpitFormat.none
                    : KokpitFormat.percent(routinePercent),
                caption: routinePercent == null
                    ? 'Planlanan rutin yok'
                    : '${overview.weeklyDone} / ${overview.weeklyPlanned} tamamlandı',
              ),
            ),
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.task_alt_outlined,
                color: AppColors.ops,
                label: 'Görevler',
                value: taskPercent == null
                    ? KokpitFormat.none
                    : KokpitFormat.percent(taskPercent),
                caption: taskPercent == null
                    ? 'Görev yok'
                    : '${overview.tasksDone} / $taskCount tamamlandı',
              ),
            ),
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.directions_walk_outlined,
                color: AppColors.fitness,
                label: 'Ort. adım',
                value: health.avgSteps == null
                    ? KokpitFormat.none
                    : thousands.format(health.avgSteps),
                caption: 'Hedef ${thousands.format(targets.dailySteps)}',
              ),
            ),
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.bedtime_outlined,
                color: AppColors.ops,
                label: 'Ort. uyku',
                value: KokpitFormat.sleep(health.avgSleepMinutes),
                caption: 'Hedef ${KokpitFormat.sleep(targets.sleepMinutes)}',
              ),
            ),
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.local_fire_department_outlined,
                color: AppColors.nutrition,
                label: 'Ort. kalori',
                value: avgCalories == null
                    ? KokpitFormat.none
                    : '${thousands.format(avgCalories.round())} kcal',
                caption:
                    'Hedef ${thousands.format(targets.dailyCalories)} kcal',
              ),
            ),
            BentoCell(
              span: 1,
              child: _MonthStatCard(
                icon: Icons.monitor_weight_outlined,
                color: AppColors.warning,
                label: 'Kilo değişimi',
                value: weightChange == null
                    ? KokpitFormat.none
                    : KokpitFormat.weightChange(weightChange),
                caption: weightChange == null
                    ? 'Ölçüm yok'
                    : '${KokpitFormat.kg(health.weightStartKg!)} → '
                        '${KokpitFormat.kg(health.weightEndKg!)} kg',
              ),
            ),
          ],
        ),
        if (!hasHealth)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Bu ay için sağlık ve beslenme verisi yok.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _MonthStatCard extends StatelessWidget {
  const _MonthStatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: BentoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BentoLabel(icon: icon, label: label, color: color),
            const SizedBox(height: 10),
            // Yarım genişlikte uzun değer satır kırmak yerine küçülür.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                caption,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
