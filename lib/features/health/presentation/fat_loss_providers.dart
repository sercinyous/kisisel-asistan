import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../onboarding/domain/goal_suggestion.dart' show TargetLimits;
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/energy_balance.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/fat_loss_plan.dart';
import '../domain/fat_loss_rate.dart';
import '../domain/meal_gap.dart';
import 'energy_providers.dart' show energyWeightLookbackDays;
import 'health_providers.dart';

export '../domain/fat_loss_plan.dart';
export '../domain/fat_loss_rate.dart';
export '../domain/meal_gap.dart';

/// Son tartı (son [energyWeightLookbackDays] gün); yoksa `null`. Kilo
/// eklenince ya da silinince [weightSeriesProvider] yenilendiği için plan
/// kendiliğinden güncellenir.
final fatLossWeightProvider = FutureProvider<WeightEntry?>((ref) async {
  final series =
      await ref.watch(weightSeriesProvider(energyWeightLookbackDays).future);
  if (series.isEmpty) return null;
  return series.reduce((a, b) => b.loggedAt.isBefore(a.loggedAt) ? a : b);
});

const String fatLossExpenditureKey = 'fat_loss_expenditure_kcal';
const String fatLossManualModeKey = 'fat_loss_expenditure_manual';
const String fatLossRateKey = 'fat_loss_rate';

/// Seçilen haftalık kayıp hızı; cihazda saklanır, varsayılan klasik.
final fatLossRateProvider =
    StateNotifierProvider<FatLossRateNotifier, FatLossRate>(
  (ref) => FatLossRateNotifier(),
);

class FatLossRateNotifier extends StateNotifier<FatLossRate> {
  FatLossRateNotifier() : super(FatLossRate.classic) {
    _load();
  }

  /// Yükleme bitmeden [set] çağrıldıysa saklı değer onu ezmez.
  bool _touched = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(fatLossRateKey);
      if (stored != null && mounted && !_touched) {
        state = FatLossRate.parse(stored);
      }
    } on Object {
      // Saklama kullanılamıyorsa klasik formülle devam edilir.
    }
  }

  Future<void> set(FatLossRate rate) async {
    _touched = true;
    state = rate;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(fatLossRateKey, rate.name);
    } on Object {
      // Kalıcı yazılamazsa seçim bu oturumda geçerli kalır.
    }
  }
}

int clampExpenditure(int kcal) => kcal
    .clamp(FatLossRules.expenditureMin, FatLossRules.expenditureMax)
    .toInt();

/// Kullanıcının elle girdiği günlük harcama; cihazda saklanır.
final manualExpenditureProvider =
    StateNotifierProvider<ManualExpenditureNotifier, int>(
  (ref) => ManualExpenditureNotifier(),
);

class ManualExpenditureNotifier extends StateNotifier<int> {
  ManualExpenditureNotifier() : super(FatLossRules.defaultExpenditure) {
    _load();
  }

  /// Yükleme bitmeden [set] çağrıldıysa saklı değer onu ezmez.
  bool _touched = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(fatLossExpenditureKey);
      if (stored != null && mounted && !_touched) {
        state = clampExpenditure(stored);
      }
    } on Object {
      // Saklama kullanılamıyorsa varsayılan değerle devam edilir.
    }
  }

  Future<void> set(int kcal) async {
    _touched = true;
    state = clampExpenditure(kcal);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(fatLossExpenditureKey, state);
    } on Object {
      // Kalıcı yazılamazsa değer bu oturumda geçerli kalır.
    }
  }
}

/// Profil tam olsa bile elle girilen harcamanın kullanılması; cihazda
/// saklanır.
final manualExpenditureModeProvider =
    StateNotifierProvider<ManualModeNotifier, bool>(
  (ref) => ManualModeNotifier(),
);

class ManualModeNotifier extends StateNotifier<bool> {
  ManualModeNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(fatLossManualModeKey);
      if (stored != null && mounted) state = stored;
    } on Object {
      // Saklama kullanılamıyorsa profil hesabıyla devam edilir.
    }
  }

  Future<void> set(bool manual) async {
    state = manual;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(fatLossManualModeKey, manual);
    } on Object {
      // Kalıcı yazılamazsa seçim bu oturumda geçerli kalır.
    }
  }
}

/// Günlük harcama ve kaynağı. [profileAvailable]: profil hesaba yetecek
/// kadar dolu.
typedef FatLossExpenditure = ({
  int kcal,
  bool fromProfile,
  bool profileAvailable,
});

/// Profilden (Mifflin–St Jeor × hareket katsayısı) harcama; profil eksikse
/// `null`. Sonuç 1200–6000 kcal aralığına sıkıştırılır.
int? profileExpenditure(UserSettings settings, double weightKg) {
  final basal = profileBasal(settings, weightKg);
  final activity = settings.activityLevel;
  if (basal == null || activity == null) return null;
  return clampExpenditure((basal * activity.factor).round());
}

