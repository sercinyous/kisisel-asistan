import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../trend_providers.dart' show trendClockProvider;
import 'targets_providers.dart';
import 'week_deficit_providers.dart';

export '../../domain/streaks.dart';

/// Serilerin geriye baktığı gün sayısı.
const int streakLookbackDays = 120;

/// Üç seri, düşük alım uyarısı.
class StreaksState {
  const StreaksState({required this.streaks, required this.lowIntake});

  /// Adım (sağlık kaynağı yoksa listede yok), Kayıt, Açık.
  final List<StreakStatus> streaks;

  /// "Son 3 gün çok az yedin".
  final bool lowIntake;

  StreakStatus? of(StreakKind kind) {
    for (final s in streaks) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  /// Kokpit satırı: "Adım 7 · Kayıt 12 · Açık 4".
  String get line =>
      streaks.map((s) => '${s.kind.label} ${s.current}').join(' · ');
}

/// Son [streakLookbackDays] günün serileri; ham veriden türetilir.
final streaksProvider = FutureProvider<StreaksState>((ref) async {
  final now = ref.watch(trendClockProvider)();
  final today = AppDates.startOfDay(now);
  final health = await ref.watch(healthDaysProvider((
    from: AppDates.addDays(today, -(streakLookbackDays - 1)),
    to: today,
  )).future);
  final settings = await ref.watch(userSettingsProvider.future);
  final resolved = await ref.watch(resolvedTargetsProvider.future);
  final targets = StreakTargets(
    dailySteps: settings.dailySteps,
    kcalTarget: settings.dailyCalories,
    floorKcal: resolved.floorKcal,
    plannedDeficit: resolved.deficit,
  );
  return StreaksState(
    streaks: computeStreaks(
      days: health.days,
      targets: targets,
      today: today,
      includeSteps: health.hasSteps,
    ),
    lowIntake: lowIntakeWarning(
      days: health.days,
      floorKcal: resolved.floorKcal,
      today: today,
    ),
  );
});
