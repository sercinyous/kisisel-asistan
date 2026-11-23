import 'dart:math' as math;

import '../../onboarding/domain/goal_suggestion.dart' show TargetLimits;
import '../../settings/domain/user_settings.dart';
import 'energy_balance.dart';
import 'fat_loss_plan.dart' show FatLossRules, FatLossTargets, formatTr;
import 'fat_loss_rate.dart';
import 'safe_targets.dart';

/// Günlük hedeflerin tek motoru. [resolveTargets] saf fonksiyondur;
/// [planWrite] ise `daily_calories/protein/carbs/fat` sütunlarının TEK
/// yazarıdır (yazılacak ayarı üretir, kaydı çağıran yapar).

/// Hedeflerin hangi kuralla üretildiği.
enum TargetsMode {
  /// Klasik formül: kcal = kg × 26 (harcamadan bağımsız).
  classic,

  /// Hız modu: kcal = harcama − r × 7700 / 7, taban max(1.200, bazal).
  rate,

  /// Hedef kilo şimdiki kilodan düşük değil: harcama kadar (koruma).
  maintain,

  /// 18 yaş altı ya da VKİ < 18,5: kilo verme planı kapalı, koruma.
  locked,
}

/// [resolveTargets] sonucu.
class ResolvedTargets {
  const ResolvedTargets({
    required this.mode,
    required this.rate,
    required this.weightKg,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.expenditure,
    required this.floorKcal,
    required this.clamped,
    required this.proteinReduced,
    required this.fatReduced,
    this.estimatedExpenditureKcal,
  });

  final TargetsMode mode;

  /// Elle değer olmasaydı modelin harcama tahmini (kcal); profil eksikse
  /// `null`. Elle girilen değer bundan ±%30 saparsa uyarı gösterilir.
  final int? estimatedExpenditureKcal;

  /// Elle girilen harcama tahminden ±%30'dan fazla sapıyor.
  bool get manualExpenditureOff {
    final estimate = estimatedExpenditureKcal;
    return expenditure.source == ExpenditureSource.manual &&
        estimate != null &&
        manualExpenditureOutOfRange(
            manualKcal: expenditure.kcal, estimateKcal: estimate);
  }

  /// Seçili hız (kilitli/korumada da ayardaki değer).
  final FatLossRate rate;

  /// Hesabın dayandığı kilo (son tartı, yoksa başlangıç kilosu).
  final double weightKg;
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int fiberG;

  /// Planın harcaması (elle, model ya da varsayılan).
  final Expenditure expenditure;

  /// Kalori tabanı: max(1.200, bazal).
  final int floorKcal;

  /// Hız modunda hedef tabana takıldı; seçilen hıza ulaşılamıyor.
  final bool clamped;

  /// Protein kcal'a sığsın diye başlangıç değerinin altına indi.
  final bool proteinReduced;

  /// Yağ kcal'a sığsın diye başlangıç değerinin altına indi.
  final bool fatReduced;

  /// Günlük açık: harcama − hedef (pozitif = açık).
  int get deficit => expenditure.kcal - kcal;

  /// Bu hedefle beklenen haftalık kayıp (kg, ≥ 0).
  double get kgPerWeek =>
      deficit <= 0 ? 0 : deficit * 7 / FatLossRules.kcalPerKgFat;

  /// Haftalık kaybın sağlık rozeti; kayıp yoksa `null`.
  RateHealth? get health =>
      kgPerWeek <= 0 ? null : classifyRate(kgPerWeek, weightKg);

  /// Klasik formül 1.200 kcal'nin altında (uyarı; sayılar değişmez).
  bool get classicBelowFloor =>
      mode == TargetsMode.classic && kcal < SafeTargets.kcalFloorMin;

  /// Klasik formül harcamaya eşit ya da üstünde: açık yok, kilo verilmez
  /// (uyarı; sayılar değişmez).
  bool get classicSurplus =>
      mode == TargetsMode.classic && kcal >= expenditure.kcal;

