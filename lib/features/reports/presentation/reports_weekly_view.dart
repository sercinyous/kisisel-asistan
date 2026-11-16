import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import 'reports_chart.dart';
import 'reports_format.dart';
import 'reports_providers.dart';
import 'reports_state.dart';
import 'reports_widgets.dart';

/// İçinde bulunulan hafta ve seçili hafta (gelecek haftaya gidilmez).
({DateTime current, DateTime selected}) reportsWeekSelection(
  DateTime now,
  DateTime? picked,
) {
  final current = AppDates.weekStart(now);
  return (
    current: current,
    selected: picked == null || picked.isAfter(current) ? current : picked,
  );
}

/// Haftalık görünüm: hafta seçici, İş/Form, günlük tamamlama grafiği,
/// ortalamalar, yapay zekâ değerlendirmesi ve geçmiş haftalar.
class ReportsWeeklyView extends ConsumerWidget {
  const ReportsWeeklyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:current, :selected) = reportsWeekSelection(
      ref.watch(kokpitClockProvider),
      ref.watch(reportsWeekProvider),
    );
    final report = ref.watch(weeklyReportProvider(selected));
    final history = ref.watch(weeklyReportListProvider);

    void show(DateTime week) =>
        ref.read(reportsWeekProvider.notifier).state = week;

    Widget aiCard(WeeklyReport? value) => ReportAiCard(
          kind: ReportKind.weekly,
          date: selected,
          title: 'Haftalık değerlendirme',
          emptyMessage: 'Bu hafta için rapor henüz oluşmadı',
          emptyHint: 'Haftalık rapor Pazartesi sabahı otomatik oluşur. '
              'Beklemeden şimdi de oluşturabilirsin.',
          exists: value != null,
          status: value?.aiStatus ?? ReportAiStatus.pending,
          summary: value?.aiSummary,
          generatedAt: value?.generatedAt,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportPeriodSwitcher(
          label: ReportsFormat.weekRange(selected),
          caption: selected == current ? 'Bu hafta' : null,
          previousTooltip: 'Önceki hafta',
          nextTooltip: 'Sonraki hafta',
          onPrevious: () => show(AppDates.addDays(selected, -7)),
          onNext: selected.isBefore(current)
              ? () => show(AppDates.addDays(selected, 7))
              : null,
        ),
        const SizedBox(height: 8),
        report.when(
          loading: () => const KokpitSkeletonCard(height: 320),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Haftalık rapor yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(weeklyReportProvider(selected)),
          ),
          data: (value) => value == null
              ? aiCard(null)
              : _WeeklyReportGrid(report: value, aiCard: aiCard(value)),
        ),
        const SizedBox(height: 24),
        const KokpitSectionHeader(title: 'Geçmiş haftalar'),
        history.when(
          loading: () => const KokpitSkeletonCard(height: 120),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Geçmiş haftalar yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(weeklyReportListProvider),
          ),
          data: (reports) {
            final others = [
              for (final item in reports)
                if (item.weekStart != selected) item,
            ];
            if (others.isEmpty) {
              return const KokpitInlineMessage(
                icon: Icons.history_rounded,
                message: 'Henüz başka haftalık rapor yok.',
              );
            }
            return ReportListCard(
              icon: Icons.insights_rounded,
              entries: [
                for (final item in others)
                  ReportListEntry(
                    key: ValueKey(
                      'reports-week-${AppDates.ymd(item.weekStart)}',
                    ),
                    title: ReportsFormat.weekRange(item.weekStart),
                    subtitle: [
                      'İş ${ReportsFormat.rate(item.metrics.workRate)}',
                      'Form ${ReportsFormat.rate(item.metrics.formRate)}',
                      if (item.metrics.weightChangeKg case final change?)
                        KokpitFormat.weightChange(change),
                    ].join(' · '),
                    onTap: () => show(item.weekStart),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WeeklyReportGrid extends StatelessWidget {
  const _WeeklyReportGrid({required this.report, required this.aiCard});

  final WeeklyReport report;
  final Widget aiCard;

  @override
  Widget build(BuildContext context) {
    final m = report.metrics;
    return BentoGrid(
      children: [
        BentoCell(
          span: 1,
          child: ReportRateCard(
            icon: Icons.task_alt_rounded,
            label: 'İş',
            color: AppColors.ops,
            rate: m.workRate,
            caption: 'Görev ${m.tasksDone} / ${m.tasksTotal} · '
                'Rutin ${ReportsFormat.rate(m.routineRate)}',
          ),
        ),
        BentoCell(
          span: 1,
          child: ReportRateCard(
            icon: Icons.fitness_center_rounded,
            label: 'Form',
            color: AppColors.fitness,
            rate: m.formRate,
            caption: 'Antrenman ${m.workoutsDone} / ${m.workoutsPlanned} · '
                'Protein ${m.proteinDaysHit} gün',
          ),
        ),
        BentoCell(child: ReportDailyCompletionCard(days: m.days)),
        BentoCell(
          child: BentoCard(
            child: ReportStatGrid(
              stats: [
                for (final stat in _weeklyAverages(m))
                  ReportStat(label: stat.label, value: stat.value),
              ],
            ),
          ),
        ),
        BentoCell(child: aiCard),
      ],
    );
  }
}

/// Haftalık ortalamalar ızgarası için değerler (veri yoksa "—").
List<({String label, String value})> _weeklyAverages(ReportMetrics m) => [
      (
        label: 'Ort. kalori',
        value: m.hasNutrition
            ? ReportsFormat.count(m.calories)
            : ReportsFormat.none,
      ),
      (
        label: 'Ort. protein',
        value: m.hasNutrition
            ? '${ReportsFormat.count(m.proteinG)} g'
            : ReportsFormat.none,
      ),
      (
        label: 'Kilo',
        value: m.weightChangeKg == null
            ? ReportsFormat.none
            : KokpitFormat.weightChange(m.weightChangeKg!),
      ),
      (
        label: 'Ort. adım',
        value: m.hasHealth ? ReportsFormat.count(m.steps) : ReportsFormat.none,
      ),
      (
        label: 'Ort. uyku',
        value: m.hasHealth
            ? ReportsFormat.sleepShort(m.sleepMinutes)
            : ReportsFormat.none,
      ),
      (
        label: 'Aktif kalori',
        value: m.hasHealth && m.activeKcal > 0
            ? ReportsFormat.count(m.activeKcal)
            : ReportsFormat.none,
      ),
    ];
