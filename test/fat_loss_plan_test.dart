import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_plan.dart';

void main() {
  group('hedefler', () {
    test('84 kg örneği', () {
      final t = computeFatLossTargets(84);
      expect(t.kcal, 2184);
      expect(t.proteinG, 168);
      expect(t.fatG, 72);
      expect(t.fiberG, 30);
      expect(t.carbsG, 216);
    });

    test('ondalıklı kilo aşağı yuvarlanır', () {
      final t = computeFatLossTargets(70.5);
      expect(t.kcal, 1833);
      expect(t.proteinG, 141);
      expect(t.fatG, 61);
      expect(t.fiberG, 25);
      expect(t.carbsG, (1833 - (141 * 4 + 61 * 9)) ~/ 4);
    });

    test('geçersiz kilo hata verir', () {
      expect(() => computeFatLossTargets(0), throwsArgumentError);
    });
  });

  test('Türkçe sayı biçimi', () {
    expect(formatTr(2184), '2.184');
    expect(formatTr(540), '540');
    expect(formatTrDecimal(0.8), '0,8');
    expect(formatTrDecimal(84), '84,0');
    expect(formatTrDecimal2(816 * 7 / 7700), '0,74');
    expect(formatTrQuantity(1.5), '1,5');
    expect(formatTrQuantity(3), '3');
  });

  group('haftalık kayıp', () {
    test('açık varsa kg/hafta', () {
      final w = estimateWeeklyLoss(expenditureKcal: 3000, targetKcal: 2184);
      expect(w.deficitKcal, 816);
      expect(w.weeklyKg, closeTo(816 * 7 / 7700, 1e-9));
      expect(w.isTooFast, isFalse);
    });

    test('0,8 kg/hafta üstü hızlı sayılır', () {
      final w = estimateWeeklyLoss(expenditureKcal: 3000, targetKcal: 1560);
      expect(w.weeklyKg, closeTo(1440 * 7 / 7700, 1e-9));
      expect(w.isTooFast, isTrue);
    });

    test('yavaş kayıpta uyarı yok', () {
      final w = estimateWeeklyLoss(expenditureKcal: 2600, targetKcal: 2184);
      expect(w.hasLoss, isTrue);
      expect(w.isTooFast, isFalse);
    });

    test('açık yoksa kayıp yok', () {
      final w = estimateWeeklyLoss(expenditureKcal: 2000, targetKcal: 2184);
      expect(w.hasLoss, isFalse);
      expect(w.weeklyKg, 0);
      expect(w.isTooFast, isFalse);
    });
  });

  group('besin karşılıkları', () {
    final t = computeFatLossTargets(84);

    test('tek öğün etiketleri', () {
      final protein =
          equivalentsFor(t, FatLossMacro.protein).map((a) => a.label).toList();
      expect(protein, contains('Tavuk göğsü · 540 g'));
      expect(protein, contains('Yumurta · 27 adet'));
      final fat =
          equivalentsFor(t, FatLossMacro.fat).map((a) => a.label).toList();
      expect(fat, contains('Zeytinyağı · 5 yemek kaşığı'));
      final carbs =
          equivalentsFor(t, FatLossMacro.carbs).map((a) => a.label).toList();
      expect(carbs, contains('Muz · 8 adet'));
      expect(carbs, contains('Pirinç pilavı · 800 g'));
      final fiber =
          equivalentsFor(t, FatLossMacro.fiber).map((a) => a.label).toList();
      expect(fiber, contains('Kuru yulaf · 300 g'));
      expect(fiber, contains('Elma · 9 adet'));
    });

    test('öğün sayısına bölünür', () {
      final a = equivalentAmount(
          FatLossFoods.chicken, FatLossMacro.protein, 168,
          meals: 3);
      // 56 / 31 × 100 = 180,6 → 180 g.
      expect(a.quantity, 180);
      final egg = equivalentAmount(FatLossFoods.egg, FatLossMacro.protein, 168,
          meals: 2);
      expect(egg.quantity, 13);
    });

    test('küçük gram 5 g adımla, birim en az 1', () {
      expect(
          equivalentAmount(FatLossFoods.walnut, FatLossMacro.fat, 24).quantity,
          35);
      expect(
          equivalentAmount(FatLossFoods.apple, FatLossMacro.fiber, 1).quantity,
          1);
    });
  });

  group('örnek menü', () {
    test('84 kg: referans hedefin altında, kırpma yok, gramlar aynı', () {
      final t = computeFatLossTargets(84);
      for (final count in [2, 3]) {
        final reference =
            count == 2 ? FatLossMenus.twoMeals : FatLossMenus.threeMeals;
        final refTotals = menuTotals(reference);
        expect(refTotals.kcal, lessThanOrEqualTo(t.kcal));
        expect(refTotals.fat, lessThanOrEqualTo(t.fatG + 0.5));
        final menu = scaledMenu(count, t);
        expect(
          [for (final m in menu) for (final i in m.items) i.quantity],
          [for (final m in reference) for (final i in m.items) i.quantity],
        );
      }
      final three = menuTotals(FatLossMenus.threeMeals);
      expect(three.kcal, closeTo(2176, 25));
      expect(three.protein, closeTo(171, 3));
      expect(three.fat, closeTo(71, 2));
      expect(three.carbs, closeTo(216, 3));
      expect(three.fiber, closeTo(42, 2));
      final two = menuTotals(FatLossMenus.twoMeals);
      expect(two.kcal, closeTo(2165, 45));
      expect(two.protein, closeTo(167, 3));
      expect(two.fat, closeTo(73, 2));
      expect(two.carbs, closeTo(208, 3));
      expect(two.fiber, closeTo(32, 2));
    });

    test('2 öğünde zeytinyağı gramla yazılır', () {
      final oil = FatLossMenus.twoMeals[1].items
          .firstWhere((i) => i.food.name == 'Zeytinyağı');
      expect(oil.food.unit, FoodUnit.gram);
      expect(oil.label, '20 g zeytinyağı');
    });

    for (final kg in [30.0, 60.0, 84.0, 120.0, 250.0]) {
      test('$kg kg: kalori hedefi aşmaz, yağ en çok %10 fazla', () {
        final t = computeFatLossTargets(kg);
        for (final count in [2, 3]) {
          final menu = scaledMenu(count, t);
          final totals = menuTotals(menu);
          expect(totals.kcal, lessThanOrEqualTo(t.kcal), reason: '$count öğün');
          expect(totals.fat, lessThanOrEqualTo(t.fatG * 1.1),
              reason: '$count öğün');
          for (final meal in menu) {
            for (final item in meal.items) {
              if (item.food.unit == FoodUnit.piece) {
                expect(item.quantity, greaterThanOrEqualTo(1));
              }
            }
          }
          // Protein kalemleri kırpılmaz: ölçeklenmiş miktar korunur.
          final chicken = menu
              .expand((m) => m.items)
              .firstWhere((i) => identical(i.food, FatLossFoods.chicken));
          final ref = (count == 2 ? 270 : 150) * kg / 84;
          expect(chicken.quantity, closeTo(ref, 5));
        }
      });
    }

    test('yağ fazlası önce yağ kaynaklarından kırpılır', () {
      const meals = [
        Meal('A', [
          MenuItem(FatLossFoods.chicken, 100),
          MenuItem(FatLossFoods.walnut, 40),
          MenuItem(FatLossFoods.oliveOil, 2),
          MenuItem(FatLossFoods.rice, 100),
        ]),
      ];
      final trimmed = trimToTarget(meals, 5000, fatTargetG: 20);
      final items = trimmed.first.items;
      expect(menuTotals(trimmed).fat, lessThanOrEqualTo(20.5));
      expect(items.first.quantity, 100);
      expect(items.firstWhere((i) => i.food == FatLossFoods.rice).quantity,
          100);
      final oil = items.where((i) => i.food == FatLossFoods.oliveOil);
      for (final o in oil) {
        expect(o.quantity * 2 % 1, 0); // 0,5 adım
      }
    });

    test('ölçekleme: gram 5 g, birim tam sayı', () {
      final t = computeFatLossTargets(100);
      final menu = scaledMenu(2, t);
      final first = menu.first.items;
      expect(first[0].quantity, 4); // 3 × 100/84 = 3,57 → 4 yumurta
      expect(menu[1].items.first.quantity, 320); // 270 × 1,19 = 321 → 320 g
      for (final meal in menu) {
        for (final item in meal.items) {
          if (item.food.unit == FoodUnit.gram) {
            expect(item.quantity % 5, 0);
          }
        }
      }
      expect(menuTotals(menu).kcal, lessThanOrEqualTo(t.kcal));
    });

    test('kırpma en çok karbonhidratlı gram kalemden başlar', () {
      const meals = [
        Meal('A', [
          MenuItem(FatLossFoods.rice, 300),
          MenuItem(FatLossFoods.chicken, 100),
        ]),
      ];
      final before = menuTotals(meals).kcal; // 450 + 165
      final trimmed = trimToTarget(meals, (before - 20).floor());
      expect(trimmed.first.items[0].quantity, lessThan(300));
      expect(trimmed.first.items[1].quantity, 100);
      expect(menuTotals(trimmed).kcal, lessThanOrEqualTo(before - 20));
    });

    test('etiketler', () {
      expect(const MenuItem(FatLossFoods.egg, 3).label, '3 yumurta');
      expect(const MenuItem(FatLossFoods.oliveOil, 1).label,
          '1 yemek kaşığı zeytinyağı');
      expect(const MenuItem(FatLossFoods.oats, 60).label, '60 g kuru yulaf');
    });
  });
}