  /// Kilo verme planı kilitli (koruma hedefleri).
  bool get locked => mode == TargetsMode.locked;

  /// Gösterilecek uyarı satırları (sırayla).
  List<String> get warnings => [
        if (locked) SafeTargets.lockedMessage,
        if (clamped) SafeTargets.clampedMessage,
        if (classicBelowFloor) SafeTargets.classicBelowFloorWarning,
        if (classicSurplus) SafeTargets.classicSurplusWarning,
        if (mode == TargetsMode.rate && rate.warning != null) rate.warning!,
      ];

  /// "Ne kadar sağlıklı?" metinlerinin ([rateInfo]) biçimi.
  FatLossRateResult get asRateResult => FatLossRateResult(
        rate: rate,
        targets: asFatLossTargets,
        floorKcal: floorKcal,
        clampedToFloor: clamped,
        actualKgPerWeek: kgPerWeek,
        proteinReduced: proteinReduced,
        fatReduced: fatReduced,
        carbsBelowMin: carbsG < FatLossRateRules.carbsMinG,
      );

  /// Eski plan ekranlarının kullandığı biçim.
  FatLossTargets get asFatLossTargets => FatLossTargets(
        weightKg: weightKg,
        kcal: kcal,
        proteinG: proteinG,
        fatG: fatG,
        fiberG: fiberG,
        carbsG: carbsG,
      );

  @override
  String toString() => 'ResolvedTargets(${mode.name}, ${rate.dbValue}, '
      'kcal: $kcal, P $proteinG, K $carbsG, Y $fatG, deficit: $deficit, '
      'clamped: $clamped)';
}

/// Ayarlardaki doğum yılından [now] yılındaki yaş; bilinmiyorsa `null`.
int? ageFromSettings(UserSettings settings, DateTime now) {
  final birthYear = settings.birthYear;
  if (birthYear == null) return null;
  return math.max(0, now.year - birthYear);
}

/// Profilden bazal (Mifflin–St Jeor); boy, yaş ya da cinsiyet yoksa `null`.
double? settingsBasal(
  UserSettings settings, {
  required double weightKg,
  required int? age,
  required Sex? sex,
}) {
  final height = settings.heightCm;
  if (height == null || age == null || sex == null || weightKg <= 0) {
    return null;
  }
  return basalKcal(weightKg: weightKg, heightCm: height, age: age, sex: sex);
}

