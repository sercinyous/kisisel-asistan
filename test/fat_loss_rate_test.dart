import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_plan.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_rate.dart';
import 'package:kisisel_asistan/features/health/domain/safe_targets.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

/// [height] cm, 36 yaş erkek; harcama elle [e]; hedef kilo [kg] − 10
/// (kilitsiz kalsın diye VKİ 18,5 üstü seçilir).
ResolvedTargets _rate(double kg, int e, FatLossRate rate,
        {int height = 180, double? target}) =>
    resolveTargets(
      settings: const UserSettings.defaults().copyWith(
        weeklyRate: rate,
        expenditureKcalManual: e,
        startWeightKg: kg,
        targetWeightKg: target ?? kg - 10,
        heightCm: height,
      ),
      latestWeightKg: kg,
      age: 36,
      sex: Sex.male,
    );

void main() {
  group('tek motor (resolveTargets) hız sonuçları', () {
    test('84 kg, harcama 3000: hızlara göre kalori ve gerçek hız', () {
      expect(_rate(84, 3000, FatLossRate.half).kcal, 2450);
      expect(_rate(84, 3000, FatLossRate.threeQuarter).kcal, 2175);
      expect(_rate(84, 3000, FatLossRate.threeQuarter).clamped, isFalse);
      expect(_rate(84, 3000, FatLossRate.half).kgPerWeek, closeTo(0.5, 1e-9));
    });

    test('klasik kg × 26 ile birebir aynı', () {
      final c = _rate(84, 3000, FatLossRate.classic);
      final e = computeFatLossTargets(84);
      expect([c.kcal, c.proteinG, c.fatG, c.carbsG, c.fiberG],
          [e.kcal, e.proteinG, e.fatG, e.carbsG, e.fiberG]);
    });

    test('değişmez: makro kalorisi hedefi aşmaz, karb ≥ 0', () {
      for (final kg in [40.0, 60.0, 84.0, 120.0, 160.0, 200.0]) {
        for (final e in [1300, 1900, 2500, 3500, 4500]) {
          for (final rate in FatLossRate.values) {
            final r = _rate(kg, e, rate);
            final why = '$kg kg, $e, ${rate.name}';
            expect(r.proteinG * 4 + r.fatG * 9 + r.carbsG * 4,
                lessThanOrEqualTo(r.kcal),
                reason: why);
            expect(r.carbsG, greaterThanOrEqualTo(0), reason: why);
            expect(r.proteinG, lessThanOrEqualTo(SafeTargets.proteinMaxG),
                reason: why);
          }
        }
      }
    });

    test('klasik taban altına inmez (kırpılır)', () {
      // 45 kg, 150 cm, hedef 43: 45 × 26 = 1.170 < 1.200 → 1.200.
      final low = _rate(45, 3000, FatLossRate.classic, height: 150, target: 43);
      expect(low.kcal, greaterThanOrEqualTo(1200));
      expect(low.clamped, isTrue);
      expect(low.asRateResult.classicBelowFloor, isFalse);
      expect(_rate(84, 3000, FatLossRate.classic).asRateResult.classicBelowFloor,
          isFalse);
    });
  });

  group('classifyRate', () {
    test('84 kg: 0,5 sürdürülebilir, 0,75 hızlı, 1 agresif', () {
      expect(classifyRate(0.5, 84), RateHealth.sustainable);
      expect(classifyRate(0.75, 84), RateHealth.fast);
      expect(classifyRate(1.0, 84), RateHealth.aggressive);
    });

    test('120 kg: 0,75 sürdürülebilir, 1 hızlı', () {
      expect(classifyRate(0.75, 120), RateHealth.sustainable);
      expect(classifyRate(1.0, 120), RateHealth.fast);
    });

    test('sınırlar: %0,7 ve %1,0 dahil', () {
      expect(classifyRate(0.7, 100), RateHealth.sustainable);
      expect(classifyRate(1.0, 100), RateHealth.fast);
      expect(classifyRate(1.01, 100), RateHealth.aggressive);
      expect(ratePercentOfBodyWeight(0.5, 50), closeTo(1.0, 1e-9));
    });
  });

  test('FatLossRate.parse tanınmayanı klasiğe düşürür', () {
    expect(FatLossRate.parse('one'), FatLossRate.threeQuarter);
    expect(FatLossRate.parse('1.0'), FatLossRate.threeQuarter);
    expect(FatLossRate.parse('x'), FatLossRate.classic);
    expect(FatLossRate.parse(null), FatLossRate.classic);
  });

  test('artılar/eksiler gerçek hızın sınıfına göre', () {
    // 50 kg, 3000: 0,75 kg agresif; 90 kg'da (harcama 3300) 0,75 kg hızlı.
    final agg =
        rateInfo(_rate(50, 3000, FatLossRate.threeQuarter,
                height: 155, target: 47)
            .asRateResult);
    expect(agg.pros.first, rateOptionLine(FatLossRate.threeQuarter));
    expect(agg.cons.any((c) => c.contains('doktora danış')), isTrue);
    final fast =
        rateInfo(_rate(90, 3300, FatLossRate.threeQuarter).asRateResult);
    expect(fast.cons.any((c) => c.contains('doktora danış')), isFalse);
    expect(fast.cons, contains('Bazı günler açlık hissi olabilir.'));
    // 60 kg, 160 cm, 1800, 0,75 kg: tabana (bazal 1.425) takılır.
    final clampedTargets =
        _rate(60, 1800, FatLossRate.threeQuarter, height: 160);
    expect(clampedTargets.clamped, isTrue);
    final clamped = rateInfo(clampedTargets.asRateResult);
    expect(clamped.cons.first, rateClampLine(clampedTargets.floorKcal));
  });

  group('supplementGuide', () {
    test('su kg×35, cinsiyete göre magnezyum', () {
      final m = supplementGuide(weightKg: 84, sex: Sex.male, kcal: 2000);
      expect(m.waterMl, 2950);
      expect(supplementGuide(weightKg: 150, sex: null, kcal: 2000).waterMl,
          4000);
      expect(m.magnesiumText, contains('Erkek: 400–420'));
      expect(m.multivitaminHighlighted, isFalse);
      final f = supplementGuide(weightKg: 60, sex: Sex.female, kcal: 1400);
      expect(f.magnesiumText, contains('Kadın: 310–320'));
      expect(f.multivitaminHighlighted, isTrue);
      final u = supplementGuide(weightKg: 60, sex: null, kcal: 1500);
      expect(u.magnesiumText, allOf(contains('310–320'), contains('400–420')));
      expect(u.multivitaminHighlighted, isFalse);
    });
  });
}
