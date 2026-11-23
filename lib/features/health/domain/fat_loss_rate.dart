import 'dart:math' as math;

import 'energy_balance.dart' show Sex;
import 'fat_loss_plan.dart';

/// Yağ yakımı hızı seçimi ve sağlık değerlendirmesi. Saf fonksiyonlar;
/// bilgilendirme amaçlıdır, tıbbi tavsiye değildir.

/// Haftalık kayıp hızı. [classic]: sabit kg × 26 formülü (varsayılan).
enum FatLossRate {
  classic(null, 'Klasik (kg×26)'),
  half(0.5, '0,50 kg/hafta'),
  threeQuarter(0.75, '0,75 kg/hafta'),
  one(1.0, '1 kg/hafta');

  const FatLossRate(this.kgPerWeek, this.label);

  /// Hedef haftalık kayıp; klasikte `null`.
  final double? kgPerWeek;
  final String label;

  /// Saklanan değeri çözer; tanınmayan değer klasiğe düşer.
  static FatLossRate parse(String? value) {
    for (final r in FatLossRate.values) {
      if (r.name == value) return r;
    }
    return FatLossRate.classic;
  }
}

/// Hız modlarının sabitleri.
abstract final class FatLossRateRules {
  static const int kcalFloor = 1200;
  static const double proteinCapPerKg = 2.2;
  static const double fatMinPerKg = 0.6;
  static const double fatShareOfKcal = 0.25;
  static const int carbsMinG = 50;

  /// Vücut ağırlığının yüzdesi olarak haftalık kayıp sınırları.
  static const double sustainablePct = 0.7;
  static const double fastPct = 1.0;
}

/// Hız modunun sonucu: hedefler ve uyarı durumları.
class FatLossRateResult {
  const FatLossRateResult({
    required this.rate,
    required this.targets,
    required this.floorKcal,
    required this.clampedToFloor,
    required this.actualKgPerWeek,
    required this.fatReduced,
    required this.carbsBelowMin,
  });

  final FatLossRate rate;
  final FatLossTargets targets;

  /// Uygulanan kalori tabanı: max(1200, bazal).
  final int floorKcal;

  /// Hedef kalori tabana takıldı.
  final bool clampedToFloor;

  /// Harcama − hedef açığıyla gerçek haftalık kayıp (≥ 0).
  final double actualKgPerWeek;

  /// Karbonhidrat 50 g'a yetsin diye yağ kg × 0,6'ya doğru azaltıldı.
  final bool fatReduced;

  /// Yağ en alt sınırda olsa da karbonhidrat 50 g'ın altında kaldı.
  final bool carbsBelowMin;
}

/// Hız modu için günlük kalori: harcama − r × 7700 / 7; en az
/// max(1200, bazal). Klasikte [computeFatLossTargets] aynen kullanılır.
FatLossRateResult computeRateTargets({
  required double weightKg,
  required int expenditureKcal,
  required FatLossRate rate,
  double? basalKcal,
}) {
  if (!weightKg.isFinite || weightKg <= 0) {
    throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
  }
  final floor = math.max(
    FatLossRateRules.kcalFloor,
    basalKcal == null || !basalKcal.isFinite ? 0 : basalKcal.round(),
  );
  final r = rate.kgPerWeek;
  if (r == null) {
    final t = computeFatLossTargets(weightKg);
    return FatLossRateResult(
      rate: rate,
      targets: t,
      floorKcal: floor,
      clampedToFloor: false,
      actualKgPerWeek: _weeklyKg(expenditureKcal, t.kcal),
      fatReduced: false,
      carbsBelowMin: false,
    );
  }
  final raw =
      (expenditureKcal - r * FatLossRules.kcalPerKgFat / 7).round();
  final clamped = raw < floor;
  final kcal = clamped ? floor : raw;
  final macros = rateMacros(weightKg: weightKg, kcal: kcal);
  return FatLossRateResult(
    rate: rate,
    targets: macros.targets,
    floorKcal: floor,
    clampedToFloor: clamped,
    actualKgPerWeek: _weeklyKg(expenditureKcal, kcal),
    fatReduced: macros.fatReduced,
    carbsBelowMin: macros.carbsBelowMin,
  );
}

double _weeklyKg(int expenditure, int kcal) {
  final deficit = expenditure - kcal;
  return deficit <= 0 ? 0 : deficit * 7 / FatLossRules.kcalPerKgFat;
}

/// Hız modu makroları: protein = kg × 2 (en çok kg × 2,2);
/// yağ = max(kg × 0,6, kcal × 0,25 / 9); lif = kcal / 1000 × 14;
/// karbonhidrat kalan (en az 50 g hedeflenir; yetmezse yağ kg × 0,6'ya
/// doğru azaltılır).
({FatLossTargets targets, bool fatReduced, bool carbsBelowMin}) rateMacros({
  required double weightKg,
  required int kcal,
}) {
  final protein = math.min(
    (weightKg * FatLossRules.proteinPerKg).floor(),
    (weightKg * FatLossRateRules.proteinCapPerKg).floor(),
  );
  final fatMin = (weightKg * FatLossRateRules.fatMinPerKg).ceil();
  var fat = math.max(
    fatMin,
    (kcal * FatLossRateRules.fatShareOfKcal / 9).floor(),
  );
  final fiber = (kcal * FatLossRules.fiberPer1000Kcal / 1000).floor();
  int carbsFor(int f) {
    final rest = kcal - (protein * 4 + f * 9);
    return rest <= 0 ? 0 : rest ~/ 4;
  }

  var carbs = carbsFor(fat);
  var reduced = false;
  if (carbs < FatLossRateRules.carbsMinG && fat > fatMin) {
    final needKcal = (FatLossRateRules.carbsMinG - carbs) * 4;
    final cut = math.min(fat - fatMin, (needKcal / 9).ceil());
    fat -= cut;
    reduced = cut > 0;
    carbs = carbsFor(fat);
  }
  return (
    targets: FatLossTargets(
      weightKg: weightKg,
      kcal: kcal,
      proteinG: protein,
      fatG: fat,
      fiberG: fiber,
      carbsG: carbs,
    ),
    fatReduced: reduced,
    carbsBelowMin: carbs < FatLossRateRules.carbsMinG,
  );
}

