import 'package:intl/intl.dart';

/// Yağ yakımı planı: son tartıdan günlük kalori ve makro hedefleri, besin
/// karşılıkları, örnek menüler ve haftalık kayıp tahmini. Saf fonksiyonlar;
/// metin biçimleri Türkçedir. Bilgilendirme amaçlıdır, tıbbi tavsiye değildir.

/// Günlük hedefler (gram ve kcal tam sayı).
class FatLossTargets {
  const FatLossTargets({
    required this.weightKg,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.fiberG,
    required this.carbsG,
  });

  final double weightKg;
  final int kcal;
  final int proteinG;
  final int fatG;
  final int fiberG;
  final int carbsG;

  int gramsFor(FatLossMacro macro) => switch (macro) {
        FatLossMacro.protein => proteinG,
        FatLossMacro.fat => fatG,
        FatLossMacro.carbs => carbsG,
        FatLossMacro.fiber => fiberG,
      };
}

/// Hedef sabitleri tek yerde.
abstract final class FatLossRules {
  static const double kcalPerKg = 26;
  static const double proteinPerKg = 2;
  static const int kcalPerFatGram = 30;
  static const double fiberPer1000Kcal = 14;
  static const double kcalPerKgFat = 7700;

  /// Haftalık kayıp bu değeri aşarsa uyarı gösterilir (kg/hafta).
  static const double fastLossKgPerWeek = 0.8;

  /// Profil eksikse önerilen günlük harcama (kcal).
  static const int defaultExpenditure = 3000;
  static const int expenditureMin = 1200;
  static const int expenditureMax = 6000;

  /// Örnek menülerin hazırlandığı referans kilo.
  static const double referenceKg = 84;
}

/// Kalori = kg × 26; protein = kg × 2; yağ = ⌊kcal / 30⌋;
/// lif = ⌊kcal / 1000 × 14⌋; karbonhidrat = ⌊(kcal − (P×4 + Y×9)) / 4⌋.
FatLossTargets computeFatLossTargets(double weightKg) {
  if (!weightKg.isFinite || weightKg <= 0) {
    throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
  }
  final kcal = (weightKg * FatLossRules.kcalPerKg).floor();
  final protein = (weightKg * FatLossRules.proteinPerKg).floor();
  final fat = kcal ~/ FatLossRules.kcalPerFatGram;
  final fiber = (kcal * FatLossRules.fiberPer1000Kcal / 1000).floor();
  final carbsKcal = kcal - (protein * 4 + fat * 9);
  final carbs = carbsKcal <= 0 ? 0 : carbsKcal ~/ 4;
  return FatLossTargets(
    weightKg: weightKg,
    kcal: kcal,
    proteinG: protein,
    fatG: fat,
    fiberG: fiber,
    carbsG: carbs,
  );
}

/// Haftalık kayıp tahmini.
class WeeklyLossEstimate {
  const WeeklyLossEstimate({
    required this.expenditureKcal,
    required this.targetKcal,
  });

  final int expenditureKcal;
  final int targetKcal;

  int get deficitKcal => expenditureKcal - targetKcal;

  /// Açık yoksa (≤ 0) kayıp yoktur.
  bool get hasLoss => deficitKcal > 0;

  double get weeklyKg =>
      hasLoss ? deficitKcal * 7 / FatLossRules.kcalPerKgFat : 0;

  bool get isTooFast => weeklyKg > FatLossRules.fastLossKgPerWeek;
}

WeeklyLossEstimate estimateWeeklyLoss({
  required int expenditureKcal,
  required int targetKcal,
}) =>
    WeeklyLossEstimate(
      expenditureKcal: expenditureKcal,
      targetKcal: targetKcal,
    );

enum FatLossMacro {
  protein('Protein'),
  fat('Yağ'),
  carbs('Karb'),
  fiber('Lif');

  const FatLossMacro(this.label);
  final String label;
}

/// Bir besinin porsiyon birimi.
enum FoodUnit {
  gram(''),
  piece('adet'),
  tablespoon('yemek kaşığı');

  const FoodUnit(this.label);
  final String label;
}

/// 100 g (pişmiş) besin değerleri; birimli besinlerde bir birim [unitGrams]
/// gramdır.
class FatLossFood {
  const FatLossFood({
    required this.name,
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
    this.unit = FoodUnit.gram,
    this.unitGrams = 1,
  });

  final String name;
  final double kcal;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
  final FoodUnit unit;
  final double unitGrams;

