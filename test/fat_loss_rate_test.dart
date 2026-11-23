import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_plan.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_rate.dart';

void main() {
  group('computeRateTargets', () {
    FatLossRateResult r84(FatLossRate rate) => computeRateTargets(
        weightKg: 84, expenditureKcal: 3000, rate: rate);

    test('84 kg, harcama 3000: hızlara göre kalori', () {
      expect(r84(FatLossRate.half).targets.kcal, 2450);
      expect(r84(FatLossRate.threeQuarter).targets.kcal, 2175);
      expect(r84(FatLossRate.one).targets.kcal, 1900);
      expect(r84(FatLossRate.one).clampedToFloor, isFalse);
      expect(r84(FatLossRate.half).actualKgPerWeek, closeTo(0.5, 1e-9));
    });

    test('klasik mevcut formülle birebir aynı', () {
      final c = r84(FatLossRate.classic).targets;
      final e = computeFatLossTargets(84);
      expect([c.kcal, c.proteinG, c.fatG, c.carbsG, c.fiberG],
          [e.kcal, e.proteinG, e.fatG, e.carbsG, e.fiberG]);
      expect(c.kcal, 2184);
    });

    test('60 kg, harcama 1900, 1 kg: 1200 tabanı ve gerçek hız', () {
      final r = computeRateTargets(
          weightKg: 60, expenditureKcal: 1900, rate: FatLossRate.one);
      expect(r.targets.kcal, 1200);
      expect(r.clampedToFloor, isTrue);
      expect(r.actualKgPerWeek, closeTo(700 * 7 / 7700, 1e-9));
    });

    test('bazal 1200 üstündeyse taban bazaldır', () {
      final r = computeRateTargets(
          weightKg: 84,
          expenditureKcal: 2400,
          rate: FatLossRate.one,
          basalKcal: 1780.4);
      expect(r.floorKcal, 1780);
      expect(r.targets.kcal, 1780);
      expect(r.clampedToFloor, isTrue);
    });

    test('makrolar: protein kg×2, yağ max(kg×0,6, %25), lif, karb kalan', () {
      final t = r84(FatLossRate.half).targets;
      expect(t.proteinG, 168);
      expect(t.fatG, 68); // 2450 × 0,25 / 9 = 68,05 > 50,4
      expect(t.fiberG, 34);
      expect(t.carbsG, (2450 - 168 * 4 - 68 * 9) ~/ 4);
    });

    test('yağ tabanı kg×0,6', () {
      final m = rateMacros(weightKg: 100, kcal: 1600);
      expect(m.targets.fatG, 60); // 1600×0,25/9 = 44 < 60
    });
  });

  group('karbonhidrat ≥ 50 g', () {
    test('yağ %25 payındayken tabana (kg×0,6) doğru azaltılır', () {
      // 16 kg, 420 kcal: P 32, Y max(10, 11) = 11 → karb 48 < 50;
      // yağ 1 g azalır → 10 → karb 50.
      final m = rateMacros(weightKg: 16, kcal: 420);
      expect(m.fatReduced, isTrue);
      expect(m.targets.fatG, 10);
      expect(m.targets.carbsG, 50);
      expect(m.carbsBelowMin, isFalse);
    });

    test('yağ tabandaysa protein kg×1,6\'ya doğru iner', () {
      // 80 kg, 1200 kcal: P 160, Y 48 → karb 32; protein 142'ye iner.
      final m = rateMacros(weightKg: 80, kcal: 1200);
      expect(m.targets.fatG, 48);
      expect(m.targets.proteinG, 142);
      expect(m.targets.carbsG, 50);
      expect(m.proteinReduced, isTrue);
      expect(m.fatReduced, isFalse);
      expect(m.carbsBelowMin, isFalse);
    });

    test('protein kg×1,6 da yetmezse yağ kg×0,5\'e iner', () {
      // 100 kg, 1200 kcal: P 160 (kg×1,6), Y 60 → 50 (kg×0,5).
      final m = rateMacros(weightKg: 100, kcal: 1200);
      expect(m.targets.proteinG, 160);
      expect(m.targets.fatG, 50);
      expect(m.fatReduced, isTrue);
      expect(m.carbsBelowMin, isTrue);
      final t = m.targets;
      expect(t.proteinG * 4 + t.fatG * 9 + t.carbsG * 4,
          lessThanOrEqualTo(1200));
    });

    test('protein en çok 220 g', () {
      final m = rateMacros(weightKg: 150, kcal: 4000);
      expect(m.targets.proteinG, 220);
      expect(m.proteinReduced, isTrue);
    });

    test('değişmez: makro kalorisi hedefi aşmaz, karb ≥ 0', () {
      for (var kg = 30; kg <= 300; kg += 5) {
        for (var e = 1200; e <= 6000; e += 100) {
          for (final rate in FatLossRate.values) {
            final r = computeRateTargets(
                weightKg: kg.toDouble(), expenditureKcal: e, rate: rate);
            final t = r.targets;
            final sum = t.proteinG * 4 + t.fatG * 9 + t.carbsG * 4;
            final why = '$kg kg, $e kcal, ${rate.name}';
            expect(t.carbsG, greaterThanOrEqualTo(0), reason: why);
            expect(t.proteinG, greaterThanOrEqualTo(0), reason: why);
            expect(t.fatG, greaterThanOrEqualTo(0), reason: why);
            if (rate != FatLossRate.classic) {
              expect(sum, lessThanOrEqualTo(t.kcal + 5), reason: why);
              expect(t.proteinG, lessThanOrEqualTo(220), reason: why);
              expect(t.kcal, greaterThanOrEqualTo(1200), reason: why);
            }
          }
        }
      }
    });

    test('harcama tabanın altında: kayıp yok, not ≈0,00 değil', () {
      final r = computeRateTargets(
          weightKg: 70, expenditureKcal: 1200, rate: FatLossRate.half);
      expect(r.clampedToFloor, isTrue);
      expect(r.actualKgPerWeek, 0);
      final i = rateInfo(r);
      expect(i.cons.first, rateClampLine(1200));
      expect(i.pros, [rateOptionLine(FatLossRate.half)]);
    });

    test('ağır kilo: 150 kg, 3000, 1 kg', () {
      final r = computeRateTargets(
          weightKg: 150, expenditureKcal: 3000, rate: FatLossRate.one);
      final t = r.targets;
      expect(t.kcal, 1900);
      expect(t.proteinG, 220);
      expect(t.fatG, 90);
      expect(t.carbsG, 52);
      expect(r.macroNote, contains('protein 220 g'));
    });

    test('klasik taban altı bayrağı', () {
      final r = computeRateTargets(
          weightKg: 40, expenditureKcal: 2000, rate: FatLossRate.classic);
      expect(r.targets.kcal, 1040);
      expect(r.classicBelowFloor, isTrue);
      expect(
          computeRateTargets(
                  weightKg: 84, expenditureKcal: 2000, rate: FatLossRate.classic)
              .classicBelowFloor,
          isFalse);
    });

    test('yeterli kaloride dokunulmaz', () {
      final m = rateMacros(weightKg: 40, kcal: 1300);
      expect(m.fatReduced, isFalse);
      expect(m.carbsBelowMin, isFalse);
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
    expect(FatLossRate.parse('one'), FatLossRate.one);
    expect(FatLossRate.parse('x'), FatLossRate.classic);
    expect(FatLossRate.parse(null), FatLossRate.classic);
  });

  test('artılar/eksiler gerçek hızın sınıfına göre', () {
    // 84 kg, 3000: 1 kg agresif; 120 kg'da 1 kg hızlı.
    final agg = rateInfo(computeRateTargets(
        weightKg: 84, expenditureKcal: 3000, rate: FatLossRate.one));
    expect(agg.pros.first, rateOptionLine(FatLossRate.one));
    expect(agg.cons.any((c) => c.contains('doktora danış')), isTrue);
    final fast = rateInfo(computeRateTargets(
        weightKg: 120, expenditureKcal: 3000, rate: FatLossRate.one));
    expect(fast.cons.any((c) => c.contains('doktora danış')), isFalse);
    expect(fast.cons, contains('Bazı günler açlık hissi olabilir.'));
    // 60 kg, 1900, 1 kg: tabana takılır, gerçek ≈0,64 → agresif değil hızlı.
    final clamped = rateInfo(computeRateTargets(
        weightKg: 60, expenditureKcal: 1900, rate: FatLossRate.one));
    expect(clamped.cons.first, rateClampLine(1200));
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
