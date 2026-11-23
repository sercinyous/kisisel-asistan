import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/bento.dart';
import '../providers/streaks_providers.dart';
import '../providers/week_deficit_providers.dart';
import '../streak_detail_screen.dart';
import 'today_common.dart';

IconData streakIcon(StreakKind kind) => switch (kind) {
      StreakKind.steps => Icons.directions_walk_rounded,
      StreakKind.logging => Icons.edit_note_rounded,
      StreakKind.deficit => Icons.local_fire_department_rounded,
      StreakKind.target => Icons.track_changes_rounded,
    };

Color streakColor(StreakKind kind) => switch (kind) {
      StreakKind.steps => AppColors.ops,
      StreakKind.logging => AppColors.nutrition,
      StreakKind.deficit => AppColors.accent,
      StreakKind.target => AppColors.accent,
    };

/// Bugün'ün başındaki seriler şeridi: Adım (kaynak varsa), Kayıt, Açık ve
/// Hafta. Dokununca [StreakDetailScreen] açılır.
class StreakStrip extends ConsumerWidget {
  const StreakStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider).valueOrNull;
    final week = ref.watch(currentWeekDeficitProvider).valueOrNull;
    final chips = <Widget>[
      if (streaks != null)
        for (final s in streaks.streaks) _StreakChip(status: s),
      if (week != null) _WeekChip(week: week),
    ];
    return BentoCard(
      key: const Key('streak-strip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      onTap: () => StreakDetailScreen.open(context),
      child: chips.isEmpty
          ? SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  'Seriler hesaplanıyor…',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 12,
                        thickness: 0.5,
                        color: AppColors.border,
                      ),
                    Expanded(
                        flex: i == chips.length - 1 ? 2 : 1, child: chips[i]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.status});

  final StreakStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = status.today == StreakToday.done;
    final color = streakColor(status.kind);
    return Semantics(
      label: '${status.semantics}, '
          '${done ? 'bugün tamam' : 'bugün bekleniyor'}',
      excludeSemantics: true,
      child: Column(
        key: Key('streak-chip-${status.kind.name}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(streakIcon(status.kind), size: 16, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  status.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${status.current} gün',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (done)
                Icon(Icons.check_rounded, size: 14, color: color)
              else
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  done ? 'bugün' : 'bekleniyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({required this.week});

  final WeekDeficit week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = week.totalKcal;
    final value = '${TodayFormat.weekTotal(week)} ${TodayFormat.weekKg(week)}';
    final target = week.targetKcal > 0
        ? TodayFormat.weekTarget(week.targetKcal, surplus: week.surplusGoal)
        : null;
    return Semantics(
      label: 'Haftalık ${TodayFormat.weekTitle(week)} $value'
          '${target == null ? '' : ', $target'}',
      excludeSemantics: true,
      child: Column(
        key: const Key('streak-chip-week'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_week_rounded,
                  size: 16, color: AppColors.fitness),
              const SizedBox(width: 4),
              Text(
                'Hafta',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              TodayFormat.weekTotal(week),
              key: const Key('streak-week-total'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: week.hasData && total < 0 && !week.surplusGoal
                    ? AppColors.warning
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              [TodayFormat.weekKg(week), if (target != null) target]
                  .join(' · '),
              key: const Key('streak-week-sub'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
