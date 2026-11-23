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

  GapStatus get status {
    final d = diff;
    if (d == null) return GapStatus.unknown;
    if (d.abs() <= _tolerance) return GapStatus.onTarget;
    return d < 0 ? GapStatus.deficit : GapStatus.excess;
  }

  /// "Protein 45 g eksik" / "Yağ 10 g fazla" / "Lif: veri yok".
  String get headline => switch (status) {
        GapStatus.deficit =>
          '${metric.label} ${formatTr(-diff!)} ${metric.unit} eksik',
        GapStatus.excess =>
          '${metric.label} ${formatTr(diff!)} ${metric.unit} fazla',
        GapStatus.onTarget => '${metric.label} tamam',
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

  /// Bilinen her değer hedefte ya da proteinin üstünde değil; eksik ya da
  /// fazla yok.
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
/// değiştirmez.
List<String> remainingMealSlots(List<NutritionLog> logs, int mealsPerDay) {
  final slots = _slots(mealsPerDay);
  var last = -1;
  for (final log in logs) {
    final i = slots.indexOf(log.mealType);
    if (i > last) last = i;
  }
  // 2 öğünde öğle kaydı ilk öğün sayılır.
  if (mealsPerDay <= 2 && last < 0 && logs.any((l) => l.mealType == 'lunch')) {
    last = 0;
  }
  return slots.sublist(last + 1);
}

/// Günün öğünlerini [targets] ile karşılaştırır. [fiberG]: bilinen lif
/// (öğün kayıtlarında tutulmadığı için çoğunlukla `null`).
MealGapReport analyzeMealGap({
  required FatLossTargets targets,
  required List<NutritionLog> logs,
  int mealsPerDay = 3,
  double? fiberG,
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
  final slots = remainingMealSlots(logs, mealsPerDay);
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

  void take(MenuItem item) {
    kcal -= item.kcal;
    fat -= item.fat;
    carbs -= item.carbs;
  }
}

FatLossMacro? _macroOf(GapMetric m) => switch (m) {
      GapMetric.protein => FatLossMacro.protein,
      GapMetric.fat => FatLossMacro.fat,
      GapMetric.carbs => FatLossMacro.carbs,
      GapMetric.fiber => FatLossMacro.fiber,
      GapMetric.kcal => null,
    };

MenuItem _item(FoodAmount a) => MenuItem(a.food, a.quantity.toDouble());

String _whenText(List<String> meals) => switch (meals.length) {
      0 => 'Ara öğünde',
      1 => '${meals.single} yemeğinde',
      _ => '${meals.join(' ve ')} öğünlerinin her birinde',
    };

List<GapAdvice> _advise(
  List<MacroGap> gaps,
  FatLossTargets targets,
  List<String> meals,
) {
  final budget = _Budget(gaps);
  MacroGap gap(GapMetric m) => gaps.firstWhere((g) => g.metric == m);
  final advice = <GapAdvice>[];

  // Eksikler: önce protein, sonra lif, karbonhidrat, yağ.
  for (final metric in const [
    GapMetric.protein,
    GapMetric.fiber,
    GapMetric.carbs,
    GapMetric.fat,
  ]) {
    final g = gap(metric);
    if (g.status != GapStatus.deficit) continue;
    final macro = _macroOf(metric)!;
    final missing = -g.diff!;
    final options = [
      for (final food in FatLossFoods.equivalents[macro]!)
        _item(equivalentAmount(food, macro, missing)),
    ]..sort((a, b) => a.kcal.compareTo(b.kcal));
    var fitting = options.where((i) => budget.fits(i, metric)).toList();
    final tight = fitting.isEmpty;
    if (tight) fitting = [options.first];
    final picks = fitting.take(2).toList();
    budget.take(picks.first);
    final split = meals.length > 1 ? meals.length : 1;
    final foods = picks
        .map((i) =>
            _item(equivalentAmount(i.food, macro, missing, meals: split)).label)
        .join(' ya da ');
    final note = tight ? ' (kalori sınırına yakınsın; en hafif seçenek)' : '';
    advice.add(GapAdvice(
      metric: metric,
      status: GapStatus.deficit,
      headline: g.headline,
      detail: '${_whenText(meals)}: $foods$note',
    ));
  }

  final later = meals.isEmpty ? 'Yarın' : 'Kalan öğünlerde';
  final fat = gap(GapMetric.fat);
  if (fat.status == GapStatus.excess) {
    final spoons = fat.diff! / MealGapRules.oilTablespoonFatG;
    final oil = spoons >= 1
        ? '≈${formatTrQuantity((spoons * 2).round() / 2)} yemek kaşığı zeytinyağı'
        : 'zeytinyağını';
    advice.add(GapAdvice(
      metric: GapMetric.fat,
      status: GapStatus.excess,
      headline: fat.headline,
      detail: '$later yağsız pişir, $oil atla; kuruyemiş, tereyağı ve '
          'kızartmadan kaçın.',
    ));
  }
  final carbs = gap(GapMetric.carbs);
  if (carbs.status == GapStatus.excess) {
    final rice = equivalentAmount(
        FatLossFoods.rice, FatLossMacro.carbs, carbs.diff!);
    advice.add(GapAdvice(
      metric: GapMetric.carbs,
      status: GapStatus.excess,
      headline: carbs.headline,
      detail: '$later karbonhidratı ${formatTr(carbs.diff!)} g azalt '
          '(≈${formatTr(rice.quantity)} g pilav); tabağı sebze ve '
          'proteinle doldur.',
    ));
  }
  final protein = gap(GapMetric.protein);
  if (protein.status == GapStatus.excess) {
    advice.add(GapAdvice(
      metric: GapMetric.protein,
      status: GapStatus.excess,
      headline: protein.headline,
      detail: 'Sorun değil; kalori hedefini aşmamak için kalan öğünlerde '
          'yağ ve karbonhidratı biraz azalt.',
    ));
  }
  final kcal = gap(GapMetric.kcal);
  if (kcal.status == GapStatus.excess) {
    final over = kcal.diff!;
    final steps = _roundTo(
        over / (targets.weightKg * MealGapRules.kcalPerStepPerKg), 500);
    final walk = '≈${formatTr(steps)} adım ekstra yürüyüş';
    final room = targets.kcal - MealGapRules.minDailyKcal;
    final cut = [over, MealGapRules.maxNextDayCut, room < 0 ? 0 : room]
        .reduce((a, b) => a < b ? a : b);
    final detail = cut <= 0
        ? 'Aç kalma; $walk yeterli.'
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
