import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_plan.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/domain/meal_gap.dart';

void main() {
  // 84 kg: 2.184 kcal, P 168, Y 72, K 216, lif 30.
  final t = computeFatLossTargets(84);
  final day = DateTime(2026, 11, 23);

  NutritionLog log(
    String type, {
    double kcal = 0,
    double p = 0,
    double f = 0,
    double c = 0,
  }) =>
      NutritionLog(
        id: type,
        foodName: type,
        mealType: type,
        calories: kcal,
        proteinG: p,
        fatG: f,
        carbsG: c,
        eatenAt: day,
      );


  test('hiç öğün yok: öneri yok, hedef gösterilir', () {
    final r = analyzeMealGap(targets: t, logs: const []);
    expect(r.nothingLogged, isTrue);
    expect(r.allDone, isFalse);
    expect(r.remainingMeals, ['Kahvaltı', 'Öğle', 'Akşam']);
    expect(r.summary, 'Henüz öğün yok · hedef 2.184 kcal');
  });

  test('hepsi tamam', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1092, p: 84, f: 36, c: 108),
      log('dinner', kcal: 1092, p: 84, f: 36, c: 108),
    ]);
    expect(r.allDone, isTrue);
    expect(r.summary, 'Bugünün hedefleri tamam');
  });

  test('lif verisi yoksa bilinmiyor; varsa eksik önerilir', () {
    final logs = [log('lunch', kcal: 2184, p: 168, f: 72, c: 216)];
    final r = analyzeMealGap(targets: t, logs: logs);
    expect(r.gap(GapMetric.fiber).status, GapStatus.unknown);
    expect(r.gap(GapMetric.fiber).headline, 'Lif: veri yok');
    expect(r.allDone, isTrue);
    final withFiber = analyzeMealGap(targets: t, logs: logs, fiberG: 10);
    expect(withFiber.gap(GapMetric.fiber).headline, 'Lif 20 g eksik');
  });

  test('kalan öğünler: 2 öğünde kahvaltıdan sonra akşam', () {
    expect(remainingMealSlots([log('breakfast')], 2), ['dinner']);
    expect(remainingMealSlots([log('snack')], 3),
        ['breakfast', 'lunch', 'dinner']);
    expect(remainingMealSlots([log('dinner')], 3), isEmpty);
  });

  test('yalnız protein fazlası: tamam sayılır', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1092, p: 110, f: 36, c: 108),
      log('dinner', kcal: 1092, p: 100, f: 36, c: 108),
    ]);
    expect(r.gap(GapMetric.protein).status, GapStatus.onTarget);
    expect(r.allDone, isTrue);
    expect(r.gap(GapMetric.protein).headline, 'Protein 42 g hedefin üstünde');
  });

  test('kalan öğünler saate göre', () {
    final logs = [log('snack')];
    expect(remainingMealSlots(logs, 3, now: DateTime(2026, 11, 23, 12)),
        ['lunch', 'dinner']);
    expect(remainingMealSlots(logs, 3, now: DateTime(2026, 11, 23, 17)),
        ['dinner']);
    expect(
        remainingMealSlots(logs, 3, now: DateTime(2026, 11, 23, 23)), isEmpty);
  });

  test('2 öğünde öğle kaydı ilk öğün sayılır', () {
    expect(remainingMealSlots([log('lunch')], 2), ['dinner']);
    expect(remainingMealSlots([log('breakfast'), log('lunch')], 2), ['dinner']);
    expect(remainingMealSlots([log('lunch'), log('dinner')], 2), isEmpty);
  });

}
