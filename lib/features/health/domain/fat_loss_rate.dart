import 'dart:math' as math;

import 'energy_balance.dart' show Sex;
import 'fat_loss_plan.dart';
import 'safe_targets.dart';

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

/// Hız değerlendirmesinin sabitleri. Hedef sayıları tek motordan
/// (`resolveTargets`, sınırlar `SafeTargets`) gelir.
abstract final class FatLossRateRules {
  /// Bunun altındaki karbonhidrat "uzun süre devam etme" notu verir.
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
      rate == FatLossRate.classic && targets.kcal < SafeTargets.kcalFloorMin;

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
  /// sınırı [magnesiumSupplementText] ile ayrıca söylenir (tek kaynak).
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
