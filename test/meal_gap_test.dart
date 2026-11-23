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

  GapAdvice adviceFor(MealGapReport r, GapMetric m) =>
      r.advice.firstWhere((a) => a.metric == m);

  test('hiç öğün yok: öneri yok, hedef gösterilir', () {
    final r = analyzeMealGap(targets: t, logs: const []);
    expect(r.nothingLogged, isTrue);
    expect(r.advice, isEmpty);
    expect(r.allDone, isFalse);
    expect(r.remainingMeals, ['Kahvaltı', 'Öğle', 'Akşam']);
    expect(r.summary, 'Henüz öğün yok · hedef 2.184 kcal');
  });

  test('eksik: protein akşam yemeğinde yağsız besinle tamamlanır', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 700, p: 50, f: 25, c: 100),
      log('lunch', kcal: 800, p: 73, f: 25, c: 116),
    ]);
    expect(r.gap(GapMetric.protein).status, GapStatus.deficit);
    expect(r.gap(GapMetric.carbs).status, GapStatus.onTarget);
    expect(r.remainingMeals, ['Akşam']);
    final a = adviceFor(r, GapMetric.protein);
    expect(a.headline, 'Protein 45 g eksik');
    expect(a.detail,
        'Akşam yemeğinde: 180 g ton balığı ya da 150 g tavuk göğsü');
    expect(r.summary, 'Protein 45 g eksik · Yağ 22 g eksik');
  });

  test('eksik iki öğüne bölünür', () {
    final r = analyzeMealGap(
        targets: t, logs: [log('breakfast', kcal: 500, p: 40, f: 20, c: 60)]);
    final a = adviceFor(r, GapMetric.protein);
    expect(a.detail, startsWith('Öğle ve Akşam öğünlerinin her birinde: '));
  });

  test('fazla: yağ ve karbonhidrat yarına telafi, aşırı öneri yok', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 700, p: 56, f: 30, c: 80),
      log('lunch', kcal: 700, p: 56, f: 30, c: 80),
      log('dinner', kcal: 784, p: 56, f: 30, c: 86),
    ]);
    expect(r.remainingMeals, isEmpty);
    final fat = adviceFor(r, GapMetric.fat);
    expect(fat.headline, 'Yağ 18 g fazla');
    expect(fat.detail, startsWith('Yarın yağsız pişir, ≈1,5 yemek kaşığı'));
    final carbs = adviceFor(r, GapMetric.carbs);
    expect(carbs.headline, 'Karbonhidrat 30 g fazla');
    expect(carbs.detail, contains('30 g azalt (≈110 g pilav)'));
  });

  test('fazla kalori: en çok 250 kcal kısma ya da yürüyüş', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('lunch', kcal: 1300, p: 84, f: 36, c: 108),
      log('dinner', kcal: 1234, p: 84, f: 36, c: 108),
    ]);
    final a = adviceFor(r, GapMetric.kcal);
    expect(a.headline, 'Kalori 350 kcal fazla');
    expect(a.detail,
        'Aç kalma; yarın 250 kcal az ye (hedef 1.934 kcal) ya da ≈8.500 adım ekstra yürüyüş.');
  });

  test('düşük hedefte 1200 kcal altına inen öneri yok', () {
    final low = computeFatLossTargets(46); // 1.196 kcal
    final r = analyzeMealGap(
        targets: low, logs: [log('lunch', kcal: 1600, p: 92, f: 39, c: 100)]);
    expect(adviceFor(r, GapMetric.kcal).detail, startsWith('Aç kalma; ≈'));
  });

  test('karışık: yağ fazlayken protein için yumurta önerilmez', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 700, p: 60, f: 41, c: 70),
      log('lunch', kcal: 700, p: 63, f: 41, c: 70),
    ]);
    expect(r.summary, 'Protein 45 g eksik · Yağ 10 g fazla');
    final p = adviceFor(r, GapMetric.protein);
    expect(p.detail, isNot(contains('yumurta')));
    expect(p.detail, contains('ton balığı'));
    expect(adviceFor(r, GapMetric.fat).detail, startsWith('Kalan öğünlerde'));
  });

  test('hepsi tamam', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1092, p: 84, f: 36, c: 108),
      log('dinner', kcal: 1092, p: 84, f: 36, c: 108),
    ]);
    expect(r.allDone, isTrue);
    expect(r.advice, isEmpty);
    expect(r.summary, 'Bugünün hedefleri tamam');
  });

  test('lif verisi yoksa bilinmiyor; varsa eksik önerilir', () {
    final logs = [log('lunch', kcal: 2184, p: 168, f: 72, c: 216)];
    final r = analyzeMealGap(targets: t, logs: logs);
    expect(r.gap(GapMetric.fiber).status, GapStatus.unknown);
    expect(r.gap(GapMetric.fiber).headline, 'Lif: veri yok');
    expect(r.allDone, isTrue);
    final withFiber = analyzeMealGap(targets: t, logs: logs, fiberG: 10);
    expect(adviceFor(withFiber, GapMetric.fiber).headline, 'Lif 20 g eksik');
  });

  test('kalan öğünler: 2 öğünde kahvaltıdan sonra akşam', () {
    expect(remainingMealSlots([log('breakfast')], 2), ['dinner']);
    expect(remainingMealSlots([log('snack')], 3),
        ['breakfast', 'lunch', 'dinner']);
    expect(remainingMealSlots([log('dinner')], 3), isEmpty);
  });
}
