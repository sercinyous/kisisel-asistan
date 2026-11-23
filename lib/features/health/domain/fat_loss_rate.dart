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

  /// `user_settings.weekly_rate` değeri: 'classic', '0.5', '0.75', '1.0'.
  String get dbValue => switch (this) {
        FatLossRate.classic => 'classic',
        FatLossRate.half => '0.5',
        FatLossRate.threeQuarter => '0.75',
        FatLossRate.one => '1.0',
      };

  /// Saklanan değeri çözer (veritabanı değeri ya da eski cihaz tercihindeki
  /// enum adı); tanınmayan değer klasiğe düşer.
  static FatLossRate parse(String? value) {
    for (final r in FatLossRate.values) {
      if (r.name == value || r.dbValue == value) return r;
    }
    return FatLossRate.classic;
  }

  /// 1 kg/hafta seçilince gösterilen uyarı; diğerlerinde `null`.
  String? get warning => this == FatLossRate.one
      ? '1 kg/hafta agresif bir hızdır: kas kaybı, yorgunluk ve besin eksikliği '
          'riski artar. 2–4 haftadan uzun sürdürmeden önce doktora danış.'
      : null;
}

/// Hız modlarının sabitleri.
abstract final class FatLossRateRules {
  static const int kcalFloor = 1200;

  /// Kalori yetmezse protein kg × 1,6'ya kadar iner; her durumda en çok
  /// 220 g.
  static const double proteinMinPerKg = 1.6;
  static const int proteinMaxG = 220;
  static const double fatMinPerKg = 0.6;

  /// Protein indirimi de yetmezse yağın inebileceği alt sınır.
  static const double fatFloorPerKg = 0.5;
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
    required this.proteinReduced,
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

  /// Protein kg × 2'nin altına indi (kalori yetmedi ya da 220 g sınırı).
  final bool proteinReduced;

  /// Karbonhidrat 50 g'a yetsin diye yağ azaltıldı.
  final bool fatReduced;

  /// Bütün indirimlere rağmen karbonhidrat 50 g'ın altında kaldı.
  final bool carbsBelowMin;

  /// Klasik formül 1.200 kcal tabanının altında kalori veriyor.
  bool get classicBelowFloor =>
      rate == FatLossRate.classic && targets.kcal < FatLossRateRules.kcalFloor;

  /// Makro indirimlerinin açıklaması; indirim yoksa `null`.
  String? get macroNote {
    final parts = <String>[
      if (proteinReduced)
        'Kalori sınırlı olduğu için protein ${targets.proteinG} g\'a '
            'indirildi (kg × 2 yerine; en az kg × 1,6, en çok 220 g).',
      if (fatReduced)
        'Karbonhidrat en az 50 g kalsın diye yağ ${targets.fatG} g\'a '
            'azaltıldı.',
      if (carbsBelowMin)
        'Karbonhidrat 50 g\'ın altında kaldı; bu kaloriyle uzun süre devam '
            'etme.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }
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
      proteinReduced: false,
      fatReduced: false,
      carbsBelowMin: false,
    );
  }
  final raw = (expenditureKcal - r * FatLossRules.kcalPerKgFat / 7).round();
  final clamped = raw < floor;
  final kcal = clamped ? floor : raw;
  final macros = rateMacros(weightKg: weightKg, kcal: kcal);
  return FatLossRateResult(
    rate: rate,
    targets: macros.targets,
    floorKcal: floor,
    clampedToFloor: clamped,
    actualKgPerWeek: _weeklyKg(expenditureKcal, kcal),
    proteinReduced: macros.proteinReduced,
    fatReduced: macros.fatReduced,
    carbsBelowMin: macros.carbsBelowMin,
  );
}

double _weeklyKg(int expenditure, int kcal) {
  final deficit = expenditure - kcal;
  return deficit <= 0 ? 0 : deficit * 7 / FatLossRules.kcalPerKgFat;
}

