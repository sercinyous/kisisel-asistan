import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/sunset_stripe.dart';
import '../../friends/presentation/friends_button.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/providers/body_providers.dart';
import '../../health/presentation/water_providers.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../../core/services/health_service.dart';
import '../../stories/presentation/stories_providers.dart';
import '../../stories/presentation/stories_row.dart';
import 'kokpit_day_view.dart';
import 'kokpit_format.dart';
import 'kokpit_motion.dart';
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
    ref.invalidate(checkinTodayProvider);
    ref.invalidate(friendStoryGroupsProvider);
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
            KokpitEntrance(index: 0, child: KokpitGreetingCard(now: now)),
            const SizedBox(height: AppSpacing.grid),
            const StoriesRow(),
            const SizedBox(height: AppSpacing.grid),
            const KokpitDayView(),
          ],
        ),
      ),
    );
  }
}

/// Ekranın tepesindeki selamlama ve gün durumu kartı. Zemini günün
/// bölümüne (sabah/öğle/akşam/gece) göre pastel bir geçişle boyanır.
class KokpitGreetingCard extends ConsumerWidget {
  const KokpitGreetingCard({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = KokpitDayPhase.of(now);
    final items = watchKokpitTodayItems(ref)
        ?.where((i) => i is! KokpitCheckinItem)
        .toList();
    final left = items?.where((i) => !i.done).length;
    final health = ref.watch(healthTodayProvider).valueOrNull;
    final sleep = health?.status == HealthStatus.ok && health!.sleepMinutes > 0
        ? health.sleepMinutes
        : null;

    return BentoCard(
      key: const ValueKey('kokpit-greeting'),
      gradient: phase.gradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SunsetStripe(key: ValueKey('kokpit-greeting-sunset')),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppDates.upperTr(AppDates.longDay(now)),
                      style: TextStyle(
                        fontSize: AppType.caption,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppDates.greeting(now),
                      style: TextStyle(
                        fontSize: AppType.screenTitle,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const FriendsButton(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _StatusChip(
                icon: phase.icon,
                color: phase.color,
                label: phase.label,
              ),
              if (left != null && items!.isNotEmpty)
                _StatusChip(
                  key: const ValueKey('kokpit-greeting-tasks'),
                  icon: left == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.checklist_rounded,
                  color: AppColors.ops,
                  label: left == 0 ? 'Bugünün işleri bitti' : 'Açık iş: $left',
                ),
              if (sleep != null)
                _StatusChip(
                  icon: Icons.bedtime_outlined,
                  color: AppColors.sleep,
                  label: 'Uyku ${KokpitFormat.sleep(sleep)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
