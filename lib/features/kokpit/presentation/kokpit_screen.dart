import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../friends/presentation/friends_button.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/water_providers.dart';
import '../../routines/presentation/routines_providers.dart';
import 'kokpit_day_view.dart';
import 'kokpit_providers.dart';

/// Kokpit ("Bugün"): kalori, günlük işler/adım/uyku, su ve bugünün rutinleri.
class KokpitScreen extends ConsumerWidget {
  const KokpitScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(kokpitClockProvider.notifier).state = DateTime.now();
    ref.invalidate(todayOccurrencesProvider);
    ref.invalidate(upcomingRemindersProvider);
    ref.invalidate(todayNutritionProvider);
    ref.invalidate(waterTodayProvider);
    // HealthKit yeniden okunup yedeklenir.
    unawaited(
      resyncHealthKit(ProviderScope.containerOf(ref.context, listen: false)),
    );
    // Hatalar kartların kendi hata durumunda gösterilir; burada yutulur.
    Future<void> settle(Future<Object?> future) async {
      try {
        await future;
      } catch (_) {}
    }

    await Future.wait<void>([
      settle(ref.read(todayOccurrencesProvider.future)),
      settle(ref.read(upcomingRemindersProvider.future)),
      settle(ref.read(todayNutritionProvider.future)),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(kokpitClockProvider);
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
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        AppDates.greeting(now),
                        style: theme.textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
                const FriendsButton(),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            const KokpitDayView(),
          ],
        ),
      ),
    );
  }
}
