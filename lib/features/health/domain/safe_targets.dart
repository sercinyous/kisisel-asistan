import 'dart:math' as math;

/// Sağlık hedeflerinin güvenlik sınırları. Hedef motoru, örnek menüler ve eksik
/// satırı aynı sabitleri kullanır. Saf fonksiyonlar; bilgilendirme
/// amaçlıdır, tıbbi tavsiye değildir.
abstract final class SafeTargets {
  /// Hız modlarında kalori tabanı: max(1.200, bazal).
  static const int kcalFloorMin = 1200;

  /// Günlük açık sınırı: harcamanın %25'i, en çok 1.000 kcal.
  static const double deficitCapShare = 0.25;
  static const int deficitCapMax = 1000;

  /// Plan kilidi: 18 yaş altı ya da VKİ (şimdiki veya hedef) 18,5 altı.
  static const int adultAge = 18;
  static const double minBmi = 18.5;

  /// Makrolar: protein kg × 2 ile başlar, kalori yetmezse kg × 1,6'ya iner;
  /// her durumda en çok 220 g. Yağ kalori yetmezse kg × 0,5'e iner.
  static const double proteinStartPerKg = 2;
  static const double proteinMinPerKg = 1.6;
  static const int proteinMaxG = 220;
  static const double fatMinPerKg = 0.6;
  static const double fatFloorPerKg = 0.5;
  static const double fatShareOfKcal = 0.25;
  static const double maintenanceFatShare = 0.27;
  static const double fiberPer1000Kcal = 14;

  /// Elle girilen harcama model tahmininden ±%30'dan fazla saparsa uyarı.
  static const double manualExpenditureTolerance = 0.30;

  /// Tek öğün hedefin en çok %45'i; et/balık öğün başına en çok 250 g.
  static const double maxMealShare = 0.45;
  static const int maxMeatGramsPerMeal = 250;

  /// Eksik satırı en çok bu kadar öneri verir.
  static const int maxGapSuggestions = 2;

  /// Günlük su: kg × 35 ml, en çok 4.000 ml.
  static const int waterMlPerKg = 35;
  static const int waterMaxMl = 4000;

  /// Ardışık bu kadar kapalı gün tabanın altında kalınca uyarı.
  static const int lowIntakeWarningDays = 3;

  static const String lowIntakeWarning = 'Son 3 gün çok az yedin';
  static const String manualExpenditureWarning =
      'Bu değer tahminden çok farklı';
  static const String classicBelowFloorWarning =
      'Klasik formül 1.200 kcal\'nin altında hedef veriyor; bu kadar az '
      'kaloriyle uzun süre devam etme.';
  static const String classicSurplusWarning =
      'Klasik formül harcamandan fazla kalori veriyor; bu hedefle kilo '
      'vermezsin. Hız seçeneklerinden birini dene.';
  static const String lockedMessage =
      'Kilo verme planı sana uygun değil, dengeli beslenme hedefleri '
      'gösteriliyor';
  static const String clampedMessage = 'Hızın güvenli sınıra indirildi';
}

/// Kalori tabanı: max(1.200, bazal). Bazal bilinmiyorsa 1.200.
int kcalFloor(double? basalKcal) => math.max(
      SafeTargets.kcalFloorMin,
      basalKcal == null || !basalKcal.isFinite ? 0 : basalKcal.round(),
    );

/// Günlük açık sınırı: min(harcamanın %25'i, 1.000).
int deficitCap(int expenditureKcal) => math.min(
      (expenditureKcal * SafeTargets.deficitCapShare).round(),
      SafeTargets.deficitCapMax,
    );

/// Vücut kitle indeksi; boy bilinmiyorsa `null`.
double? bmiOf(double weightKg, int? heightCm) {
  if (heightCm == null || heightCm <= 0 || weightKg <= 0) return null;
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// Kilo verme planı kilitli mi? 18 yaş altı ya da şimdiki veya hedef VKİ
/// 18,5'in altı: yalnızca koruma (harcama kadar) hedefleri verilir.
bool planLocked({
  required int? age,
  required double weightKg,
  required double targetWeightKg,
  required int? heightCm,
}) {
  if (age != null && age < SafeTargets.adultAge) return true;
  final now = bmiOf(weightKg, heightCm);
  final target = bmiOf(targetWeightKg, heightCm);
  return (now != null && now < SafeTargets.minBmi) ||
      (target != null && target < SafeTargets.minBmi);
}

/// Elle girilen harcama model tahmininden ±%30'dan fazla mı sapıyor?
bool manualExpenditureOutOfRange({
  required int manualKcal,
  required int estimateKcal,
}) {
  if (estimateKcal <= 0) return false;
  final ratio = (manualKcal - estimateKcal).abs() / estimateKcal;
  return ratio > SafeTargets.manualExpenditureTolerance + 1e-9;
}

/// Günlük su hedefi: min(kg × 35, 4.000) ml, 50 ml'ye yuvarlı.
int recommendedWaterMl(double weightKg) => math.min(
      (weightKg * SafeTargets.waterMlPerKg / 50).round() * 50,
      SafeTargets.waterMaxMl,
    );

/// Makro sonucu ve hangi indirimlerin yapıldığı.
class MacroFit {
  const MacroFit({
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.fiberG,
    required this.proteinReduced,
    required this.fatReduced,
  });

  final int proteinG;
  final int fatG;
  final int carbsG;
  final int fiberG;

  /// Protein başlangıç değerinin altına indi.
  final bool proteinReduced;

  /// Yağ başlangıç değerinin altına indi.
  final bool fatReduced;

  /// P×4 + Y×9 + K×4 (kcal).
  int get kcal => proteinG * 4 + fatG * 9 + carbsG * 4;
}

/// Makroları [kcal]'a sığdırır; toplam asla [kcal]'ı aşmaz. Sıra:
/// 1) protein en çok 220 g; 2) sığmazsa protein kg × 1,6'ya doğru iner;
/// 3) yine sığmazsa yağ kg × 0,5'e doğru iner; 4) son çare protein ve yağ
/// kalan kaloriye kırpılır. Karbonhidrat kalandır (≥ 0). Orantılı ölçekleme
/// yapılmaz.
MacroFit fitMacros({
  required double weightKg,
  required int kcal,
  required int proteinG,
  required int fatG,
}) {
  final startProtein = proteinG;
  final startFat = fatG;
  var protein = math.min(proteinG, SafeTargets.proteinMaxG);
  var fat = fatG;
  bool over() => protein * 4 + fat * 9 > kcal;

  if (over()) {
    final pMin = math.min(
      (weightKg * SafeTargets.proteinMinPerKg).floor(),
      SafeTargets.proteinMaxG,
    );
    final fits = ((kcal - fat * 9) / 4).floor();
    protein = math.max(math.min(pMin, protein), math.min(protein, fits));
  }
  if (over()) {
    final fFloor = (weightKg * SafeTargets.fatFloorPerKg).ceil();
    final fits = ((kcal - protein * 4) / 9).floor();
    fat = math.max(math.min(fFloor, fat), math.min(fat, fits));
  }
  if (over()) {
    if (protein * 4 > kcal) protein = math.max(0, kcal ~/ 4);
    fat = math.max(0, (kcal - protein * 4) ~/ 9);
  }
  final rest = kcal - (protein * 4 + fat * 9);
  return MacroFit(
    proteinG: protein,
    fatG: fat,
    carbsG: rest <= 0 ? 0 : rest ~/ 4,
    fiberG: (kcal * SafeTargets.fiberPer1000Kcal / 1000).floor(),
    proteinReduced: protein < startProtein,
    fatReduced: fat < startFat,
  );
}
