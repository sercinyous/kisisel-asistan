import 'fat_loss_plan.dart';
import 'health_models.dart';

/// "Bugün ne eksik / ne fazla": günün öğünleri yağ yakımı hedefleriyle
/// karşılaştırılır; eksikler somut besinlerle, fazlalar kalan öğünlerde
/// telafiyle önerilir. Saf hesap; arayüz ve sağlayıcılar yalnızca okur.

/// Karşılaştırılan değer.
enum GapMetric {
  kcal('Kalori', 'kcal'),
  protein('Protein', 'g'),
  fat('Yağ', 'g'),
  carbs('Karbonhidrat', 'g'),
  fiber('Lif', 'g');

  const GapMetric(this.label, this.unit);
  final String label;
  final String unit;
}

enum GapStatus { deficit, onTarget, excess, unknown }

/// Eşik kuralları tek yerde.
abstract final class MealGapRules {
  /// Bu kadar sapma "tamam" sayılır.
  static const double kcalTolerance = 75;
  static const double gramTolerance = 5;
  static const double fiberTolerance = 3;

  /// Öneri besininin yağ bütçesini aşabileceği pay (g): tavuk göğsü geçer,
  /// yumurta ve kuruyemiş geçmez.
  static const double sideFatTolerance = 6;

  /// Fazla kalori ertesi güne en çok bu kadar yayılır.
  static const int maxNextDayCut = 250;

  /// Hiçbir öneri günlük alımı bunun altına indirmez.
  static const int minDailyKcal = 1200;

  /// Adım ≈ kcal / (kg × 0,0005).
  static const double kcalPerStepPerKg = 0.0005;

  /// Yağsız pişirme önerisinde atlanacak zeytinyağı kaşığının yağı (g).
  static const double oilTablespoonFatG = 13.5;

  /// Bir öneride tek besin en çok bu kadar gram ya da birim olur.
  static const int maxFoodGrams = 300;
  static const int maxFoodUnits = 3;

  /// Fazla telafisi sınırları; ötesi birkaç güne yayılır.
  static const int maxExtraSteps = 10000;
  static const double maxOilSkipTablespoons = 3;
  static const double maxCarbCutShare = 0.5;

  /// "Kalori sınırına yakınsın" notu: gerçek kalan kalori bunun altında.
  static const double nearKcalLimit = 75;

  /// Bir öğüne (ara öğün: [snack]) eklenecek en çok miktar: makrolarda gram,
  /// kaloride kcal.
  static double perMealCap(GapMetric metric, {required bool snack}) =>
      switch (metric) {
        GapMetric.protein => snack ? 20 : 50,
        GapMetric.carbs => snack ? 30 : 90,
        GapMetric.fat => snack ? 10 : 25,
        GapMetric.fiber => snack ? 5 : 12,
        GapMetric.kcal => snack ? 250 : 600,
      };
}

/// Bir değerin günlük durumu.
class MacroGap {
  const MacroGap({
    required this.metric,
    required this.eaten,
    required this.target,
  });

  final GapMetric metric;

  /// Yenen; veri yoksa `null` (öğün kayıtlarında lif tutulmaz).
  final double? eaten;
  final int target;

  double get _tolerance => switch (metric) {
        GapMetric.kcal => MealGapRules.kcalTolerance,
        GapMetric.fiber => MealGapRules.fiberTolerance,
        _ => MealGapRules.gramTolerance,
      };

  /// Yenen − hedef (yuvarlanmış); veri yoksa `null`.
  int? get diff => eaten == null ? null : (eaten! - target).round();

  /// Protein hedefin üstünde: sorun sayılmaz, durum [GapStatus.onTarget].
  bool get aboveTarget =>
      metric == GapMetric.protein && (diff ?? 0) > _tolerance;

  GapStatus get status {
    final d = diff;
    if (d == null) return GapStatus.unknown;
    if (d.abs() <= _tolerance || aboveTarget) return GapStatus.onTarget;
    return d < 0 ? GapStatus.deficit : GapStatus.excess;
  }

