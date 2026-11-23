import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import 'reports_chart.dart';
import 'reports_friends_row.dart';
import 'reports_health.dart';
import 'reports_week_details_screen.dart';
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

/// Haftalık görünüm: hafta seçici, İş/Form puanları + yapay zekâ
/// değerlendirmesi, günlük tamamlama grafiği, haftalık açık + seriler, "Ayrıntılar" bağlantısı ve
/// arkadaşlar satırı.
class ReportsWeeklyView extends ConsumerWidget {
  const ReportsWeeklyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:current, :selected) = reportsWeekSelection(
      ref.watch(kokpitClockProvider),
      ref.watch(reportsWeekProvider),
    );
    final report = ref.watch(weeklyReportProvider(selected));

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
          header: value == null
              ? null
              : ReportScorePair(
                  workRate: value.metrics.workRate,
                  formRate: value.metrics.formRate,
                ),
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
            icon: Icons.cloud_off_outlined,
            message: 'Haftalık rapor yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(weeklyReportProvider(selected)),
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              aiCard(value),
              if (value != null) ...[
                const SizedBox(height: AppSpacing.grid),
                ReportDailyCompletionCard(days: value.metrics.days),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.grid),
        ReportsHealthWeekCard(weekStart: selected),
        const SizedBox(height: AppSpacing.grid),
        ReportLinkRow(
          key: const ValueKey('reports-details'),
          icon: Icons.table_chart_outlined,
          label: 'Ayrıntılar',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReportsWeekDetailsScreen(week: selected),
            ),
          ),
        ),
        const ReportsFriendsRow(),
      ],
    );
  }
}

/// Haftalık ortalamalar ızgarası için değerler (veri yoksa "—").
List<({String label, String value})> weeklyAverages(ReportMetrics m) => [
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
