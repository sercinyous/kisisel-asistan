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

class MealGapReport {
  const MealGapReport({
    required this.gaps,
    required this.remainingMeals,
    required this.nothingLogged,
  });

  /// Sıra: kalori, protein, yağ, karbonhidrat, lif.
  final List<MacroGap> gaps;

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
      remainingMeals: names,
      nothingLogged: true,
    );
  }
  return MealGapReport(
    gaps: gaps,
    remainingMeals: names,
    nothingLogged: false,
  );
}
