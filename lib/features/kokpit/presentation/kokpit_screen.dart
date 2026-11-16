import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../health/presentation/health_providers.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import 'kokpit_day_view.dart';
import 'kokpit_month_view.dart';
import 'kokpit_providers.dart';

/// Kokpit: **Gün** (bugünün özeti, rutinler, yaklaşanlar) ve **Ay** (takvim,
/// aylık sabitler, ay özeti) görünümleri.
class KokpitScreen extends ConsumerWidget {
  const KokpitScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    final view = ref.read(kokpitViewProvider);
    ref.read(kokpitClockProvider.notifier).state = DateTime.now();
    ref.invalidate(todayOccurrencesProvider);
    ref.invalidate(upcomingRemindersProvider);
    ref.invalidate(todayNutritionProvider);
    ref.invalidate(monthOverviewProvider);
    // HealthKit yeniden okunup yedeklenir; bitince 7 günlük adım grafiği ve
    // Ay ortalamaları da tazelenir.
    unawaited(
      resyncHealthKit(ProviderScope.containerOf(ref.context, listen: false)),
    );
    // Hatalar kartların kendi hata durumunda gösterilir; burada yutulur.
    Future<void> settle(Future<Object?> future) async {
      try {
        await future;
      } catch (_) {}
    }

    // Yalnızca açık görünümün verisi beklenir; diğeri açıldığında yüklenir.
    await Future.wait<void>(switch (view) {
      KokpitView.day => [
          settle(ref.read(todayOccurrencesProvider.future)),
          settle(ref.read(upcomingRemindersProvider.future)),
          settle(ref.read(todayNutritionProvider.future)),
        ],
      KokpitView.month => [
          settle(
            ref.read(
              monthOverviewProvider(ref.read(kokpitMonthProvider)).future,
            ),
          ),
        ],
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(kokpitClockProvider);
    final view = ref.watch(kokpitViewProvider);
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppDates.upperTr(AppDates.longDay(now)),
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppDates.greeting(now),
                        style: theme.textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                  tooltip: 'Ayarlar',
                  icon: const Icon(Icons.settings_outlined),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<KokpitView>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: KokpitView.day,
                  label: Text('Gün'),
                  icon: Icon(Icons.today_rounded),
                ),
                ButtonSegment(
                  value: KokpitView.month,
                  label: Text('Ay'),
                  icon: Icon(Icons.calendar_month_rounded),
                ),
              ],
              selected: {view},
              onSelectionChanged: (selection) => ref
                  .read(kokpitViewProvider.notifier)
                  .state = selection.first,
              style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textSecondary,
                selectedBackgroundColor: AppColors.surfaceHigh,
                selectedForegroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.inner),
                ),
              ),
            ),
            const SizedBox(height: 16),
            switch (view) {
              KokpitView.day => const KokpitDayView(),
              KokpitView.month => const KokpitMonthView(),
            },
          ],
        ),
      ),
    );
  }
}
