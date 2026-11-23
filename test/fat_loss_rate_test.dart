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

    test('yağ zaten tabandaysa azaltılmaz, not düşülür', () {
      // 80 kg, 1200 kcal: P 160, Y max(48, 33) = 48 → karb 32.
      final m = rateMacros(weightKg: 80, kcal: 1200);
      expect(m.targets.fatG, 48);
      expect(m.fatReduced, isFalse);
      expect(m.carbsBelowMin, isTrue);
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

  test('1 kg bilgisinde su notu ve doktor uyarısı', () {
    final i = rateInfo(FatLossRate.one);
    expect(i.note, rateWaterNote);
    expect(i.cons.any((c) => c.contains('doktora danış')), isTrue);
  });

  group('supplementGuide', () {
    test('su kg×35, cinsiyete göre magnezyum', () {
      final m = supplementGuide(weightKg: 84, sex: Sex.male, kcal: 2000);
      expect(m.waterMl, 2950);
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