  double per100(FatLossMacro macro) => switch (macro) {
        FatLossMacro.protein => protein,
        FatLossMacro.fat => fat,
        FatLossMacro.carbs => carbs,
        FatLossMacro.fiber => fiber,
      };

  /// Bir porsiyonun (100 g ya da bir birim) makro gramı.
  double perServing(FatLossMacro macro) =>
      unit == FoodUnit.gram ? per100(macro) : per100(macro) * unitGrams / 100;
}

abstract final class FatLossFoods {
  static const chicken = FatLossFood(
      name: 'Tavuk göğsü',
      kcal: 165,
      protein: 31,
      fat: 3.6,
      carbs: 0,
      fiber: 0);
  static const tuna = FatLossFood(
      name: 'Ton balığı', kcal: 116, protein: 25, fat: 1, carbs: 0, fiber: 0);
  static const yogurt = FatLossFood(
      name: 'Süzme yoğurt', kcal: 97, protein: 10, fat: 5, carbs: 4, fiber: 0);
  static const lentil = FatLossFood(
      name: 'Kırmızı mercimek',
      kcal: 116,
      protein: 9,
      fat: 0.4,
      carbs: 20,
      fiber: 7.9);
  static const egg = FatLossFood(
      name: 'Yumurta',
      kcal: 143,
      protein: 12.6,
      fat: 9.5,
      carbs: 0.7,
      fiber: 0,
      unit: FoodUnit.piece,
      unitGrams: 50);
  static const oliveOil = FatLossFood(
      name: 'Zeytinyağı',
      kcal: 884,
      protein: 0,
      fat: 100,
      carbs: 0,
      fiber: 0,
      unit: FoodUnit.tablespoon,
      unitGrams: 13.5);
  static const walnut = FatLossFood(
      name: 'Ceviz', kcal: 654, protein: 15, fat: 65, carbs: 14, fiber: 6.7);
  static const almond = FatLossFood(
      name: 'Badem', kcal: 579, protein: 21, fat: 50, carbs: 22, fiber: 12.5);
  static const butter = FatLossFood(
      name: 'Tereyağı', kcal: 717, protein: 0.9, fat: 81, carbs: 0.1, fiber: 0);
  static const avocado = FatLossFood(
      name: 'Avokado', kcal: 160, protein: 2, fat: 15, carbs: 9, fiber: 6.7);
  static const rice = FatLossFood(
      name: 'Pirinç pilavı',
      kcal: 150,
      protein: 2.7,
      fat: 3,
      carbs: 28,
      fiber: 0.4);
  static const bulgur = FatLossFood(
      name: 'Bulgur pilavı',
      kcal: 111,
      protein: 3.1,
      fat: 2.5,
      carbs: 19,
      fiber: 4.5);
  static const oats = FatLossFood(
      name: 'Kuru yulaf',
      kcal: 389,
      protein: 16.9,
      fat: 6.9,
      carbs: 66,
      fiber: 10);
  static const potato = FatLossFood(
      name: 'Haşlanmış patates',
      kcal: 87,
      protein: 1.9,
      fat: 0.1,
      carbs: 20,
      fiber: 1.8);
  static const bread = FatLossFood(
      name: 'Tam buğday ekmeği',
      kcal: 247,
      protein: 13,
      fat: 3.4,
      carbs: 41,
      fiber: 7);
  static const banana = FatLossFood(
      name: 'Muz',
      kcal: 89,
      protein: 1.1,
      fat: 0.3,
      carbs: 22.5,
      fiber: 2.6,
      unit: FoodUnit.piece,
      unitGrams: 120);
  static const chickpea = FatLossFood(
      name: 'Nohut',
      kcal: 164,
      protein: 8.9,
      fat: 2.6,
      carbs: 27.4,
      fiber: 7.6);
  static const apple = FatLossFood(
      name: 'Elma',
      kcal: 52,
      protein: 0.3,
      fat: 0.2,
      carbs: 13.8,
      fiber: 2.2,
      unit: FoodUnit.piece,
      unitGrams: 200);
  static const salad = FatLossFood(
      name: 'Salata', kcal: 20, protein: 1.2, fat: 0.2, carbs: 3.6, fiber: 1.8);

  /// Her makro için tek başına karşılık gösterilen besinler.
  static const Map<FatLossMacro, List<FatLossFood>> equivalents = {
    FatLossMacro.protein: [chicken, tuna, yogurt, lentil, egg],
    FatLossMacro.fat: [oliveOil, walnut, almond, butter, avocado],
    FatLossMacro.carbs: [rice, bulgur, oats, potato, bread, banana],
    FatLossMacro.fiber: [oats, lentil, chickpea, bulgur, apple],
  };
}

