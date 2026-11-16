import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';

void main() {
  group('NutritionLog', () {
    test('fromMap: sütunlar bire bir; numeric int de gelebilir', () {
      final log = NutritionLog.fromMap(const {
        'id': 'n1',
        'meal_type': 'lunch',
        'food_name': 'Tavuk göğsü',
        'quantity_text': '200 gr',
        'calories': 330,
        'protein_g': 62.5,
        'carbs_g': 0,
        'fat_g': 7.2,
        'eaten_at': '2026-11-16T10:05:00+00:00',
        'source': 'ai',
      });
      expect(log.id, 'n1');
      expect(log.mealType, 'lunch');
      expect(log.foodName, 'Tavuk göğsü');
      expect(log.quantityText, '200 gr');
      expect(log.calories, 330.0);
      expect(log.proteinG, 62.5);
      expect(log.carbsG, 0.0);
      expect(log.fatG, 7.2);
      expect(log.eatenAt.isUtc, isFalse);
      expect(log.eatenAt.toUtc(), DateTime.utc(2026, 11, 16, 10, 5));
      expect(log.source, 'ai');
    });

    test('fromMap: eksik alanlar tablo varsayılanlarına düşer', () {
      final log = NutritionLog.fromMap(const {
        'id': 'n2',
        'food_name': 'Muz',
        'eaten_at': '2026-11-16T10:05:00Z',
      });
      expect(log.mealType, 'snack');
      expect(log.quantityText, isNull);
      expect(log.calories, 0);
      expect(log.source, 'manual');
    });

    test('toWriteMap: düzenlenebilir sütunlar, zaman UTC; id ve source yok', () {
      final log = NutritionLog(
        id: 'n1',
        mealType: 'breakfast',
        foodName: 'Yulaf',
        quantityText: '70 gr',
        calories: 264,
        proteinG: 9,
        carbsG: 46,
        fatG: 5,
        eatenAt: DateTime(2026, 11, 16, 8, 10),
        source: 'ai',
      );
      expect(log.toWriteMap(), {
        'meal_type': 'breakfast',
        'food_name': 'Yulaf',
        'quantity_text': '70 gr',
        'calories': 264.0,
        'protein_g': 9.0,
        'carbs_g': 46.0,
        'fat_g': 5.0,
        'eaten_at': DateTime(2026, 11, 16, 8, 10).toUtc().toIso8601String(),
      });
    });

    test('copyWith: değiştirir; clearQuantityText miktarı siler', () {
      final log = NutritionLog(
        id: 'n1',
        foodName: 'Yulaf',
        quantityText: '70 gr',
        eatenAt: DateTime(2026, 11, 16, 8),
      );
      final changed = log.copyWith(foodName: 'Yulaf ezmesi', calories: 264);
      expect(changed.id, 'n1');
      expect(changed.foodName, 'Yulaf ezmesi');
      expect(changed.calories, 264);
      expect(changed.quantityText, '70 gr');
      expect(log.copyWith(clearQuantityText: true).quantityText, isNull);
    });

    test('öğün türleri veritabanı check listesiyle aynı', () {
      expect(NutritionLog.mealTypes, ['breakfast', 'lunch', 'dinner', 'snack']);
    });
  });

  group('WorkoutLog', () {
    test('fromMap: sütunlar bire bir', () {
      final w = WorkoutLog.fromMap(const {
        'id': 'w1',
        'workout_type': 'running',
        'title': 'Koşu',
        'duration_min': 40,
        'distance_km': 6.5,
        'calories_burned': 420,
        'notes': 'sahil',
        'logged_at': '2026-11-14T07:00:00+00:00',
        'source': 'healthkit',
      });
      expect(w.workoutType, 'running');
      expect(w.title, 'Koşu');
      expect(w.durationMin, 40);
      expect(w.distanceKm, 6.5);
      expect(w.caloriesBurned, 420);
      expect(w.notes, 'sahil');
      expect(w.loggedAt.toUtc(), DateTime.utc(2026, 11, 14, 7));
      expect(w.source, 'healthkit');
    });

    test('fromMap: isteğe bağlı alanlar null kalır; mesafe int gelebilir', () {
      final w = WorkoutLog.fromMap(const {
        'id': 'w2',
        'workout_type': 'weights',
        'distance_km': 5,
        'logged_at': '2026-11-14T07:00:00Z',
      });
      expect(w.title, isNull);
      expect(w.durationMin, isNull);
      expect(w.distanceKm, 5.0);
      expect(w.caloriesBurned, isNull);
      expect(w.notes, isNull);
      expect(w.source, 'manual');
    });

    test('toWriteMap: log_type workout olarak yazılır, zaman UTC', () {
      final w = WorkoutLog(
        id: 'w1',
        workoutType: 'kickboxing',
        title: 'Kickboks',
        durationMin: 60,
        caloriesBurned: 540,
        loggedAt: DateTime(2026, 11, 16, 19, 30),
      );
      expect(w.toWriteMap(), {
        'log_type': 'workout',
        'workout_type': 'kickboxing',
        'title': 'Kickboks',
        'duration_min': 60,
        'distance_km': null,
        'calories_burned': 540,
        'notes': null,
        'logged_at': DateTime(2026, 11, 16, 19, 30).toUtc().toIso8601String(),
      });
    });

    test('copyWith: clear bayrakları isteğe bağlı alanları siler', () {
      final w = WorkoutLog(
        id: 'w1',
        workoutType: 'running',
        title: 'Koşu',
        durationMin: 40,
        distanceKm: 6.5,
        caloriesBurned: 420,
        notes: 'sahil',
        loggedAt: DateTime(2026, 11, 14, 10),
      );
      final cleared = w.copyWith(
        clearTitle: true,
        clearDurationMin: true,
        clearDistanceKm: true,
        clearCaloriesBurned: true,
        clearNotes: true,
      );
      expect(cleared.title, isNull);
      expect(cleared.durationMin, isNull);
      expect(cleared.distanceKm, isNull);
      expect(cleared.caloriesBurned, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.workoutType, 'running');
      expect(w.copyWith(durationMin: 50).durationMin, 50);
      expect(w.copyWith(durationMin: 50).distanceKm, 6.5);
    });

    test('sınırlar veritabanı check kısıtlarıyla aynı', () {
      expect(WorkoutLog.workoutTypes,
          ['weights', 'kickboxing', 'running', 'football', 'other']);
      expect(WorkoutLog.durationMinMin, 1);
      expect(WorkoutLog.durationMinMax, 600);
      expect(WeightLimits.minKg, 30);
      expect(WeightLimits.maxKg, 250);
    });
  });
}
