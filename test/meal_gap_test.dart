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
    expect(
        a.detail, 'Akşam yemeğinde: 180 g ton balığı ya da 150 g tavuk göğsü');
    expect(r.summary, 'Protein 45 g eksik · Yağ 22 g eksik');
  });

  test('eksik iki öğüne bölünür', () {
    final r = analyzeMealGap(
        targets: t, logs: [log('breakfast', kcal: 500, p: 40, f: 20, c: 60)]);
    final a = adviceFor(r, GapMetric.protein);
    expect(a.detail, startsWith('Öğle ve akşam öğünlerinin her birinde: '));
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
    expect(
        fat.detail,
        startsWith(
            'Yarın yağsız pişir, zeytinyağını ≈1,5 yemek kaşığı azalt;'));
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
        'Aç kalma; yarın 250 kcal az ye (hedef 1.934 kcal) ya da ≈8.500 adım fazladan yürü.');
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

  void noHugePortions(MealGapReport r) {
    for (final a in r.advice) {
      for (final m in RegExp(r'(\d[\d.]*) g ').allMatches(a.detail)) {
        final grams = int.parse(m.group(1)!.replaceAll('.', ''));
        if (a.detail.contains('azalt')) continue;
        expect(grams, lessThanOrEqualTo(300), reason: a.detail);
      }
    }
  }

  test('kalori fazlayken makro eksiğine besin önerilmez', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1200, p: 60, f: 40, c: 200),
      log('lunch', kcal: 1300, p: 60, f: 10, c: 150),
    ]);
    expect(r.gap(GapMetric.kcal).headline, 'Kalori 316 kcal fazla');
    expect(adviceFor(r, GapMetric.protein).detail,
        'Yarın proteine öncelik ver (ör. tavuk, ton, süzme yoğurt).');
    final fat = adviceFor(r, GapMetric.fat);
    expect(fat.headline, 'Yağ 22 g eksik');
    expect(fat.detail, isNot(contains('zeytinyağı')));
    expect(fat.detail, isNot(contains('ceviz')));
  });

  test('büyük eksikler öğün başına sınırlanır, kalanı yarına', () {
    final r = analyzeMealGap(
      targets: t,
      logs: [log('snack', kcal: 150, p: 5, f: 5, c: 20)],
      now: DateTime(2026, 11, 23, 8),
    );
    expect(r.remainingMeals, ['Kahvaltı', 'Öğle', 'Akşam']);
    final p = adviceFor(r, GapMetric.protein);
    expect(p.detail,
        startsWith('Kahvaltı, öğle ve akşam öğünlerinin her birinde: '));
    expect(p.detail, contains('Kalanı (≈13 g) yarın tamamla'));
    final c = adviceFor(r, GapMetric.carbs);
    expect(c.detail, isNot(contains('4 muz')));
    expect(adviceFor(r, GapMetric.fat).detail, isNot(contains('tereyağı')));
    noHugePortions(r);
  });

  test('ara öğünde küçük porsiyon', () {
    final r = analyzeMealGap(
      targets: t,
      logs: [log('dinner', kcal: 1500, p: 100, f: 50, c: 150)],
    );
    final p = adviceFor(r, GapMetric.protein);
    expect(p.detail, startsWith('Ara öğünde: 80 g ton balığı'));
    expect(p.detail, contains('Kalanı (≈48 g) yarın tamamla'));
    noHugePortions(r);
  });

  test('çok büyük fazla: telafiler sınırlanır', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('lunch', kcal: 4000, p: 168, f: 150, c: 400),
    ]);
    expect(adviceFor(r, GapMetric.kcal).detail,
        'Aç kalma; yarın 250 kcal az ye (hedef 1.934 kcal) ya da ≈10.000 adım fazladan yürü, kalanını birkaç güne yay.');
    expect(
        adviceFor(r, GapMetric.fat).detail,
        contains(
            'zeytinyağını ≈3 yemek kaşığı azalt, kalanını birkaç güne yay'));
    expect(adviceFor(r, GapMetric.carbs).detail,
        contains('karbonhidratı 108 g azalt (≈400 g pilav), kalanını'));
  });

  test('yalnız protein fazlası: tamam sayılır', () {
    final r = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1092, p: 110, f: 36, c: 108),
      log('dinner', kcal: 1092, p: 100, f: 36, c: 108),
    ]);
    expect(r.gap(GapMetric.protein).status, GapStatus.onTarget);
    expect(r.allDone, isTrue);
    final a = adviceFor(r, GapMetric.protein);
    expect(a.headline, 'Protein 42 g hedefin üstünde');
    expect(a.detail, startsWith('Hedefin üstünde, sorun değil.'));
    expect(a.detail, contains('Yarın yağ ve karbonhidratı'));
  });

  test('makrolar tamamken kalori eksiği: sınırlı dengeli porsiyon', () {
    final r = analyzeMealGap(
      targets: t,
      logs: [log('lunch', kcal: 1884, p: 168, f: 72, c: 216)],
      now: DateTime(2026, 11, 23, 13),
    );
    final a = adviceFor(r, GapMetric.kcal);
    expect(
        a.toString(),
        'Kalori 300 kcal eksik → Akşam yemeğinde dengeli bir porsiyon ekle '
        '(ör. 90 g tavuk göğsü + 170 g bulgur pilavı).');
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

  test('örnek çıktılar', () {
    final w95 = computeFatLossTargets(95);
    final lunch = analyzeMealGap(
      targets: w95,
      logs: [log('lunch', kcal: 700, p: 45, f: 25, c: 70)],
      now: DateTime(2026, 11, 23, 14),
    );
    final over = analyzeMealGap(targets: t, logs: [
      log('breakfast', kcal: 1200, p: 60, f: 40, c: 200),
      log('lunch', kcal: 1300, p: 60, f: 10, c: 150),
    ]);
    final snackOnly = analyzeMealGap(
      targets: t,
      logs: [log('snack', kcal: 250, p: 10, f: 10, c: 30)],
      now: DateTime(2026, 11, 23, 12),
    );
    for (final r in [lunch, over, snackOnly]) {
      // ignore: avoid_print
      print('--- ${r.summary}\n${r.advice.join('\n')}');
      noHugePortions(r);
    }
  });
}
