import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/presentation/health_format.dart';

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('parseDecimal', () {
    test('virgül ve noktayı ondalık ayırıcı kabul eder', () {
      expect(parseDecimal('83,6'), 83.6);
      expect(parseDecimal(' 83.6 '), 83.6);
      expect(parseDecimal('420'), 420);
    });

    test('boş ya da sayı olmayan metin null döner', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal(null), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('1,2,3'), isNull);
      expect(parseDecimal('NaN'), isNull);
      expect(parseDecimal('Infinity'), isNull);
    });

    test('ondalık basamak sayısına yuvarlar', () {
      expect(parseDecimal('83,456', decimals: 2), 83.46);
      expect(parseDecimal('12,34', decimals: 1), 12.3);
    });
  });

  group('validateDecimal', () {
    test('kilo sınırları dahildir, dışı reddedilir', () {
      String? check(String v) => validateDecimal(
            v,
            min: WeightLimits.minKg,
            max: WeightLimits.maxKg,
            required: true,
            decimals: 2,
          );
      expect(check('30'), isNull);
      expect(check('250'), isNull);
      expect(check('29,9'), '30 ile 250 arasında olmalı.');
      expect(check('250,1'), '30 ile 250 arasında olmalı.');
    });

    test('zorunlu alan boşsa ve sayı değilse ayrı mesaj verir', () {
      expect(
        validateDecimal('', min: 0, max: 10, required: true),
        'Bu alan boş olamaz.',
      );
      expect(validateDecimal('x', min: 0, max: 10), 'Geçerli bir sayı gir.');
    });

    test('isteğe bağlı alan boş bırakılabilir', () {
      expect(validateDecimal('', min: 0, max: 10), isNull);
      expect(validateDecimal(null, min: 0, max: 10), isNull);
    });

    test('negatif ve üst sınırı aşan makro reddedilir', () {
      String? check(String v) =>
          validateDecimal(v, min: 0, max: NutritionLog.macroMax);
      expect(check('-1'), '0 ile 9999,9 arasında olmalı.');
      expect(check('10000'), '0 ile 9999,9 arasında olmalı.');
      expect(check('9999,9'), isNull);
    });
  });

  group('validateInteger', () {
    test('süre 1..600 dışında reddedilir', () {
      String? check(String v) => validateInteger(
            v,
            min: WorkoutLog.durationMinMin,
            max: WorkoutLog.durationMinMax,
          );
      expect(check('1'), isNull);
      expect(check('600'), isNull);
      expect(check('0'), '1 ile 600 arasında olmalı.');
      expect(check('601'), '1 ile 600 arasında olmalı.');
      expect(check(''), isNull);
    });

    test('ondalıklı ya da sayı olmayan değer tam sayı değildir', () {
      expect(validateInteger('12,5', min: 1, max: 600), 'Tam sayı gir.');
      expect(validateInteger('on', min: 1, max: 600), 'Tam sayı gir.');
    });
  });

  group('validateFoodName', () {
    test('boş ad ve 200 karakteri aşan ad reddedilir', () {
      expect(validateFoodName('  '), 'Ad boş olamaz.');
      expect(validateFoodName('a' * 200), isNull);
      expect(validateFoodName('a' * 201), 'En fazla 200 karakter.');
    });
  });

  group('WeightTrend', () {
    final now = DateTime(2026, 11, 16, 12);
    WeightEntry entry(double kg, DateTime at) =>
        WeightEntry(id: '$at', weightKg: kg, loggedAt: at);

    test('ölçüm yoksa null', () {
      expect(
        WeightTrend.from(const [], startKg: 84.5, targetKg: 78, now: now),
        isNull,
      );
    });

    test('bu ay değişimi ay öncesindeki son ölçüme göre hesaplanır', () {
      final trend = WeightTrend.from(
        [
          entry(85.0, DateTime(2026, 10, 20)),
          entry(84.5, DateTime(2026, 10, 30)),
          entry(84.2, DateTime(2026, 11, 3)),
          entry(83.6, DateTime(2026, 11, 15)),
        ],
        startKg: 84.5,
        targetKg: 78,
        now: now,
      )!;
      expect(trend.latestKg, 83.6);
      expect(trend.firstKg, 85.0);
      expect(trend.monthChangeKg, closeTo(-0.9, 1e-9));
      expect(trend.remainingKg, closeTo(5.6, 1e-9));
      expect(trend.reached, isFalse);
    });

    test('ay öncesi ölçüm yoksa ayın ilk ölçümü taban alınır', () {
      final trend = WeightTrend.from(
        [
          entry(84.0, DateTime(2026, 11, 2)),
          entry(83.0, DateTime(2026, 11, 14)),
        ],
        startKg: 84.5,
        targetKg: 78,
        now: now,
      )!;
      expect(trend.monthChangeKg, closeTo(-1.0, 1e-9));
    });

    test('bu ay ölçüm yoksa ya da tek ölçüm varsa aylık değişim null', () {
      final onlyOld = WeightTrend.from(
        [entry(84.0, DateTime(2026, 10, 28))],
        startKg: 84.5,
        targetKg: 78,
        now: now,
      )!;
      expect(onlyOld.monthChangeKg, isNull);

      final single = WeightTrend.from(
        [entry(84.0, DateTime(2026, 11, 5))],
        startKg: 84.5,
        targetKg: 78,
        now: now,
      )!;
      expect(single.monthChangeKg, isNull);
    });

    test('hedefe ulaşma kilo verme ve alma yönünde doğru çalışır', () {
      final lose = WeightTrend.from(
        [entry(77.8, DateTime(2026, 11, 5))],
        startKg: 84.5,
        targetKg: 78,
        now: now,
      )!;
      expect(lose.reached, isTrue);

      final gain = WeightTrend.from(
        [entry(68, DateTime(2026, 11, 5))],
        startKg: 65,
        targetKg: 70,
        now: now,
      )!;
      expect(gain.reached, isFalse);
      expect(gain.remainingKg, closeTo(2, 1e-9));
    });
  });

  group('groupMeals', () {
    NutritionLog log(String id, String meal, double kcal, double protein) =>
        NutritionLog(
          id: id,
          foodName: id,
          mealType: meal,
          calories: kcal,
          proteinG: protein,
          eatenAt: DateTime(2026, 11, 16, 8),
        );

    test('üç ana öğün her zaman, ara öğün yalnızca kayıt varsa listelenir', () {
      final empty = groupMeals(const []);
      expect(empty.map((g) => g.mealType), ['breakfast', 'lunch', 'dinner']);
      expect(empty.every((g) => g.logs.isEmpty), isTrue);

      final withSnack = groupMeals([log('a', 'snack', 100, 5)]);
      expect(
        withSnack.map((g) => g.mealType),
        ['breakfast', 'lunch', 'dinner', 'snack'],
      );
    });

    test('öğün toplamları hesaplanır; bilinmeyen tür ara öğüne düşer', () {
      final groups = groupMeals([
        log('yulaf', 'breakfast', 300, 12),
        log('yumurta', 'breakfast', 120, 16),
        log('gizemli', 'brunch', 50, 1),
      ]);
      final breakfast = groups.first;
      expect(breakfast.logs.map((l) => l.id), ['yulaf', 'yumurta']);
      expect(breakfast.calories, 420);
      expect(breakfast.proteinG, 28);
      expect(groups.last.mealType, 'snack');
      expect(groups.last.logs.single.id, 'gizemli');
    });
  });

  group('HealthFormat', () {
    test('etiketler Türkçedir', () {
      expect(HealthFormat.mealLabel('breakfast'), 'Kahvaltı');
      expect(HealthFormat.mealLabel('snack'), 'Ara öğün');
      expect(HealthFormat.workoutLabel('weights'), 'Ağırlık antrenmanı');
      expect(HealthFormat.workoutLabel('football'), 'Halı saha');
      expect(HealthFormat.workoutLabel('bilinmeyen'), 'Diğer');
    });

    test('sayılar gereksiz ondalık olmadan yazılır', () {
      expect(HealthFormat.kcal(420), '420 kcal');
      expect(HealthFormat.kcal(1960.4), '1.960 kcal');
      expect(HealthFormat.grams(28), '28 g');
      expect(HealthFormat.grams(27.5), '27,5 g');
      expect(HealthFormat.kg(78), '78,0');
      expect(HealthFormat.kg(83.64), '83,6');
      expect(HealthFormat.plain(5), '5');
      expect(HealthFormat.plain(5.25), '5,25');
    });

    test('antrenman başlığı boşsa tür etiketi kullanılır', () {
      final base = WorkoutLog(
        id: 'w',
        loggedAt: DateTime(2026, 11, 16, 19, 30),
        workoutType: 'kickboxing',
      );
      expect(HealthFormat.workoutTitle(base), 'Kickboks');
      expect(
        HealthFormat.workoutTitle(base.copyWith(title: '  ')),
        'Kickboks',
      );
      expect(
        HealthFormat.workoutTitle(base.copyWith(title: 'Sparring')),
        'Sparring',
      );
    });

    test('antrenman ayrıntısı zaman, süre ve mesafeyi birleştirir', () {
      final now = DateTime(2026, 11, 16, 21);
      final w = WorkoutLog(
        id: 'w',
        loggedAt: DateTime(2026, 11, 16, 19, 30),
        workoutType: 'running',
        durationMin: 60,
        distanceKm: 5.2,
      );
      expect(
        HealthFormat.workoutDetail(w, now: now),
        'Bugün 19:30 · 60 dk · 5,2 km',
      );
      expect(
        HealthFormat.workoutDetail(
          w.copyWith(clearDurationMin: true, clearDistanceKm: true),
          now: now,
        ),
        'Bugün 19:30',
      );
    });
  });
}