/// Bir besinden gereken miktar: gram ya da birim sayısı.
class FoodAmount {
  const FoodAmount(this.food, this.quantity);

  final FatLossFood food;

  /// Gram (gram birimli besin) ya da birim sayısı.
  final int quantity;

  String get label => '${food.name} · ${formatQuantity(food.unit, quantity)}';
}

String formatQuantity(FoodUnit unit, int quantity) => unit == FoodUnit.gram
    ? '${formatTr(quantity)} g'
    : '${formatTr(quantity)} ${unit.label}';

/// Günlük [macroGrams]'ın [meals] öğüne bölünmüş hâlini tek başına karşılayan
/// miktar. Gram: 100 g ve üstü 10 g'a, altı 5 g'a yuvarlanır; birim: tam sayı
/// (en az 1).
FoodAmount equivalentAmount(
  FatLossFood food,
  FatLossMacro macro,
  int macroGrams, {
  int meals = 1,
}) {
  if (meals < 1) throw ArgumentError.value(meals, 'meals');
  final perServing = food.perServing(macro);
  if (perServing <= 0 || macroGrams <= 0) return FoodAmount(food, 0);
  final servings = macroGrams / meals / perServing;
  if (food.unit != FoodUnit.gram) {
    final n = servings.round();
    return FoodAmount(food, n < 1 ? 1 : n);
  }
  final grams = servings * 100;
  final step = grams >= 100 ? 10 : 5;
  final rounded = (grams / step).round() * step;
  return FoodAmount(food, rounded < step ? step : rounded);
}

List<FoodAmount> equivalentsFor(
  FatLossTargets targets,
  FatLossMacro macro, {
  int meals = 1,
}) =>
    [
      for (final food in FatLossFoods.equivalents[macro]!)
        equivalentAmount(food, macro, targets.gramsFor(macro), meals: meals),
    ];

/// Menüdeki bir kalem.
class MenuItem {
  const MenuItem(this.food, this.quantity);

  final FatLossFood food;

  /// Gram ya da birim sayısı ([FatLossFood.unit]).
  final int quantity;

  double get grams => food.unit == FoodUnit.gram
      ? quantity.toDouble()
      : quantity * food.unitGrams;

  double amountOf(double per100) => per100 * grams / 100;

  double get kcal => amountOf(food.kcal);
  double get carbs => amountOf(food.carbs);

  String get label => food.unit == FoodUnit.gram
      ? '${formatTr(quantity)} g ${food.name.toLowerCase()}'
      : '${formatTr(quantity)} ${food.unit == FoodUnit.piece ? '' : '${food.unit.label} '}'
          '${food.name.toLowerCase()}';

  MenuItem withQuantity(int value) => MenuItem(food, value);
}

class Meal {
  const Meal(this.name, this.items);

  final String name;
  final List<MenuItem> items;
}

/// Menü toplamları.
class MenuTotals {
  const MenuTotals({
    required this.kcal,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
  });

  final double kcal;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;
}

MenuTotals menuTotals(List<Meal> meals) {
  var kcal = 0.0, p = 0.0, f = 0.0, c = 0.0, fi = 0.0;
  for (final meal in meals) {
    for (final item in meal.items) {
      kcal += item.kcal;
      p += item.amountOf(item.food.protein);
      f += item.amountOf(item.food.fat);
      c += item.amountOf(item.food.carbs);
      fi += item.amountOf(item.food.fiber);
    }
  }
  return MenuTotals(kcal: kcal, protein: p, fat: f, carbs: c, fiber: fi);
}

abstract final class FatLossMenus {
  static const threeMeals = [
    Meal('Kahvaltı', [
      MenuItem(FatLossFoods.egg, 3),
      MenuItem(FatLossFoods.oats, 60),
      MenuItem(FatLossFoods.yogurt, 200),
      MenuItem(FatLossFoods.banana, 1),
    ]),
    Meal('Öğle', [
      MenuItem(FatLossFoods.chicken, 150),
      MenuItem(FatLossFoods.bulgur, 250),
      MenuItem(FatLossFoods.salad, 200),
      MenuItem(FatLossFoods.oliveOil, 1),
    ]),
    Meal('Akşam', [
      MenuItem(FatLossFoods.tuna, 150),
      MenuItem(FatLossFoods.lentil, 200),
      MenuItem(FatLossFoods.rice, 140),
      MenuItem(FatLossFoods.salad, 200),
      MenuItem(FatLossFoods.oliveOil, 1),
      MenuItem(FatLossFoods.walnut, 15),
    ]),
  ];

