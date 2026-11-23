import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/health_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/bento.dart';
import '../../../kokpit/presentation/kokpit_format.dart';
import '../../../kokpit/presentation/kokpit_providers.dart';
import '../health_format.dart';
import '../health_providers.dart';
import '../providers/targets_providers.dart';
import '../weekly_detail_screen.dart';
import '../workout_form_sheet.dart';
import 'today_common.dart';

/// Hareket 2×2: Adım, Uyku, Antrenman ve Haftalık detay. Her kutu Haftalık
/// detayı kendi ölçüsüyle açar.
class MovementTiles extends ConsumerWidget {
  const MovementTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(healthTodayProvider).valueOrNull;
    final ok = snapshot != null && snapshot.status == HealthStatus.ok;
    final targets = ref.watch(targetsProvider);
    final week = ref.watch(weekWorkoutPlanProvider).valueOrNull;
    final steps = ok ? snapshot.steps : null;
    final sleep =
        ok && snapshot.sleepMinutes > 0 ? snapshot.sleepMinutes : null;

    return BentoGrid(children: [
      BentoCell(
        span: 1,
        child: _Tile(
          key: const Key('move-steps'),
          icon: Icons.directions_walk_rounded,
          label: 'Adım',
          color: AppColors.ops,
          value: steps == null ? '—' : HealthFormat.count(steps),
          sub: 'hedef ${HealthFormat.count(targets.steps)}',
          progress: steps == null || targets.steps <= 0
              ? null
              : steps / targets.steps,
          onTap: () =>
              WeeklyDetailScreen.open(context, metric: WeeklyMetric.steps),
        ),
      ),
      BentoCell(
        span: 1,
        child: _Tile(
          key: const Key('move-sleep'),
          icon: Icons.bedtime_rounded,
          label: 'Uyku',
          color: AppColors.sleep,
          value: sleep == null ? '—' : KokpitFormat.sleep(sleep),
          sub: 'dün gece',
          progress: sleep == null || targets.sleepMinutes <= 0
              ? null
              : sleep / targets.sleepMinutes,
          onTap: () =>
              WeeklyDetailScreen.open(context, metric: WeeklyMetric.sleep),
        ),
      ),
      BentoCell(
        span: 1,
        child: _Tile(
          key: const Key('move-workouts'),
          icon: Icons.fitness_center_rounded,
          label: 'Antrenman',
          color: AppColors.fitness,
          value: week == null
              ? '—'
              : week.plannedCount > 0
                  ? '${week.doneCount} / ${week.plannedCount}'
                  : '${week.doneCount}',
          sub: 'bu hafta',
          onTap: () =>
              WeeklyDetailScreen.open(context, metric: WeeklyMetric.workouts),
          action: TextButton.icon(
            key: const Key('move-workout-add'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => WorkoutFormSheet.show(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ekle'),
          ),
        ),
      ),
      BentoCell(
        span: 1,
        child: _Tile(
          key: const Key('move-weekly'),
          icon: Icons.insights_rounded,
          label: 'Haftalık detay',
          color: AppColors.accent,
          value: '7 · 30 · 90',
          sub: 'gün grafikleri',
          onTap: () => WeeklyDetailScreen.open(context),
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.sub,
    required this.onTap,
    this.progress,
    this.action,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String value;
  final String sub;
  final VoidCallback onTap;
  final double? progress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = this.progress;
    return BentoCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(icon: icon, label: label, color: color),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            SlimBar(progress: progress, color: color),
          ],
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ],
      ),
    );
  }
}
