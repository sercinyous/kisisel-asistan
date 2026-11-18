import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import 'reports_daily_view.dart';
import 'reports_providers.dart';
import 'reports_state.dart';
import 'reports_weekly_view.dart';
import 'weekly_checkin_card.dart';

/// Raporlar: sunucuda otomatik üretilen **haftalık** ve **günlük** raporlar.
/// Sayılar rapordan gösterilir; uygulamada yeniden hesaplanmaz.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    // Gün değişmiş olabilir: "bugün" ve "bu hafta" güncel saate göre olsun.
    ref.read(kokpitClockProvider.notifier).state = DateTime.now();
    ref
      ..invalidate(weeklyReportProvider)
      ..invalidate(weeklyReportListProvider)
      ..invalidate(dailyReportProvider)
      ..invalidate(dailyReportListProvider);
    // Hatalar bölümlerin kendi hata durumunda gösterilir; burada yutulur.
    Future<void> settle(Future<Object?> future) async {
      try {
        await future;
      } catch (_) {}
    }

    final now = ref.read(kokpitClockProvider);
    // Yalnızca açık görünümün verisi beklenir.
    await Future.wait<void>(switch (ref.read(reportsViewProvider)) {
      ReportsView.weekly => [
          settle(
            ref.read(
              weeklyReportProvider(reportsWeekSelection(now, ref.read(reportsWeekProvider))
                  .selected).future,
            ),
          ),
          settle(ref.read(weeklyReportListProvider.future)),
        ],
      ReportsView.daily => [
          settle(
            ref.read(
              dailyReportProvider(reportsDaySelection(now, ref.read(reportsDayProvider))
                  .selected).future,
            ),
          ),
        ],
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(reportsViewProvider);
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surfaceHigh,
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            12,
            AppSpacing.page,
            120,
          ),
          children: [
            Text('Raporlar', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            SegmentedButton<ReportsView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ReportsView.weekly,
                  label: Text('Haftalık'),
                  icon: Icon(Icons.date_range_rounded),
                ),
                ButtonSegment(
                  value: ReportsView.daily,
                  label: Text('Günlük'),
                  icon: Icon(Icons.today_rounded),
                ),
              ],
              selected: {view},
              onSelectionChanged: (selection) => ref
                  .read(reportsViewProvider.notifier)
                  .state = selection.first,
              style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textSecondary,
                selectedBackgroundColor: AppColors.surfaceHigh,
                selectedForegroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.inner),
                ),
              ),
            ),
            const SizedBox(height: 12),
            switch (view) {
              ReportsView.weekly => const ReportsWeeklyView(),
              ReportsView.daily => const ReportsDailyView(),
            },
            const SizedBox(height: 16),
            const WeeklyCheckinCard(bottomSpacing: 0),
          ],
        ),
      ),
    );
  }
}
