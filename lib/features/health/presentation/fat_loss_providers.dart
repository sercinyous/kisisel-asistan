import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/energy_balance.dart';
import '../domain/fat_loss_plan.dart';
import '../domain/fat_loss_rate.dart';
import '../domain/meal_gap.dart';
import 'health_providers.dart';
import 'providers/targets_providers.dart';
import 'trend_providers.dart' show trendClockProvider;

export '../domain/fat_loss_plan.dart';
export '../domain/fat_loss_rate.dart';
export '../domain/meal_gap.dart';

/// Yağ yakımı ekranının sağlayıcıları. Tüm değerler `user_settings`'ten
/// okunur ve [PlanController] ile yazılır (cihazda tercih saklanmaz); hedef
/// sayıları tek motordan ([resolveTargets]) gelir.

/// Seçilen haftalık kayıp hızı (`user_settings.weekly_rate`).
final fatLossRateProvider =
    NotifierProvider<FatLossRateNotifier, FatLossRate>(FatLossRateNotifier.new);

class FatLossRateNotifier extends Notifier<FatLossRate> {
  @override
  FatLossRate build() => ref.watch(settingsOrDefaultProvider).weeklyRate;

  /// Tempo değişimi her zaman hedefleri yeniden yazar ([PlanTrigger.rateChanged]).
  Future<void> set(FatLossRate rate) async {
    state = rate;
    await ref
        .read(planControllerProvider)
        .applyPlan(PlanTrigger.rateChanged, rate: rate);
  }
}

int clampExpenditure(int kcal) => kcal
    .clamp(FatLossRules.expenditureMin, FatLossRules.expenditureMax)
    .toInt();

/// Elle girilen günlük harcama; girilmediyse varsayılan öneri.
final manualExpenditureProvider =
    NotifierProvider<ManualExpenditureNotifier, int>(
  ManualExpenditureNotifier.new,
);

class ManualExpenditureNotifier extends Notifier<int> {
  @override
  int build() =>
      ref.watch(settingsOrDefaultProvider).expenditureKcalManual ??
      FatLossRules.defaultExpenditure;

  Future<void> set(int kcal) async {
    state = clampExpenditure(kcal);
    await ref.read(planControllerProvider).setExpenditureManual(state);
  }
}

/// Elle girilen harcama kullanılıyor mu (`expenditure_kcal_manual` dolu).
final manualExpenditureModeProvider =
    NotifierProvider<ManualModeNotifier, bool>(ManualModeNotifier.new);

class ManualModeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(settingsOrDefaultProvider).expenditureKcalManual != null;

  Future<void> set(bool manual) async {
    state = manual;
    await ref
        .read(planControllerProvider)
        .setExpenditureManual(manual ? ref.read(manualExpenditureProvider) : null);
  }
}

/// Günlük harcama ve kaynağı. [profileAvailable]: profil hesaba yetecek
/// kadar dolu.
typedef FatLossExpenditure = ({
  int kcal,
  bool fromProfile,
  bool profileAvailable,
});

/// Plan: son tartı + motor sonucu + harcama. Tartı yoksa `null`.
class FatLossPlanState {
  const FatLossPlanState({
    required this.weight,
    required this.resolved,
    required this.expenditure,
    this.sex,
  });

  final WeightEntry weight;
  final ResolvedTargets resolved;
  final FatLossExpenditure expenditure;

  /// Profildeki cinsiyet; bilinmiyorsa `null`.
  final Sex? sex;

  /// Eski kartların biçimi.
  FatLossRateResult get rateResult => FatLossRateResult(
        rate: resolved.rate,
        targets: targets,
        floorKcal: resolved.floorKcal,
        clampedToFloor: resolved.clamped,
        actualKgPerWeek: resolved.kgPerWeek,
        proteinReduced: resolved.proteinReduced,
        fatReduced: resolved.fatReduced,
        carbsBelowMin: resolved.carbsG < FatLossRateRules.carbsMinG,
      );

  /// Seçilen hıza göre hedefler; bütün kartlar bunu kullanır.
  FatLossTargets get targets => resolved.asFatLossTargets;
  FatLossRate get rate => resolved.rate;

  WeeklyLossEstimate get weekly => estimateWeeklyLoss(
        expenditureKcal: expenditure.kcal,
        targetKcal: targets.kcal,
      );
}

/// Ayarlar yüklenene kadar bekler; ayar hatası plan hatası olarak görünür.
final fatLossPlanProvider = FutureProvider<FatLossPlanState?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final weight = await ref.watch(latestWeightProvider.future);
  if (weight == null) return null;
  final now = ref.watch(trendClockProvider)();
  final age = ageFromSettings(settings, now);
  final sex = Sex.tryParse(settings.sex);
  final resolved = resolveTargets(
    settings: settings,
    latestWeightKg: weight.weightKg,
    age: age,
    sex: sex,
  );
  final basal =
      settingsBasal(settings, weightKg: weight.weightKg, age: age, sex: sex);
  return FatLossPlanState(
    weight: weight,
    resolved: resolved,
    expenditure: (
      kcal: resolved.expenditure.kcal,
      fromProfile: resolved.expenditure.source == ExpenditureSource.estimate,
      profileAvailable: basal != null,
    ),
    sex: sex,
  );
});

/// Günlük öğün sayısı (2 ya da 3; `user_settings.meal_count`); örnek menü ve
/// "Bugün" kartı paylaşır.
final fatLossMealCountProvider =
    NotifierProvider<MealCountNotifier, int>(MealCountNotifier.new);

class MealCountNotifier extends Notifier<int> {
  @override
  int build() => ref.watch(settingsOrDefaultProvider).mealCount;

  Future<void> set(int count) async {
    state = count;
    await ref.read(planControllerProvider).setMealCount(count);
  }
}

/// Bugünün öğünleri `user_settings` hedefleriyle; tartı yoksa `null`. Öğün
/// eklenince, düzenlenince ya da silinince [dayNutritionLogsProvider]
/// yenilendiği için kendiliğinden güncellenir.
final todayMealGapProvider = FutureProvider<MealGapReport?>((ref) async {
  final plan = await ref.watch(fatLossPlanProvider.future);
  if (plan == null) return null;
  final t = ref.watch(targetsProvider);
  final logs = await ref.watch(
      dayNutritionLogsProvider(AppDates.startOfDay(DateTime.now())).future);
  return analyzeMealGap(
    targets: FatLossTargets(
      weightKg: plan.weight.weightKg,
      kcal: t.kcal,
      proteinG: t.proteinG,
      fatG: t.fatG,
      fiberG: plan.targets.fiberG,
      carbsG: t.carbsG,
    ),
    logs: logs,
    mealsPerDay: ref.watch(fatLossMealCountProvider),
    now: DateTime.now(),
  );
});