/// Ayarlar ve son tartıdan günlük hedefler. Saf; yazmaz.
///
/// * Kilit (18 yaş altı, VKİ < 18,5): harcama kadar kalori, koruma makroları.
/// * Hedef kilo şimdiki kilodan düşük değilse: koruma.
/// * Klasik: kcal = ⌊kg × 26⌋, protein kg × 2, yağ ⌊kcal / 30⌋,
///   lif ⌊kcal / 1000 × 14⌋, karbonhidrat kalan. 1.200 altı yalnızca uyarı.
/// * Hız: kcal = harcama − r × 7700 / 7; taban max(1.200, bazal) (altına
///   inerse [ResolvedTargets.clamped]). Protein kg × 2 (≤ 220 g),
///   yağ max(kg × 0,6, kcal × %25 / 9).
/// * Makrolar hiçbir modda kcal'ı aşmaz ([fitMacros]).
ResolvedTargets resolveTargets({
  required UserSettings settings,
  double? latestWeightKg,
  int? age,
  Sex? sex,
}) {
  final weight =
      latestWeightKg != null && latestWeightKg.isFinite && latestWeightKg > 0
          ? latestWeightKg
          : settings.startWeightKg;
  final basal = settingsBasal(settings, weightKg: weight, age: age, sex: sex);
  final expenditure = planExpenditure(
    manualKcal: settings.expenditureKcalManual,
    basal: basal,
    activityFactor: settings.activityLevel?.factor,
    stepsTarget: settings.dailySteps,
  );
  final estimate = planExpenditure(
    basal: basal,
    activityFactor: settings.activityLevel?.factor,
    stepsTarget: settings.dailySteps,
  );
  final floor = kcalFloor(basal);
  final rate = settings.weeklyRate;

  ResolvedTargets build({
    required TargetsMode mode,
    required int kcal,
    required int protein,
    required int fat,
    bool clamped = false,
  }) {
    final fit = fitMacros(
      weightKg: weight,
      kcal: kcal,
      proteinG: protein,
      fatG: fat,
    );
    return ResolvedTargets(
      mode: mode,
      rate: rate,
      weightKg: weight,
      kcal: kcal,
      proteinG: fit.proteinG,
      carbsG: fit.carbsG,
      fatG: fit.fatG,
      fiberG: fit.fiberG,
      expenditure: expenditure,
      floorKcal: floor,
      clamped: clamped,
      proteinReduced: fit.proteinReduced,
      fatReduced: fit.fatReduced,
      estimatedExpenditureKcal: estimate.source == ExpenditureSource.estimate
          ? estimate.kcal
          : null,
    );
  }

  final startProtein = math.min(
    (weight * SafeTargets.proteinStartPerKg).floor(),
    SafeTargets.proteinMaxG,
  );

  final locked = planLocked(
    age: age,
    weightKg: weight,
    targetWeightKg: settings.targetWeightKg,
    heightCm: settings.heightCm,
  );
  final losing = settings.targetWeightKg < weight - 0.05;
  if (locked || !losing) {
    final kcal = math.max(expenditure.kcal, SafeTargets.kcalFloorMin);
    return build(
      mode: locked ? TargetsMode.locked : TargetsMode.maintain,
      kcal: kcal,
      protein: math.min(
        (weight * SafeTargets.proteinMinPerKg).floor(),
        SafeTargets.proteinMaxG,
      ),
      fat: (kcal * SafeTargets.maintenanceFatShare / 9).floor(),
    );
  }

  final r = rate.kgPerWeek;
  if (r == null) {
    final kcal = (weight * FatLossRules.kcalPerKg).floor();
    return build(
      mode: TargetsMode.classic,
      kcal: kcal,
      protein: startProtein,
      fat: kcal ~/ FatLossRules.kcalPerFatGram,
    );
  }
  final raw = (expenditure.kcal - r * FatLossRules.kcalPerKgFat / 7).round();
  final clamped = raw < floor;
  final kcal = clamped ? floor : raw;
  return build(
    mode: TargetsMode.rate,
    kcal: kcal,
    protein: startProtein,
    fat: math.max(
      (weight * SafeTargets.fatMinPerKg).ceil(),
      (kcal * SafeTargets.fatShareOfKcal / 9).floor(),
    ),
    clamped: clamped,
  );
}

/// [planWrite]'ı tetikleyen olay.
enum PlanTrigger {
  /// İlk kurulum: her zaman yazar, kaynak 'onboarding'.
  onboarding,

  /// Tartı kaydı: kaynak 'manual' değilse ve fark eşiği aşıyorsa yazar.
  weightSaved,

  /// Profil (hedef kilo, boy, hareket, adım) kaydedildi: [weightSaved] ile
  /// aynı kural.
  profileSaved,

  /// Tempo değişti: her zaman yazar, kaynak 'plan'.
  rateChanged,

  /// "Kilona göre önerilen … [Uygula]": her zaman yazar, kaynak 'plan'.
  suggestionApplied,
}

/// Tartı sonrası yeniden yazma eşikleri.
abstract final class PlanThresholds {
  static const int kcal = 50;
  static const int proteinG = 5;
}

/// [planWrite] sonucu: yazılacak ayar ve snackbar için eski/yeni kalori.
class PlanWrite {
  const PlanWrite({
    required this.settings,
    required this.previousKcal,
    required this.kcal,
  });

  final UserSettings settings;
  final int previousKcal;
  final int kcal;