/// Profilden bazal (Mifflin–St Jeor); profil eksikse `null`.
double? profileBasal(UserSettings settings, double weightKg) {
  final sex = Sex.tryParse(settings.sex);
  final height = settings.heightCm;
  final birthYear = settings.birthYear;
  final activity = settings.activityLevel;
  if (sex == null || height == null || birthYear == null || activity == null) {
    return null;
  }
  final age = DateTime.now().year - birthYear;
  return basalKcal(
    weightKg: weightKg,
    heightCm: height,
    age: age < 0 ? 0 : age,
    sex: sex,
  );
}

/// Profil tamsa ve elle giriş seçilmediyse profilden; değilse elle girilen.
FatLossExpenditure resolveExpenditure({
  required UserSettings settings,
  required double weightKg,
  required int manualKcal,
  required bool manualMode,
}) {
  final profile = profileExpenditure(settings, weightKg);
  if (profile != null && !manualMode) {
    return (kcal: profile, fromProfile: true, profileAvailable: true);
  }
  return (
    kcal: clampExpenditure(manualKcal),
    fromProfile: false,
    profileAvailable: profile != null,
  );
}

/// Plan: son tartı + hedefler + harcama. Tartı yoksa `null`.
class FatLossPlanState {
  const FatLossPlanState({
    required this.weight,
    required this.rateResult,
    required this.expenditure,
    this.sex,
  });

  final WeightEntry weight;
  final FatLossRateResult rateResult;
  final FatLossExpenditure expenditure;

  /// Profildeki cinsiyet; bilinmiyorsa `null`.
  final Sex? sex;

  /// Seçilen hıza göre hedefler; bütün kartlar bunu kullanır.
  FatLossTargets get targets => rateResult.targets;
  FatLossRate get rate => rateResult.rate;

  WeeklyLossEstimate get weekly => estimateWeeklyLoss(
        expenditureKcal: expenditure.kcal,
        targetKcal: targets.kcal,
      );
}

/// Ayarlar yüklenene kadar bekler (elle → profil geçişi titremesin); ayar
/// hatası plan hatası olarak görünür.
final fatLossPlanProvider = FutureProvider<FatLossPlanState?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final weight = await ref.watch(fatLossWeightProvider.future);
  if (weight == null) return null;
  final expenditure = resolveExpenditure(
    settings: settings,
    weightKg: weight.weightKg,
    manualKcal: ref.watch(manualExpenditureProvider),
    manualMode: ref.watch(manualExpenditureModeProvider),
  );
  return FatLossPlanState(
    weight: weight,
    rateResult: computeRateTargets(
      weightKg: weight.weightKg,
      expenditureKcal: expenditure.kcal,
      rate: ref.watch(fatLossRateProvider),
      basalKcal: profileBasal(settings, weight.weightKg),
    ),
    expenditure: expenditure,
    sex: Sex.tryParse(settings.sex),
  );
});

/// "Hedeflerimi ayarla" ile kaydedilecek değerler. Kalori uygulamanın
/// sınırına ([TargetLimits]) sıkıştırılırsa P/Y/K aynı oranla ölçeklenir.
class FatLossApplyValues {
  const FatLossApplyValues({
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.clamped,
  });

  final int kcal;
  final int proteinG;
  final int fatG;
  final int carbsG;

  /// Kalori sınır nedeniyle değişti.
  final bool clamped;
}

FatLossApplyValues fatLossApplyValues(FatLossTargets t) {
  final kcal =
      t.kcal.clamp(TargetLimits.caloriesMin, TargetLimits.caloriesMax).toInt();
  final clamped = kcal != t.kcal;
  final ratio = clamped && t.kcal > 0 ? kcal / t.kcal : 1.0;
  int scale(int g, int min, int max) =>
      (g * ratio).round().clamp(min, max).toInt();
  return FatLossApplyValues(
    kcal: kcal,
    proteinG:
        scale(t.proteinG, TargetLimits.proteinMin, TargetLimits.proteinMax),
    fatG: scale(t.fatG, TargetLimits.fatMin, TargetLimits.fatMax),
    carbsG: scale(t.carbsG, TargetLimits.carbsMin, TargetLimits.carbsMax),
    clamped: clamped,
  );
}

/// Günlük öğün sayısı (2 ya da 3); örnek menü ve "Bugün" kartı paylaşır.
final fatLossMealCountProvider = StateProvider<int>((ref) => 3);

/// Bugünün öğünleri plan hedefleriyle; plan yoksa `null`. Öğün eklenince,
/// düzenlenince ya da silinince [dayNutritionLogsProvider] yenilendiği için
/// kendiliğinden güncellenir.
final todayMealGapProvider = FutureProvider<MealGapReport?>((ref) async {
  final plan = await ref.watch(fatLossPlanProvider.future);
  if (plan == null) return null;
  final logs = await ref.watch(
      dayNutritionLogsProvider(AppDates.startOfDay(DateTime.now())).future);
  return analyzeMealGap(
    targets: plan.targets,
    logs: logs,
    mealsPerDay: ref.watch(fatLossMealCountProvider),
    now: DateTime.now(),
  );
});