  /// "Protein 45 g eksik" / "Yağ 10 g fazla" / "Lif: veri yok".
  String get headline => switch (status) {
        GapStatus.deficit =>
          '${metric.label} ${formatTr(-diff!)} ${metric.unit} eksik',
        GapStatus.excess =>
          '${metric.label} ${formatTr(diff!)} ${metric.unit} fazla',
        GapStatus.onTarget => aboveTarget
            ? '${metric.label} ${formatTr(diff!)} ${metric.unit} hedefin üstünde'
            : '${metric.label} tamam',
        GapStatus.unknown => '${metric.label}: veri yok',
      };
}

/// Bir öneri satırı: başlık ve ne yapılacağı.
class GapAdvice {
  const GapAdvice({
    required this.metric,
    required this.status,
    required this.headline,
    required this.detail,
  });

  final GapMetric metric;
  final GapStatus status;
  final String headline;
  final String detail;

  @override
  String toString() => '$headline → $detail';
}

class MealGapReport {
  const MealGapReport({
    required this.gaps,
    required this.advice,
    required this.remainingMeals,
    required this.nothingLogged,
  });

  /// Sıra: kalori, protein, yağ, karbonhidrat, lif.
  final List<MacroGap> gaps;
  final List<GapAdvice> advice;

  /// Henüz girilmemiş ana öğünlerin adları (ör. ['Akşam']).
  final List<String> remainingMeals;
  final bool nothingLogged;

  MacroGap gap(GapMetric metric) => gaps.firstWhere((g) => g.metric == metric);

  /// Bilinen her değer hedefte (protein hedefin üstünde de olabilir); eksik
  /// ya da fazla yok.
  bool get allDone =>
      !nothingLogged &&
      gaps.every((g) =>
          g.status == GapStatus.onTarget || g.status == GapStatus.unknown);

  /// Beslenme kartındaki kısa satır: en önemli iki sapma.
  String get summary {
    if (nothingLogged) {
      return 'Henüz öğün yok · hedef ${formatTr(gap(GapMetric.kcal).target)} kcal';
    }
    if (allDone) return 'Bugünün hedefleri tamam';
    const order = [
      GapMetric.protein,
      GapMetric.fat,
      GapMetric.carbs,
      GapMetric.kcal,
      GapMetric.fiber,
    ];
    final parts = [
      for (final m in order)
        if (gap(m).status case GapStatus.deficit || GapStatus.excess)
          gap(m).headline,
    ];
    return parts.take(2).join(' · ');
  }
}

/// Ana öğün sırası (öğün sayısına göre) ve görünen adları.
const Map<String, String> _slotNames = {
  'breakfast': 'Kahvaltı',
  'lunch': 'Öğle',
  'dinner': 'Akşam',
};

List<String> _slots(int mealsPerDay) => mealsPerDay <= 2
    ? const ['breakfast', 'dinner']
    : const ['breakfast', 'lunch', 'dinner'];

/// Son girilen ana öğünden sonraki öğünler. Ara öğünler (snack) sırayı
/// değiştirmez; 2 öğünde öğle kaydı ilk öğün sayılır. [now] verilirse
/// penceresi geçmiş öğünler ([mealSlotEndHour]) düşülür.
List<String> remainingMealSlots(
  List<NutritionLog> logs,
  int mealsPerDay, {
  DateTime? now,
}) {
  final slots = _slots(mealsPerDay);
  var last = -1;
  for (final log in logs) {
    final type = mealsPerDay <= 2 && log.mealType == 'lunch'
        ? 'breakfast'
        : log.mealType;
    final i = slots.indexOf(type);
    if (i > last) last = i;
  }
  final left = slots.sublist(last + 1);
  if (now == null) return left;
  return [
    for (final s in left)
      if (now.hour < mealSlotEndHour[s]!) s,
  ];
}

