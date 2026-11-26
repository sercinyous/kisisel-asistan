import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import 'reports_format.dart';
import 'reports_providers.dart';
import 'reports_state.dart';
import 'reports_widgets.dart';

/// Bugün ve seçili gün (geleceğe gidilmez).
({DateTime today, DateTime selected}) reportsDaySelection(
  DateTime now,
  DateTime? picked,
) {
  final today = AppDates.startOfDay(now);
  return (
    today: today,
    selected: picked == null || picked.isAfter(today) ? today : picked,
  );
}

/// Günlük görünüm: gün seçici, İş/Form, hedefleriyle beslenme ve sağlık
/// sayıları, yapay zekâ değerlendirmesi ve son 7 gün.
class ReportsDailyView extends ConsumerWidget {
  const ReportsDailyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:today, :selected) = reportsDaySelection(
      ref.watch(kokpitClockProvider),
      ref.watch(reportsDayProvider),
    );
    final report = ref.watch(dailyReportProvider(selected));
    final recent = ref.watch(dailyReportListProvider(lastSevenDays(today)));

    void show(DateTime day) =>
        ref.read(reportsDayProvider.notifier).state = day;

    Widget aiCard(DailyReport? value) => ReportAiCard(
          kind: ReportKind.daily,
          date: selected,
          title: 'Günlük değerlendirme',
          emptyMessage: 'Bu gün için rapor henüz oluşmadı',
          emptyHint: 'Günlük rapor gece yarısından sonra (00:15) biten gün için otomatik oluşur. '
              'Beklemeden şimdi de oluşturabilirsin.',
          exists: value != null,
          status: value?.aiStatus ?? ReportAiStatus.pending,
          summary: value?.aiSummary,
          generatedAt: value?.generatedAt,
        );

    final String? caption;
    if (selected == today) {
      caption = 'Bugün';
    } else if (selected == AppDates.addDays(today, -1)) {
      caption = 'Dün';
    } else {
      caption = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportPeriodSwitcher(
          label: AppDates.longDay(selected),
          caption: caption,
          previousTooltip: 'Önceki gün',
          nextTooltip: 'Sonraki gün',
          onPrevious: () => show(AppDates.addDays(selected, -1)),
          onNext: selected.isBefore(today)
              ? () => show(AppDates.addDays(selected, 1))
              : null,
        ),
        const SizedBox(height: 8),
        report.when(
          loading: () => const KokpitSkeletonCard(height: 320),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Günlük rapor yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(dailyReportProvider(selected)),
          ),
          data: (value) => value == null
              ? aiCard(null)
              : _DailyReportGrid(report: value, aiCard: aiCard(value)),
        ),
        const SizedBox(height: AppSpacing.grid),
        recent.when(
          loading: () => const KokpitSkeletonCard(height: 120),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Son günlerin raporları yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(dailyReportListProvider),
          ),
          data: (reports) {
            final others = [
              for (final item in reports)
                if (item.reportDate != selected) item,
            ];
            if (others.isEmpty) {
              return const KokpitInlineMessage(
                icon: Icons.history_outlined,
                message: 'Son 7 günde başka rapor yok.',
              );
            }
            return ReportListCard(
              icon: Icons.today_outlined,
              title: 'Son 7 gün',
              entries: [
                for (final item in others)
                  ReportListEntry(
                    key: ValueKey(
                      'reports-day-${AppDates.ymd(item.reportDate)}',
                    ),
                    title: ReportsFormat.dayShort(item.reportDate),
                    subtitle: [
                      'İş ${ReportsFormat.rate(item.metrics.workRate)}',
                      'Form ${ReportsFormat.rate(item.metrics.formRate)}',
                      if (item.metrics.hasHealth && item.metrics.steps > 0)
                        '${ReportsFormat.count(item.metrics.steps)} adım',
                    ].join(' · '),
                    onTap: () => show(item.reportDate),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DailyReportGrid extends StatelessWidget {
  const _DailyReportGrid({required this.report, required this.aiCard});

  final DailyReport report;
  final Widget aiCard;

  /// Hedef yoksa (ya da 0 ise) çubuk çizilmez.
  static double? _progress(num value, int? target) =>
      target == null || target <= 0 ? null : value / target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = report.metrics;
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

    final String proteinNote;
    if (!m.hasNutrition) {
      proteinNote = 'Öğün kaydı yok';
    } else if (m.proteinDaysHit > 0) {
      proteinNote = 'Protein tuttu';
    } else {
      proteinNote = 'Protein eksik';
    }

    return BentoGrid(
      children: [
        BentoCell(
          span: 1,
          child: ReportRateCard(
            icon: Icons.task_alt_outlined,
            label: 'İş',
            color: AppColors.accent,
            rate: m.workRate,
            caption: 'Görev ${m.tasksDone} / ${m.tasksTotal} · '
                'Rutin ${m.routinesDone} / ${m.routinesPlanned}',
          ),
        ),
        BentoCell(
          span: 1,
          child: ReportRateCard(
            icon: Icons.fitness_center_outlined,
            label: 'Form',
            color: AppColors.sleep,
            rate: m.formRate,
            caption: 'Antrenman ${m.workoutsDone} / ${m.workoutsPlanned} · '
                '$proteinNote',
          ),
        ),
        BentoCell(
          child: BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BentoLabel(
                  icon: Icons.restaurant_outlined,
                  label: 'Beslenme',
                  color: AppColors.nutrition,
                ),
                const SizedBox(height: 12),
                if (!m.hasNutrition)
                  Text('Bu gün için öğün kaydı yok.', style: muted)
                else ...[
                  ReportTargetRow(
                    label: 'Kalori',
                    value: ReportsFormat.count(m.calories),
                    target: m.targetCalories == null
                        ? 'kcal'
                        : '/ ${ReportsFormat.count(m.targetCalories!)} kcal',
                    progress: _progress(m.calories, m.targetCalories),
                    color: AppColors.nutrition,
                  ),
                  const SizedBox(height: 12),
                  ReportTargetRow(
                    label: 'Protein',
                    value: '${ReportsFormat.count(m.proteinG)} g',
                    target: m.targetProteinG == null
                        ? null
                        : '/ ${ReportsFormat.count(m.targetProteinG!)} g',
                    progress: _progress(m.proteinG, m.targetProteinG),
                    color: AppColors.nutrition,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Karbonhidrat ${ReportsFormat.count(m.carbsG)} g · '
                    'Yağ ${ReportsFormat.count(m.fatG)} g',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
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
                  icon: Icons.favorite_rounded,
                  label: 'Sağlık',
                  color: AppColors.accent,
                ),
                const SizedBox(height: 12),
                if (!m.hasHealth)
                  Text('Bu gün için sağlık verisi yok.', style: muted)
                else ...[
                  ReportTargetRow(
                    label: 'Adım',
                    value: ReportsFormat.count(m.steps),
                    target: m.targetSteps == null
                        ? null
                        : '/ ${ReportsFormat.count(m.targetSteps!)}',
                    progress: _progress(m.steps, m.targetSteps),
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  ReportTargetRow(
                    label: 'Uyku',
                    value: ReportsFormat.sleepShort(m.sleepMinutes),
                    target: m.targetSleepMinutes == null
                        ? null
                        : '/ ${ReportsFormat.sleepShort(m.targetSleepMinutes!)}',
                    progress: _progress(m.sleepMinutes, m.targetSleepMinutes),
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  ReportTargetRow(
                    label: 'Aktif kalori',
                    value: m.activeKcal > 0
                        ? ReportsFormat.count(m.activeKcal)
                        : ReportsFormat.none,
                    target: 'kcal',
                    color: AppColors.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
        BentoCell(child: aiCard),
      ],
    );
  }
}
