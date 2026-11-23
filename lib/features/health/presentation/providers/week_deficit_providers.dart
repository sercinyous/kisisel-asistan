import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/health_source.dart' show healthSourceProvider;
import '../../../../core/utils/date_utils.dart';
import '../../../settings/domain/user_settings.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../data/health_repository.dart';
import '../../domain/energy_balance.dart';
import '../../domain/streaks.dart';
import '../energy_providers.dart' show EnergyWindow, energyWeightLookbackDays;
import '../trend_providers.dart' show trendClockProvider;
import 'targets_providers.dart';

export '../../domain/streaks.dart';

/// Bir aralığın günlük ham verisi ve o güne göre harcama (tek model:
/// [dayExpenditure]). Gün dengesi, haftalık açık ve seriler bunu okur.
class HealthDays {
  const HealthDays({required this.days, required this.hasSteps});

  /// Eskiden yeniye, aralığın her günü (bugünde biter).
  final List<StreakDay> days;

  /// Aralıkta sağlık kaynağından adım geldi mi (Adım serisi gösterilir).
  final bool hasSteps;
}

/// [EnergyWindow] aralığının günleri. Kilo, o günün sonuna kadarki son tartı
/// (yoksa başlangıç kilosu); bazal profil eksikse yoktur (harcama da yok,
/// elle girilmediyse).
final healthDaysProvider =
    FutureProvider.family<HealthDays, EnergyWindow>((ref, window) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final now = ref.watch(trendClockProvider)();
  final today = AppDates.startOfDay(now);
  final first = AppDates.startOfDay(window.from);
  final requested = AppDates.startOfDay(window.to);
  final last = requested.isAfter(today) ? today : requested;
  if (first.isAfter(last)) return const HealthDays(days: [], hasSteps: false);

  final repository = ref.watch(healthRepositoryProvider);
  final metricsRead = repository.fetchDailyMetrics(first, last,
      source: ref.watch(healthSourceProvider));
  final nutritionRead =
      repository.fetchNutritionTotals(first, AppDates.endOfDay(last));
  final weightsRead = repository.fetchWeights(
    AppDates.addDays(first, -energyWeightLookbackDays),
    AppDates.endOfDay(last),
  );
  await Future.wait<Object>([metricsRead, nutritionRead, weightsRead]);
  final metrics = {
    for (final m in await metricsRead) AppDates.startOfDay(m.day): m,
  };
  final nutrition = {
    for (final n in await nutritionRead) AppDates.startOfDay(n.day): n,
  };
  final weights = [...await weightsRead]
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  return HealthDays(
    hasSteps: metrics.values.any((m) => m.steps > 0),
    days: buildHealthDays(
      settings: settings,
      first: first,
      last: last,
      now: now,
      metrics: metrics,
      nutrition: nutrition,
      weights: weights,
    ),
  );
});

/// [healthDaysProvider]'ın saf çekirdeği.
List<StreakDay> buildHealthDays({
  required UserSettings settings,
  required DateTime first,
  required DateTime last,
  required DateTime now,
  required Map<DateTime, DailyHealthMetric> metrics,
  required Map<DateTime, DailyNutritionTotal> nutrition,
  required List<WeightEntry> weights,
}) {
  final sex = Sex.tryParse(settings.sex);
  double weightOn(DateTime day) {
    final end = AppDates.endOfDay(day);
    var kg = settings.startWeightKg;
    for (final w in weights) {
      if (!w.loggedAt.isBefore(end)) break;
      kg = w.weightKg;
    }
    return kg;
  }

  return [
    for (var day = first; !day.isAfter(last); day = AppDates.addDays(day, 1))
      () {
        final m = metrics[day];
        final n = nutrition[day];
        final basal = settingsBasal(
          settings,
          weightKg: weightOn(day),
          age: ageFromSettings(settings, day),
          sex: sex,
        );
        return StreakDay(
          date: day,
          steps: m?.steps,
          mealCount: n?.entryCount ?? 0,
          intakeKcal: n?.calories ?? 0,
          expenditureKcal: dayExpenditure(
            day: day,
            now: now,
            manualKcal: settings.expenditureKcalManual,
            basal: basal,
            activeKcal: m?.activeKcal,
            steps: m?.steps ?? 0,
          )?.kcal,
        );
      }(),
  ];
}

/// Haftalık hedef açık (kcal) bugünkü motor sonucundan.
int weekTargetFor(ResolvedTargets r) => weeklyDeficitTarget(
      kgPerWeek: r.mode == TargetsMode.rate ? r.rate.kgPerWeek : null,
      dailyDeficit: r.mode == TargetsMode.classic ? r.deficit : 0,
    );

/// Pazartesi–Pazar haftalık kalori açığı; anahtar haftanın pazartesisi.
/// Bugün, SeriDetay, İçgörü ve bildirim aynı sağlayıcıyı okur.
final weekDeficitProvider =
    FutureProvider.family<WeekDeficit, DateTime>((ref, weekStart) async {
  final start = AppDates.weekStart(weekStart);
  final now = ref.watch(trendClockProvider)();
  final health = await ref.watch(
      healthDaysProvider((from: start, to: AppDates.addDays(start, 6))).future);
  final resolved = await ref.watch(resolvedTargetsProvider.future);
  return computeWeekDeficit(
    weekStart: start,
    days: health.days,
    today: now,
    targetKcal: weekTargetFor(resolved),
  );
});

/// Bu haftanın açığı.
final currentWeekDeficitProvider = FutureProvider<WeekDeficit>((ref) {
  final now = ref.watch(trendClockProvider)();
  return ref.watch(weekDeficitProvider(AppDates.weekStart(now)).future);
});

/// Son [weeks] haftanın açığı (eskiden yeniye; SeriDetay 8 hafta).
final pastWeekDeficitsProvider =
    FutureProvider.family<List<WeekDeficit>, int>((ref, weeks) async {
  final now = ref.watch(trendClockProvider)();
  final thisWeek = AppDates.weekStart(now);
  return Future.wait([
    for (var i = weeks - 1; i >= 0; i--)
      ref.watch(weekDeficitProvider(AppDates.addDays(thisWeek, -7 * i)).future),
  ]);
});