/// Haftalık kaybın vücut ağırlığına göre sınıfı.
enum RateHealth {
  sustainable('Sürdürülebilir'),
  fast('Hızlı'),
  aggressive('Agresif');

  const RateHealth(this.label);
  final String label;
}

/// Haftalık kayıp, vücut ağırlığının yüzdesi.
double ratePercentOfBodyWeight(double kgPerWeek, double weightKg) =>
    weightKg <= 0 ? 0 : kgPerWeek / weightKg * 100;

/// ≤ %0,7 sürdürülebilir; %0,7–1,0 hızlı; > %1,0 agresif.
RateHealth classifyRate(double kgPerWeek, double weightKg) {
  final pct = ratePercentOfBodyWeight(kgPerWeek, weightKg);
  if (pct <= FatLossRateRules.sustainablePct + 1e-9) {
    return RateHealth.sustainable;
  }
  if (pct <= FatLossRateRules.fastPct + 1e-9) return RateHealth.fast;
  return RateHealth.aggressive;
}

/// "Ne kadar sağlıklı?" metinleri.
class RateInfo {
  const RateInfo({required this.pros, required this.cons, this.note});

  final List<String> pros;
  final List<String> cons;
  final String? note;
}

const String rateWaterNote =
    'İlk 1–2 haftada tartıdaki hızlı düşüşün bir kısmı sudur.';

RateInfo rateInfo(FatLossRate rate) => switch (rate) {
      FatLossRate.classic => const RateInfo(
          pros: [
            'Sabit formül: kilonun 26 katı kalori; harcamaya bağlı değil.',
            'Hesabı basit, her gün aynı hedef.',
          ],
          cons: [
            'Haftalık hız harcamana göre değişir; aşağıdaki tahmine bak.',
          ],
        ),
      FatLossRate.half => const RateInfo(
          pros: [
            'Kas kaybı en az.',
            'Açlık ve halsizlik az.',
            'Alışkanlık kalıcı olur.',
            'Antrenman performansı korunur.',
          ],
          cons: [
            'Görünür ilerleme yavaş.',
            'Motivasyon düşebilir.',
            'Uzun süre gerekir.',
          ],
        ),
      FatLossRate.threeQuarter => const RateInfo(
          pros: [
            'Hız ve sürdürülebilirlik dengesi.',
            'Çoğu kişi için uygun.',
          ],
          cons: [
            'Yüksek proteine ve uykuya daha çok dikkat gerekir.',
            'Bazı günler açlık hissi olabilir.',
          ],
        ),
      FatLossRate.one => const RateInfo(
          pros: [
            'Hızlı sonuç.',
            'Yüksek kilolularda başlangıçta uygun olabilir.',
          ],
          cons: [
            'Kas kaybı riski artar.',
            'Yorgunluk, açlık ve sinirlilik.',
            'Besin eksikliği riski.',
            'Safra kesesi taşı riski.',
            'Uzun süre sürdürmek zor; 2–4 haftadan uzun sürdürmeden önce '
                'doktora danış.',
          ],
          note: rateWaterNote,
        ),
    };

/// Diyette günlük vitamin/mineral rehberi (genel yetişkin bilgisi).
class SupplementGuide {
  const SupplementGuide({
    required this.waterMl,
    required this.magnesiumText,
    required this.multivitaminHighlighted,
  });

  /// Günlük su: kg × 35 ml (50 ml'ye yuvarlı).
  final int waterMl;

  /// Cinsiyete göre toplam magnezyum; bilinmiyorsa iki değer.
  final String magnesiumText;

  /// Kalori 1.500'ün altında: multivitamin özellikle önerilir.
  final bool multivitaminHighlighted;
}

abstract final class SupplementRules {
  static const int waterMlPerKg = 35;
  static const int multivitaminKcalLimit = 1500;
}

SupplementGuide supplementGuide({
  required double weightKg,
  required Sex? sex,
  required int kcal,
}) {
  final water = (weightKg * SupplementRules.waterMlPerKg / 50).round() * 50;
  final magnesium = switch (sex) {
    Sex.female => 'Kadın: 310–320 mg/gün toplam (yiyecek + takviye)',
    Sex.male => 'Erkek: 400–420 mg/gün toplam (yiyecek + takviye)',
    _ => 'Kadın 310–320 mg, erkek 400–420 mg/gün toplam '
        '(yiyecek + takviye)',
  };
  return SupplementGuide(
    waterMl: water,
    magnesiumText: magnesium,
    multivitaminHighlighted: kcal < SupplementRules.multivitaminKcalLimit,
  );
}