/// Hız modu makroları. Başlangıç: protein = kg × 2 (en çok 220 g),
/// yağ = max(kg × 0,6, kcal × 0,25 / 9), lif = kcal / 1000 × 14,
/// karbonhidrat kalan. Karbonhidrat 50 g'a yetmezse sırasıyla:
/// yağ kg × 0,6'ya, protein kg × 1,6'ya, yağ kg × 0,5'e iner. Son çare
/// karbonhidrat 0 ve yağ kalan kaloriye sığdırılır; böylece
/// P×4 + Y×9 + K×4 ≤ kcal her zaman sağlanır.
({
  FatLossTargets targets,
  bool proteinReduced,
  bool fatReduced,
  bool carbsBelowMin,
}) rateMacros({
  required double weightKg,
  required int kcal,
}) {
  const carbsMin = FatLossRateRules.carbsMinG;
  final fullProtein = (weightKg * FatLossRules.proteinPerKg).floor();
  var protein = math.min(fullProtein, FatLossRateRules.proteinMaxG);
  final fatMin = (weightKg * FatLossRateRules.fatMinPerKg).ceil();
  final fatFloor = (weightKg * FatLossRateRules.fatFloorPerKg).ceil();
  final fatStart = math.max(
    fatMin,
    (kcal * FatLossRateRules.fatShareOfKcal / 9).floor(),
  );
  var fat = fatStart;
  int fatFits(int p) => ((kcal - p * 4 - carbsMin * 4) / 9).floor();
  bool short() => protein * 4 + fat * 9 + carbsMin * 4 > kcal;

  // 1) Yağı %25 payından kg × 0,6'ya doğru indir.
  if (short() && fat > fatMin) fat = math.max(fatMin, fatFits(protein));
  // 2) Proteini kg × 1,6'ya doğru indir.
  if (short()) {
    final pMin = math.min(
      (weightKg * FatLossRateRules.proteinMinPerKg).floor(),
      FatLossRateRules.proteinMaxG,
    );
    final need = ((kcal - fat * 9 - carbsMin * 4) / 4).floor();
    protein = math.max(pMin, math.min(protein, need));
  }
  // 3) Yağı kg × 0,5'e doğru indir.
  if (short() && fat > fatFloor) fat = math.max(fatFloor, fatFits(protein));
  // 4) Son çare: karbonhidrat 0, yağ ve gerekirse protein sığdırılır.
  if (protein * 4 + fat * 9 > kcal) {
    if (protein * 4 > kcal) protein = kcal ~/ 4;
    fat = math.max(0, (kcal - protein * 4) ~/ 9);
  }
  final rest = kcal - (protein * 4 + fat * 9);
  final carbs = rest <= 0 ? 0 : rest ~/ 4;
  return (
    targets: FatLossTargets(
      weightKg: weightKg,
      kcal: kcal,
      proteinG: protein,
      fatG: fat,
      fiberG: (kcal * FatLossRules.fiberPer1000Kcal / 1000).floor(),
      carbsG: carbs,
    ),
    proteinReduced: protein < fullProtein,
    fatReduced: fat < fatStart,
    carbsBelowMin: carbs < carbsMin,
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
  const RateInfo({required this.pros, required this.cons});

  final List<String> pros;
  final List<String> cons;
}

/// Seçeneğe özgü tek satır.
String rateOptionLine(FatLossRate rate) => switch (rate) {
      FatLossRate.classic =>
        'Sabit formül: harcamaya bağlı değil, her gün aynı hedef.',
      FatLossRate.half =>
        '0,50 kg/hafta: en yavaş seçenek; alışkanlık kalıcı olur.',
      FatLossRate.threeQuarter =>
        '0,75 kg/hafta: çoğu kişi için hız ve sürdürülebilirlik dengesi.',
      FatLossRate.one =>
        '1 kg/hafta: yüksek kilolularda başlangıçta uygun olabilir.',
    };

/// Kalori tabanına takılınca seçilen hız yerine gösterilen satır.
String rateClampLine(int floorKcal) =>
    'Hedef kalori ${formatTr(floorKcal)} kcal tabanına takıldı; seçilen hıza '
    'ulaşılamıyor, gerçek hız daha düşük.';

const Map<RateHealth, RateInfo> _healthInfo = {
  RateHealth.sustainable: RateInfo(
    pros: [
      'Kas kaybı en az.',
      'Açlık ve halsizlik az.',
      'Antrenman performansı korunur.',
    ],
    cons: [
      'Görünür ilerleme yavaş.',
      'Motivasyon düşebilir; uzun süre gerekir.',
    ],
  ),
  RateHealth.fast: RateInfo(
    pros: [
      'Görünür ilerleme daha hızlı.',
      'Kısa-orta vadede sürdürülebilir.',
    ],
    cons: [
      'Yüksek proteine ve uykuya daha çok dikkat gerekir.',
      'Bazı günler açlık hissi olabilir.',
    ],
  ),
  RateHealth.aggressive: RateInfo(
    pros: [
      'Hızlı sonuç.',
    ],
    cons: [
      'Kas kaybı riski artar.',
      'Yorgunluk, açlık ve sinirlilik.',
      'Besin eksikliği ve safra kesesi taşı riski.',
      'Uzun süre sürdürmek zor; 2–4 haftadan uzun sürdürmeden önce '
          'doktora danış.',
    ],
  ),
};

/// Metinler gerçek hızın sınıfına ([classifyRate]) göre seçilir; başa
/// seçeneğe özgü satır eklenir. Tabana takıldıysa bu, eksilerin başında
/// söylenir. Kayıp yoksa yalnızca seçenek satırı (ve taban satırı).
RateInfo rateInfo(FatLossRateResult result) {
  final option = rateOptionLine(result.rate);
  final kg = result.targets.weightKg;
  final clamp = [if (result.clampedToFloor) rateClampLine(result.floorKcal)];
  if (result.actualKgPerWeek <= 0) {
    return RateInfo(
      pros: [option],
      cons: clamp,
    );
  }
  final base = _healthInfo[classifyRate(result.actualKgPerWeek, kg)]!;
  return RateInfo(
    pros: [option, ...base.pros],
    cons: [...clamp, ...base.cons],
  );
}

/// Diyette günlük vitamin/mineral rehberi (genel yetişkin bilgisi).
class SupplementGuide {
  const SupplementGuide({
    required this.waterMl,
    required this.magnesiumText,
    required this.multivitaminHighlighted,
  });

  /// Günlük su: kg × 35 ml (50 ml'ye yuvarlı), en çok 4.000 ml.
  final int waterMl;

  /// Cinsiyete göre toplam magnezyum; bilinmiyorsa iki değer. Takviye
  /// sınırı [magnesiumSupplementText] ile ayrıca söylenir.
  final String magnesiumText;

  /// Takviye dozu ve üst sınır (yiyecekten bağımsız).
  static const String magnesiumSupplementText =
      'Takviye genelde 200–350 mg; takviyeden günde 350 mg\'ı aşma.';

  /// Kalori 1.500'ün altında: multivitamin özellikle önerilir.
  final bool multivitaminHighlighted;
}

abstract final class SupplementRules {
  static const int waterMlPerKg = 35;
  static const int waterMaxMl = 4000;
  static const int multivitaminKcalLimit = 1500;
}

SupplementGuide supplementGuide({
  required double weightKg,
  required Sex? sex,
  required int kcal,
}) {
  final water = math.min(
    (weightKg * SupplementRules.waterMlPerKg / 50).round() * 50,
    SupplementRules.waterMaxMl,
  );
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
