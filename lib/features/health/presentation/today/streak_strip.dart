import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ritim_ui.dart';
import '../providers/streaks_providers.dart';
import '../providers/week_deficit_providers.dart';
import '../streak_detail_screen.dart';
import 'today_common.dart';

Color streakColor(StreakKind kind) => switch (kind) {
      StreakKind.steps => AppColors.ops,
      StreakKind.logging => AppColors.nutrition,
      StreakKind.deficit => AppColors.accent,
      StreakKind.target => AppColors.accent,
    };

/// Bugün'ün başındaki seriler kartı: Adım (kaynak varsa), Kayıt, Açık ve
/// Hafta 2x2 ızgarada. Dokununca [StreakDetailScreen] açılır.
class StreakStrip extends ConsumerWidget {
  const StreakStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider).valueOrNull;
    final week = ref.watch(currentWeekDeficitProvider).valueOrNull;
    final chips = <Widget>[
      if (streaks != null)
        for (final s in streaks.streaks) _streakChip(s),
      if (week != null) _weekChip(week),
    ];
    return RitimSectionCard(
      key: const Key('streak-strip'),
      title: 'Seriler',
      trailing: 'Detay ›',
      onTap: () => StreakDetailScreen.open(context),
      onTrailingTap: () => StreakDetailScreen.open(context),
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
          : RitimChipGrid(children: chips),
    );
  }
}

Widget _streakChip(StreakStatus status) {
  final done = status.today == StreakToday.done;
  return Semantics(
    key: Key('streak-chip-${status.kind.name}'),
    label: '${status.semantics}, '
        '${done ? 'bugün tamam' : 'bugün bekleniyor'}',
    excludeSemantics: true,
    child: RitimChipTile(
      label: status.kind.label,
      value: '${status.current} gün',
      status: done ? '✓ bugün tamam' : '• bugün bekleniyor',
      statusColor: done ? AppColors.positive : null,
    ),
  );
}

Widget _weekChip(WeekDeficit week) {
  final total = week.totalKcal;
  final target = week.targetKcal > 0
      ? TodayFormat.weekTarget(week.targetKcal, surplus: week.surplusGoal)
      : null;
  final sub =
      [TodayFormat.weekKg(week), if (target != null) target].join(' · ');
  return Semantics(
    key: const Key('streak-chip-week'),
    label: 'Haftalık ${TodayFormat.weekTitle(week)} '
        '${TodayFormat.weekTotal(week)} $sub',
    excludeSemantics: true,
    child: RitimChipTile(
      label: 'Hafta',
      value: TodayFormat.weekTotal(week),
      valueColor: week.hasData && total < 0 && !week.surplusGoal
          ? AppColors.warning
          : null,
      status: sub,
    ),
  );
}