  static const twoMeals = [
    Meal('Öğün 1', [
      MenuItem(FatLossFoods.egg, 3),
      MenuItem(FatLossFoods.oats, 80),
      MenuItem(FatLossFoods.yogurt, 250),
      MenuItem(FatLossFoods.banana, 1),
      MenuItem(FatLossFoods.walnut, 20),
    ]),
    Meal('Öğün 2', [
      MenuItem(FatLossFoods.chicken, 270),
      MenuItem(FatLossFoods.rice, 200),
      MenuItem(FatLossFoods.lentil, 150),
      MenuItem(FatLossFoods.salad, 250),
      MenuItem(FatLossFoods.oliveOil, 20),
      MenuItem(FatLossFoods.apple, 1),
    ]),
  ];
}

/// Zeytinyağı 2 öğünlük menüde gram olarak yazılır; bu yüzden gram birimli
/// bir kopyası tutulur.
const _oliveOilGrams = FatLossFood(
  name: 'Zeytinyağı',
  kcal: 884,
  protein: 0,
  fat: 100,
  carbs: 0,
  fiber: 0,
);

MenuItem _normalize(MenuItem item, List<Meal> source) =>
    identical(source, FatLossMenus.twoMeals) &&
            identical(item.food, FatLossFoods.oliveOil)
        ? MenuItem(_oliveOilGrams, item.quantity)
        : item;

/// Referans (84 kg) menüyü kg/84 ile ölçekler: gram 5 g'a, birim tam sayıya
/// (en az 1) yuvarlanır. Toplam kalori hedefi aşarsa en çok karbonhidratlı
/// gram kalemi 5 g'lık adımlarla azaltılır.
List<Meal> scaledMenu(int mealCount, FatLossTargets targets) {
  final source =
      mealCount == 2 ? FatLossMenus.twoMeals : FatLossMenus.threeMeals;
  final factor = targets.weightKg / FatLossRules.referenceKg;
  final meals = [
    for (final meal in source)
      Meal(meal.name, [
        for (final raw in meal.items) _scale(_normalize(raw, source), factor),
      ]),
  ];
  return trimToTarget(meals, targets.kcal);
}

MenuItem _scale(MenuItem item, double factor) {
  if (item.food.unit != FoodUnit.gram) {
    final n = (item.quantity * factor).round();
    return item.withQuantity(n < 1 ? 1 : n);
  }
  final g = (item.quantity * factor / 5).round() * 5;
  return item.withQuantity(g < 5 ? 5 : g);
}

/// Toplam kalori [targetKcal]'yi aşıyorsa en çok karbonhidrat veren gram
/// kalemini 5 g azaltarak hedefin altına indirir.
List<Meal> trimToTarget(List<Meal> meals, int targetKcal) {
  final items = [
    for (final m in meals) [...m.items]
  ];
  double total() => menuTotals([
        for (var i = 0; i < meals.length; i++) Meal(meals[i].name, items[i]),
      ]).kcal;
  while (total() > targetKcal) {
    var bestMeal = -1, bestItem = -1;
    var bestCarbs = 0.0;
    for (var m = 0; m < items.length; m++) {
      for (var i = 0; i < items[m].length; i++) {
        final item = items[m][i];
        if (item.food.unit != FoodUnit.gram || item.quantity <= 0) continue;
        if (item.carbs > bestCarbs) {
          bestCarbs = item.carbs;
          bestMeal = m;
          bestItem = i;
        }
      }
    }
    if (bestMeal < 0) break;
    final item = items[bestMeal][bestItem];
    items[bestMeal][bestItem] = item.withQuantity(item.quantity - 5);
  }
  return [
    for (var i = 0; i < meals.length; i++)
      Meal(meals[i].name, [
        for (final item in items[i])
          if (item.quantity > 0) item,
      ]),
  ];
}

final NumberFormat _trInt = NumberFormat.decimalPattern('tr_TR');
final NumberFormat _trOneDecimal = NumberFormat('0.0', 'tr_TR');

/// Türkçe binlik ayraçlı tam sayı: 2184 → "2.184".
String formatTr(num value) => _trInt.format(value.round());

/// Bir ondalıklı Türkçe sayı: 0.8 → "0,8".
String formatTrDecimal(double value) => _trOneDecimal.format(value);