  /// "Hedefin güncellendi: 1.880 → 1.850 kcal"
  String get message =>
      'Hedefin güncellendi: ${formatTr(previousKcal)} → ${formatTr(kcal)} kcal';
}

/// Hedef, ayardaki değerlerden eşik kadar farklı mı?
bool targetsDiffer(UserSettings settings, ResolvedTargets resolved) {
  final v = _dbValues(resolved);
  return (v.kcal - settings.dailyCalories).abs() > PlanThresholds.kcal ||
      (v.protein - settings.dailyProteinG).abs() > PlanThresholds.proteinG;
}

/// `daily_*` sütunlarının sınırına sıkıştırılmış değerler (ölçekleme yok).
({int kcal, int protein, int carbs, int fat}) _dbValues(ResolvedTargets r) => (
      kcal: r.kcal
          .clamp(TargetLimits.caloriesMin, TargetLimits.caloriesMax)
          .toInt(),
      protein: r.proteinG
          .clamp(TargetLimits.proteinMin, TargetLimits.proteinMax)
          .toInt(),
      carbs:
          r.carbsG.clamp(TargetLimits.carbsMin, TargetLimits.carbsMax).toInt(),
      fat: r.fatG.clamp(TargetLimits.fatMin, TargetLimits.fatMax).toInt(),
    );

/// `daily_calories/protein/carbs/fat` sütunlarının TEK yazarı. Yazılacak
/// ayarı döndürür; yazma gerekmiyorsa `null`:
/// * [PlanTrigger.weightSaved], [PlanTrigger.profileSaved]: kaynak 'manual'
///   ise ya da fark eşiğin
///   altındaysa (|Δkcal| ≤ 50 ve |Δprotein| ≤ 5 g) yazılmaz.
/// * Diğer tetikleyiciler her zaman yazar.
/// Kaynak ilk kurulumda 'onboarding', diğerlerinde 'plan' olur;
/// `targets_updated_at` [now] ile damgalanır.
PlanWrite? planWrite({
  required UserSettings settings,
  required ResolvedTargets resolved,
  required PlanTrigger trigger,
  required DateTime now,
}) {
  if (trigger == PlanTrigger.weightSaved ||
      trigger == PlanTrigger.profileSaved) {
    if (settings.targetsSource == TargetsSource.manual) return null;
    if (!targetsDiffer(settings, resolved)) return null;
  }
  final v = _dbValues(resolved);
  return PlanWrite(
    previousKcal: settings.dailyCalories,
    kcal: v.kcal,
    settings: settings.copyWith(
      weeklyRate: resolved.rate,
      dailyCalories: v.kcal,
      dailyProteinG: v.protein,
      dailyCarbsG: v.carbs,
      dailyFatG: v.fat,
      targetsSource: trigger == PlanTrigger.onboarding
          ? TargetsSource.onboarding
          : TargetsSource.plan,
      targetsUpdatedAt: now,
    ),
  );
}

/// Ayarlar > Hedeflerim elle kaydı: değerler aynen yazılır, kaynak 'manual'.
UserSettings manualTargets(
  UserSettings settings, {
  required int kcal,
  required int proteinG,
  required int carbsG,
  required int fatG,
  required DateTime now,
}) =>
    settings.copyWith(
      dailyCalories: kcal,
      dailyProteinG: proteinG,
      dailyCarbsG: carbsG,
      dailyFatG: fatG,
      targetsSource: TargetsSource.manual,
      targetsUpdatedAt: now,
    );

/// Kayıtlı hedef motorun sonucundan eşik kadar farklıysa önerilen hedef
/// ("Kilona göre önerilen 1.820 kcal [Uygula]"); kaynaktan bağımsızdır
/// (elle ayar ya da henüz yeniden yazılmamış plan). Fark yoksa `null`.
ResolvedTargets? planSuggestion(
  UserSettings settings,
  ResolvedTargets resolved,
) =>
    targetsDiffer(settings, resolved) ? resolved : null;