/// Günün öğünlerini [targets] ile karşılaştırır. [fiberG]: bilinen lif
/// (öğün kayıtlarında tutulmadığı için çoğunlukla `null`). [now]: kalan
/// öğünler saate göre süzülür.
MealGapReport analyzeMealGap({
  required FatLossTargets targets,
  required List<NutritionLog> logs,
  int mealsPerDay = 3,
  double? fiberG,
  DateTime? now,
}) {
  double sum(double Function(NutritionLog) f) =>
      logs.fold<double>(0, (s, l) => s + f(l));
  final gaps = [
    MacroGap(
        metric: GapMetric.kcal,
        eaten: sum((l) => l.calories),
        target: targets.kcal),
    MacroGap(
        metric: GapMetric.protein,
        eaten: sum((l) => l.proteinG),
        target: targets.proteinG),
    MacroGap(
        metric: GapMetric.fat, eaten: sum((l) => l.fatG), target: targets.fatG),
    MacroGap(
        metric: GapMetric.carbs,
        eaten: sum((l) => l.carbsG),
        target: targets.carbsG),
    MacroGap(metric: GapMetric.fiber, eaten: fiberG, target: targets.fiberG),
  ];
  final slots = remainingMealSlots(logs, mealsPerDay, now: now);
  final names = [for (final s in slots) _slotNames[s]!];
  if (logs.isEmpty) {
    return MealGapReport(
      gaps: gaps,
      advice: const [],
      remainingMeals: names,
      nothingLogged: true,
    );
  }
  return MealGapReport(
    gaps: gaps,
    advice: _advise(gaps, targets, names),
    remainingMeals: names,
    nothingLogged: false,
  );
}

/// Kalan bütçe: hedef − yenen (fazlada negatif).
class _Budget {
  _Budget(List<MacroGap> gaps)
      : kcal = _left(gaps, GapMetric.kcal),
        fat = _left(gaps, GapMetric.fat),
        carbs = _left(gaps, GapMetric.carbs);

  static double _left(List<MacroGap> gaps, GapMetric m) {
    final g = gaps.firstWhere((g) => g.metric == m);
    return g.target - (g.eaten ?? 0);
  }

  double kcal;
  double fat;
  double carbs;

  bool fits(MenuItem item, GapMetric filling) {
    // Doldurulan makronun kendisi bütçeyi zorlamaz; yan makrolar zorlar.
    final kcalOk = item.kcal <= kcal + MealGapRules.kcalTolerance;
    final fatOk = filling == GapMetric.fat ||
        item.fat <= (fat > 0 ? fat : 0) + MealGapRules.sideFatTolerance;
    final carbsOk = filling == GapMetric.carbs ||
        filling == GapMetric.fiber && carbs > 0 ||
        item.carbs <= (carbs > 0 ? carbs : 0) + MealGapRules.gramTolerance;
    return kcalOk && fatOk && carbsOk;
  }

  /// Sonraki makrolar için yalnızca eklenen makronun kalorisi düşülür
  /// (protein/karbonhidrat/lif ×4 ya da 2, yağ ×9).
  void charge(GapMetric metric, double grams) {
    switch (metric) {
      case GapMetric.fat:
        kcal -= grams * 9;
        fat -= grams;
      case GapMetric.carbs:
        kcal -= grams * 4;
        carbs -= grams;
      case GapMetric.protein:
        kcal -= grams * 4;
      case GapMetric.fiber:
        kcal -= grams * 2;
      case GapMetric.kcal:
        kcal -= grams;
    }
  }
}

FatLossMacro? _macroOf(GapMetric m) => switch (m) {
      GapMetric.protein => FatLossMacro.protein,
      GapMetric.fat => FatLossMacro.fat,
      GapMetric.carbs => FatLossMacro.carbs,
      GapMetric.fiber => FatLossMacro.fiber,
      GapMetric.kcal => null,
    };

/// Bir öneride tek besin sınırı aşmaz: ≤ 300 g ya da ≤ 3 birim.
bool _withinPortion(FoodAmount a) => a.food.unit == FoodUnit.gram
    ? a.quantity <= MealGapRules.maxFoodGrams
    : a.quantity <= MealGapRules.maxFoodUnits;

/// "Kahvaltıda" / "Akşam yemeğinde" / "Kahvaltı, öğle ve akşam öğünlerinin
/// her birinde" / "Ara öğünde".
String _whenText(List<String> meals) {
  if (meals.isEmpty) return 'Ara öğünde';
  if (meals.length == 1) {
    return meals.single == 'Kahvaltı'
        ? 'Kahvaltıda'
        : '${meals.single} yemeğinde';
  }
  final rest = [for (final m in meals.skip(1)) m.toLowerCase()];
  final head = [meals.first, ...rest.take(rest.length - 1)].join(', ');
  return '$head ve ${rest.last} öğünlerinin her birinde';
}

