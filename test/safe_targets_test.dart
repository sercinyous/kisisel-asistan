import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/safe_targets.dart';

void main() {
  group('taban ve açık sınırı', () {
    test('taban max(1200, bazal)', () {
      expect(kcalFloor(null), 1200);
      expect(kcalFloor(1100), 1200);
      expect(kcalFloor(1650.4), 1650);
      expect(kcalFloor(double.nan), 1200);
    });

    test('açık sınırı min(%25 harcama, 1000)', () {
      expect(deficitCap(2000), 500);
      expect(deficitCap(3000), 750);
      expect(deficitCap(5000), 1000);
    });
  });

  group('plan kilidi', () {
    test('18 yaş altı kilitli', () {
      expect(
          planLocked(age: 17, weightKg: 90, targetWeightKg: 80, heightCm: 180),
          isTrue);
      expect(
          planLocked(age: 18, weightKg: 90, targetWeightKg: 80, heightCm: 180),
          isFalse);
    });

    test('şimdiki ya da hedef VKİ 18,5 altı kilitli', () {
      // 180 cm: 18,5 VKİ = 59,9 kg.
      expect(
          planLocked(age: 30, weightKg: 59, targetWeightKg: 55, heightCm: 180),
          isTrue);
      expect(
          planLocked(age: 30, weightKg: 70, targetWeightKg: 58, heightCm: 180),
          isTrue);
      expect(
          planLocked(age: 30, weightKg: 70, targetWeightKg: 62, heightCm: 180),
          isFalse);
    });

    test('boy bilinmiyorsa VKİ kuralı uygulanmaz', () {
      expect(
          planLocked(age: 30, weightKg: 50, targetWeightKg: 45, heightCm: null),
          isFalse);
    });
  });

  group('fitMacros', () {
    test('sığıyorsa dokunmaz, karbonhidrat kalan', () {
      final m = fitMacros(weightKg: 84, kcal: 2184, proteinG: 168, fatG: 72);
      expect(m.proteinG, 168);
      expect(m.fatG, 72);
      expect(m.carbsG, (2184 - 168 * 4 - 72 * 9) ~/ 4);
      expect(m.fiberG, 30);
      expect(m.proteinReduced, isFalse);
    });

    test('protein en çok 220 g', () {
      final m = fitMacros(weightKg: 150, kcal: 3500, proteinG: 300, fatG: 90);
      expect(m.proteinG, 220);
      expect(m.proteinReduced, isTrue);
    });

    test('kalori yetmezse önce protein kg × 1,6, sonra yağ kg × 0,5', () {
      // 100 kg, 1200 kcal: P 200×4 + Y 90×9 = 1610 > 1200.
      final m = fitMacros(weightKg: 100, kcal: 1200, proteinG: 200, fatG: 90);
      expect(m.proteinG, 160);
      expect(m.fatG, 62);
      expect(m.kcal, lessThanOrEqualTo(1200));
      expect(m.carbsG, greaterThanOrEqualTo(0));
    });

    test('hiçbir girdide toplam kcal\'ı aşmaz', () {
      for (final kg in [40.0, 60.0, 84.0, 120.0, 180.0, 250.0]) {
        for (final kcal in [800, 1000, 1200, 1500, 2000, 3000]) {
          final m = fitMacros(
              weightKg: kg,
              kcal: kcal,
              proteinG: (kg * 2).floor(),
              fatG: (kg * 0.6).ceil());
          expect(m.kcal, lessThanOrEqualTo(kcal), reason: '$kg kg $kcal');
          expect(m.carbsG, greaterThanOrEqualTo(0));
          expect(m.proteinG, lessThanOrEqualTo(220));
        }
      }
    });
  });

  test('su min(kg × 35, 4000), 50 ml yuvarlı', () {
    expect(recommendedWaterMl(84), 2950);
    expect(recommendedWaterMl(150), 4000);
  });

  test('elle harcama ±%30 dışında uyarı', () {
    expect(manualExpenditureOutOfRange(manualKcal: 2600, estimateKcal: 2500),
        isFalse);
    expect(manualExpenditureOutOfRange(manualKcal: 3300, estimateKcal: 2500),
        isTrue);
    expect(manualExpenditureOutOfRange(manualKcal: 1700, estimateKcal: 2500),
        isTrue);
  });

  group('AI filtresi', () {
    const floor = 1500;
    test('güvenli metin değişmez', () {
      const text = 'Bu hafta proteini artır. Günde 8.000 adım hedefle.';
      expect(filterAiHealthAdvice(text, floorKcal: floor), text);
    });

    test('taban altı kalori, oruç ve hızlı kayıp cümlesi değiştirilir', () {
      const text = 'Harika gidiyorsun. Günde 1.000 kcal ye. '
          'Aralıklı oruç dene. Haftada 1,5 kg ver.';
      final out = filterAiHealthAdvice(text, floorKcal: floor);
      expect(out, startsWith('Harika gidiyorsun.'));
      expect(out, contains(aiSafeSentence(floor)));
      expect(out, isNot(contains('1.000 kcal')));
      expect(out, isNot(contains('oruç')));
      expect(aiSafeSentence(floor).allMatches(out).length, 1);
    });

    test('açık sayısı taban altı olsa da yemek önerisi değilse kalır', () {
      const text = 'Bu hafta 900 kcal açık verdin.';
      expect(filterAiHealthAdvice(text, floorKcal: floor), text);
    });

    test('bağlam talimatı sınırları içerir', () {
      const c = AiHealthContext(
        kcalTarget: 1900,
        proteinG: 150,
        floorKcal: 1500,
        deficitCapKcal: 700,
        weekDeficitKcal: 2850,
        weekTargetKcal: 3850,
        streakLine: 'Adım 7 · Kayıt 12 · Açık 4',
      );
      expect(c.prompt, contains('en az 1500 kcal'));
      expect(c.prompt, contains('0,75 kg'));
      expect(c.prompt, contains('oruç'));
      expect(c.prompt, contains('Adım 7'));
    });
  });
}
