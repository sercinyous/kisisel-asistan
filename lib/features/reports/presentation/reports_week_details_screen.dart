import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../operations/presentation/dashboard/task_dashboard_view.dart';
import 'reports_format.dart';
import 'reports_providers.dart';
import 'reports_state.dart';
import 'reports_weekly_view.dart';
import 'reports_widgets.dart';

/// Haftanın ayrıntıları: sayı tablosu, geçmiş haftalar ve iş ayrıntısı
/// (görev panosu).
class ReportsWeekDetailsScreen extends ConsumerWidget {
  const ReportsWeekDetailsScreen({super.key, required this.week});

  /// Haftanın Pazartesi'si.
  final DateTime week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(weeklyReportProvider(week));
    final history = ref.watch(weeklyReportListProvider);

    void open(DateTime other) {
      ref.read(reportsWeekProvider.notifier).state = other;
      Navigator.of(context).pop();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ayrıntılar'),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          8,
          AppSpacing.page,
          120,
        ),
        children: [
          Text(
            ReportsFormat.weekRange(week),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          report.when(
            loading: () => const KokpitSkeletonCard(height: 240),
            error: (_, __) => KokpitInlineMessage(
              icon: Icons.cloud_off_outlined,
              message: 'Haftalık rapor yüklenemedi.',
              actionLabel: 'Tekrar dene',
              onAction: () => ref.invalidate(weeklyReportProvider(week)),
            ),
            data: (value) => value == null
                ? const KokpitInlineMessage(
                    icon: Icons.insights_outlined,
                    message: 'Bu hafta için rapor henüz oluşmadı.',
                  )
                : _NumbersGrid(metrics: value.metrics),
          ),
          const SizedBox(height: AppSpacing.grid),
          history.when(
            loading: () => const KokpitSkeletonCard(height: 120),
            error: (_, __) => KokpitInlineMessage(
              icon: Icons.cloud_off_outlined,
              message: 'Geçmiş haftalar yüklenemedi.',
              actionLabel: 'Tekrar dene',
              onAction: () => ref.invalidate(weeklyReportListProvider),
            ),
            data: (reports) {
              final others = [
                for (final item in reports)
                  if (item.weekStart != week) item,
              ];
              if (others.isEmpty) {
                return const KokpitInlineMessage(
                  icon: Icons.history_outlined,
                  message: 'Henüz başka haftalık rapor yok.',
                );
              }
              return ReportListCard(
                icon: Icons.insights_outlined,
                title: 'Geçmiş haftalar',
                entries: [
                  for (final item in others)
                    ReportListEntry(
                      key: ValueKey(
                        'reports-week-${AppDates.ymd(item.weekStart)}',
                      ),
                      title: ReportsFormat.weekRange(item.weekStart),
                      subtitle: [
                        'İş ${ReportsFormat.rate(item.metrics.workRate)}',
                        'Sağlık ${ReportsFormat.rate(item.metrics.formRate)}',
                        if (item.metrics.weightChangeKg case final change?)
                          KokpitFormat.weightChange(change),
                      ].join(' · '),
                      onTap: () => open(item.weekStart),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const KokpitSectionHeader(title: 'İş ayrıntısı'),
          const TaskDashboardSection(),
        ],
      ),
    );
  }
}

class _NumbersGrid extends StatelessWidget {
  const _NumbersGrid({required this.metrics});

  final ReportMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
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
                'Rutin ${ReportsFormat.rate(m.routineRate)}',
          ),
        ),
        BentoCell(
          span: 1,
          child: ReportRateCard(
            icon: Icons.fitness_center_outlined,
            label: 'Sağlık',
            color: AppColors.sleep,
            rate: m.formRate,
            caption: 'Antrenman ${m.workoutsDone} / ${m.workoutsPlanned} · '
                'Protein ${m.proteinDaysHit} gün',
          ),
        ),
        BentoCell(
          child: BentoCard(
            child: ReportStatGrid(
              stats: [
                for (final stat in weeklyAverages(m))
                  ReportStat(label: stat.label, value: stat.value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