const String _proteinTomorrow =
    'Yarın proteine öncelik ver (ör. tavuk, ton, süzme yoğurt).';

int _round10(double v) => (v / 10).round() * 10;

List<GapAdvice> _advise(
  List<MacroGap> gaps,
  FatLossTargets targets,
  List<String> meals,
) {
  final budget = _Budget(gaps);
  MacroGap gap(GapMetric m) => gaps.firstWhere((g) => g.metric == m);
  final advice = <GapAdvice>[];
  final kcal = gap(GapMetric.kcal);
  final kcalOver = kcal.status == GapStatus.excess;
  final nearLimit = !kcalOver &&
      targets.kcal - (kcal.eaten ?? 0) < MealGapRules.nearKcalLimit;
  final snack = meals.isEmpty;
  final split = snack ? 1 : meals.length;
  final later = meals.isEmpty ? 'Yarın' : 'Kalan öğünlerde';

  // Eksikler: önce protein, sonra lif, karbonhidrat, yağ.
  for (final metric in const [
    GapMetric.protein,
    GapMetric.fiber,
    GapMetric.carbs,
    GapMetric.fat,
  ]) {
    final g = gap(metric);
    if (g.status != GapStatus.deficit) continue;
    void textOnly(String detail) => advice.add(GapAdvice(
          metric: metric,
          status: GapStatus.deficit,
          headline: g.headline,
          detail: detail,
        ));
    if (kcalOver) {
      textOnly(metric == GapMetric.protein
          ? _proteinTomorrow
          : 'Kalori hedefi aşıldı; bugün ekleme yapma.');
      continue;
    }
    final macro = _macroOf(metric)!;
    final missing = -g.diff!;
    final cap = MealGapRules.perMealCap(metric, snack: snack);
    final perMeal = (missing / split < cap ? missing / split : cap).round();
    final options = [
      for (final food in FatLossFoods.equivalents[macro]!)
        if (food != FatLossFoods.butter) equivalentAmount(food, macro, perMeal),
    ].where(_withinPortion).toList()
      ..sort((a, b) => MenuItem(a.food, a.quantity.toDouble())
          .kcal
          .compareTo(MenuItem(b.food, b.quantity.toDouble()).kcal));
    final fitting = [
      for (final a in options)
        if (budget.fits(
            MenuItem(a.food, a.quantity * split.toDouble()), metric))
          MenuItem(a.food, a.quantity.toDouble()),
    ];
    if (fitting.isEmpty) {
      textOnly(metric == GapMetric.protein
          ? _proteinTomorrow
          : 'Kalan kalori bütçesine sığan seçenek yok; yarın '
              '${metric.label.toLowerCase()} hedefine öncelik ver.');
      continue;
    }
    budget.charge(metric, perMeal * split.toDouble());
    final foods = fitting.take(2).map((i) => i.label).join(' ya da ');
    final note = nearLimit ? ' (kalori sınırına yakınsın)' : '';
    final rest = missing - perMeal * split;
    final tolerance = metric == GapMetric.fiber
        ? MealGapRules.fiberTolerance
        : MealGapRules.gramTolerance;
    final tail = rest > tolerance
        ? '. Kalanı (≈${formatTr(rest)} g) yarın tamamla.'
        : '';
    textOnly('${_whenText(meals)}: $foods$note$tail');
  }

  // Makrolar tamamken kalori eksiği: dengeli, sınırlı bir porsiyon.
  final macrosOk = const [GapMetric.protein, GapMetric.fat, GapMetric.carbs]
      .every((m) => gap(m).status != GapStatus.deficit);
  if (kcal.status == GapStatus.deficit && macrosOk) {
    final cap = MealGapRules.perMealCap(GapMetric.kcal, snack: snack);
    final missing = -kcal.diff! / split;
    final perMeal = missing < cap ? missing : cap;
    int grams(double kcalPer100) {
      final g = _round10(perMeal / 2 / kcalPer100 * 100);
      return g.clamp(10, MealGapRules.maxFoodGrams);
    }

    final chicken = grams(FatLossFoods.chicken.kcal);
    final bulgur = grams(FatLossFoods.bulgur.kcal);
    advice.add(GapAdvice(
      metric: GapMetric.kcal,
      status: GapStatus.deficit,
      headline: kcal.headline,
      detail: '${_whenText(meals)} dengeli bir porsiyon ekle (ör. '
          '$chicken g tavuk göğsü + $bulgur g bulgur pilavı).',
    ));
  }

  final fat = gap(GapMetric.fat);
  if (fat.status == GapStatus.excess) {
    final spoons = fat.diff! / MealGapRules.oilTablespoonFatG;
    final capped = spoons > MealGapRules.maxOilSkipTablespoons
        ? MealGapRules.maxOilSkipTablespoons
        : spoons;
    final oil = spoons >= 1
        ? 'zeytinyağını ≈${formatTrQuantity((capped * 2).round() / 2)} '
            'yemek kaşığı azalt'
        : 'zeytinyağını azalt';
    final spread = spoons > MealGapRules.maxOilSkipTablespoons
        ? ', kalanını birkaç güne yay'
        : '';
    advice.add(GapAdvice(
      metric: GapMetric.fat,
      status: GapStatus.excess,
      headline: fat.headline,
      detail: '$later yağsız pişir, $oil$spread; kuruyemiş, tereyağı ve '
          'kızartmadan kaçın.',
    ));
  }
  final carbs = gap(GapMetric.carbs);
  if (carbs.status == GapStatus.excess) {
    final maxCut = (targets.carbsG * MealGapRules.maxCarbCutShare).round();
    final over = carbs.diff!;
    final cut = over < maxCut ? over : maxCut;
    final rice = equivalentAmount(FatLossFoods.rice, FatLossMacro.carbs, cut);
    final spread = over > maxCut ? ', kalanını birkaç güne yay' : '';
    advice.add(GapAdvice(
      metric: GapMetric.carbs,
      status: GapStatus.excess,
      headline: carbs.headline,
      detail: '$later karbonhidratı ${formatTr(cut)} g azalt '
          '(≈${formatTr(rice.quantity)} g pilav)$spread; tabağı sebze ve '
          'proteinle doldur.',
    ));
  }
  final protein = gap(GapMetric.protein);
  if (protein.aboveTarget) {
    final keep = kcal.status == GapStatus.deficit
        ? ''
        : ' $later yağ ve karbonhidratı biraz azalt; kalori hedefi korunur.';
    advice.add(GapAdvice(
      metric: GapMetric.protein,
      status: GapStatus.onTarget,
      headline: protein.headline,
      detail: 'Hedefin üstünde, sorun değil.$keep',
    ));
  }
  if (kcalOver) {
    final over = kcal.diff!;
    final steps = _roundTo(
        over / (targets.weightKg * MealGapRules.kcalPerStepPerKg), 500);
    final walk = steps > MealGapRules.maxExtraSteps
        ? '≈${formatTr(MealGapRules.maxExtraSteps)} adım fazladan yürü, '
            'kalanını birkaç güne yay'
        : '≈${formatTr(steps)} adım fazladan yürü';
    final room = targets.kcal - MealGapRules.minDailyKcal;
    final cut = [over, MealGapRules.maxNextDayCut, room < 0 ? 0 : room]
        .reduce((a, b) => a < b ? a : b);
    final detail = cut <= 0
        ? 'Aç kalma; $walk.'
        : 'Aç kalma; yarın ${formatTr(cut)} kcal az ye (hedef '
            '${formatTr(targets.kcal - cut)} kcal) ya da $walk.';
    advice.add(GapAdvice(
      metric: GapMetric.kcal,
      status: GapStatus.excess,
      headline: kcal.headline,
      detail: detail,
    ));
  }
  return advice;
}

int _roundTo(double value, int step) {
  final r = (value / step).round() * step;
  return r < step ? step : r;
}
