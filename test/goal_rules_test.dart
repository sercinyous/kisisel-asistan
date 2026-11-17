import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/goal_rules.dart';

void main() {
  group('GoalRules.stepsHit (%100)', () {
    test('tam hedef tutar, bir eksik tutmaz', () {
      expect(GoalRules.stepsHit(10000, 10000), isTrue);
      expect(GoalRules.stepsHit(9999, 10000), isFalse);
    });

    test('hedefin üstü tutar', () {
      expect(GoalRules.stepsHit(10001, 10000), isTrue);
      expect(GoalRules.stepsHit(25000, 10000), isTrue);
    });

    test('adım yoksa tutmaz', () {
      expect(GoalRules.stepsHit(0, 10000), isFalse);
    });
  });

  group('GoalRules.sleepHit (hedefin %90\'ı)', () {
    test('450 dk hedefte 405 tutar, 404 tutmaz', () {
      expect(GoalRules.sleepHit(405, 450), isTrue);
      expect(GoalRules.sleepHit(404, 450), isFalse);
    });

    test('hedefin üstü tutar', () {
      expect(GoalRules.sleepHit(450, 450), isTrue);
      expect(GoalRules.sleepHit(600, 450), isTrue);
    });

    test('kayan nokta yuvarlama hatası eşiği kaydırmaz', () {
      // 480 * 0.9 = 432 tam; 420 * 0.9 = 378 tam.
      expect(GoalRules.sleepHit(432, 480), isTrue);
      expect(GoalRules.sleepHit(431, 480), isFalse);
      expect(GoalRules.sleepHit(378, 420), isTrue);
      expect(GoalRules.sleepHit(377, 420), isFalse);
    });
  });

  group('GoalRules.caloriesHit (hedefin %85–%110\'u, uçlar dahil)', () {
    test('alt uç: 2000 hedefte 1700 tutar, 1699 tutmaz', () {
      expect(GoalRules.caloriesHit(1700, 2000), isTrue);
      expect(GoalRules.caloriesHit(1699, 2000), isFalse);
    });

    test('üst uç: 2200 tutar, 2201 tutmaz', () {
      expect(GoalRules.caloriesHit(2200, 2000), isTrue);
      expect(GoalRules.caloriesHit(2201, 2000), isFalse);
    });

    test('hedefin tam kendisi ve ara değerler tutar', () {
      expect(GoalRules.caloriesHit(2000, 2000), isTrue);
      expect(GoalRules.caloriesHit(1850.5, 2000), isTrue);
    });

    test('ondalıklı sınır aşımı tutmaz', () {
      expect(GoalRules.caloriesHit(1699.9, 2000), isFalse);
      expect(GoalRules.caloriesHit(2200.4, 2000), isFalse);
    });

    test('0 kcal tutmaz', () {
      expect(GoalRules.caloriesHit(0, 2000), isFalse);
    });

    test('1 ondalıklı satırların double toplamı tam sınırda doğru yanda kalır',
        () {
      // Tam 1870.0 (= 2200'ün %85'i); double toplamı 1869.9999999999998.
      final sum = 333.9 + 663.9 + 271.9 + 481.0 + 119.3;
      expect(sum, isNot(1870.0), reason: 'kayan nokta artığı bu testin sebebi');
      expect(GoalRules.caloriesHit(sum, 2200), isTrue);
    });

    test('tek değerde tam %110 sınırı: 1027.4 kcal, hedef 934', () {
      expect(GoalRules.caloriesHit(1027.4, 934), isTrue);
      expect(GoalRules.caloriesHit(1027.5, 934), isFalse);
    });

    test('devasa sonlu değer atmaz, tutmaz (veritabanında yazılamaz)', () {
      expect(GoalRules.caloriesHit(1e300, 2000), isFalse);
      expect(GoalRules.caloriesHit(-1e300, 2000), isFalse);
    });
  });

  group('GoalRules.proteinHit (≥ %90)', () {
    test('170 g hedefte 153 tutar, 152 tutmaz', () {
      expect(GoalRules.proteinHit(153, 170), isTrue);
      expect(GoalRules.proteinHit(152, 170), isFalse);
    });

    test('hedefin üstü tutar; ondalıklı eksik tutmaz', () {
      expect(GoalRules.proteinHit(170, 170), isTrue);
      expect(GoalRules.proteinHit(200, 170), isTrue);
      expect(GoalRules.proteinHit(152.9, 170), isFalse);
    });

    test('tek değerde tam %90 sınırı: 18.9 g, hedef 21', () {
      expect(GoalRules.proteinHit(18.9, 21), isTrue);
      expect(GoalRules.proteinHit(18.8, 21), isFalse);
    });

    test('1 ondalıklı satırların double toplamı tam sınırda doğru yanda kalır',
        () {
      // Tam 153.0 (= 170'in %90'ı); double toplamı sınırın altına düşer.
      final sum = 50.1 + 50.1 + 52.8;
      expect(GoalRules.proteinHit(sum, 170), isTrue);
    });

    test('devasa sonlu değer atmaz, tutmaz (veritabanında yazılamaz)', () {
      expect(GoalRules.proteinHit(1e300, 170), isFalse);
      expect(GoalRules.proteinHit(-1e300, 170), isFalse);
    });
  });

  group('GoalRules geçersiz girdi', () {
    test('hedef sıfır ya da negatifken hiçbir kural tutmaz (sahte övgü yok)', () {
      expect(GoalRules.stepsHit(5000, 0), isFalse);
      expect(GoalRules.sleepHit(480, 0), isFalse);
      expect(GoalRules.caloriesHit(0, 0), isFalse);
      expect(GoalRules.caloriesHit(2000, -1), isFalse);
      expect(GoalRules.proteinHit(100, 0), isFalse);
    });

    test('NaN ve sonsuz değerler tutmaz', () {
      expect(GoalRules.caloriesHit(double.nan, 2000), isFalse);
      expect(GoalRules.caloriesHit(double.infinity, 2000), isFalse);
      expect(GoalRules.proteinHit(double.nan, 170), isFalse);
    });
  });

  group('TrendMetric', () {
    test('üç metrik, sıra adım - uyku - kalori', () {
      expect(TrendMetric.values, [
        TrendMetric.steps,
        TrendMetric.sleep,
        TrendMetric.calories,
      ]);
    });
  });
}
