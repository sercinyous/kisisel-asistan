import '../../../core/utils/date_utils.dart';

/// `daily_health_metrics` satırı (HealthKit günlük özeti).
class DailyHealthMetric {
  const DailyHealthMetric({
    required this.day,
    this.steps = 0,
    this.activeKcal = 0,
    this.sleepMinutes = 0,
  });

  /// Yerel gün (gece yarısı).
  final DateTime day;
  final int steps;
  final int activeKcal;
  final int sleepMinutes;

  factory DailyHealthMetric.fromMap(Map<String, dynamic> map) =>
      DailyHealthMetric(
        day: DateTime.parse(map['metric_date'] as String),
        steps: (map['steps'] as num?)?.toInt() ?? 0,
        activeKcal: (map['active_kcal'] as num?)?.toInt() ?? 0,
        sleepMinutes: (map['sleep_minutes'] as num?)?.toInt() ?? 0,
      );
}

/// `fitness_logs` içindeki bir kilo ölçümü.
class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.weightKg,
    required this.loggedAt,
  });

  final String id;
  final double weightKg;
  final DateTime loggedAt;

  factory WeightEntry.fromMap(Map<String, dynamic> map) => WeightEntry(
        id: map['id'] as String,
        weightKg: (map['weight_kg'] as num).toDouble(),
        loggedAt: DateTime.parse(map['logged_at'] as String).toLocal(),
      );
}

/// Bir yerel günün makro toplamı.
class DailyNutritionTotal {
  const DailyNutritionTotal({
    required this.day,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.entryCount = 0,
  });

  final DateTime day;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final int entryCount;

  /// `nutrition_logs` satırlarını cihazın yerel gününe göre toplar
  /// (günler eskiden yeniye).
  static List<DailyNutritionTotal> fromLogRows(
    List<Map<String, dynamic>> rows,
  ) {
    double value(Map<String, dynamic> row, String key) =>
        (row[key] as num?)?.toDouble() ?? 0;

    final byDay = <DateTime, DailyNutritionTotal>{};
    for (final row in rows) {
      final eaten = row['eaten_at'];
      final at = eaten is String ? DateTime.tryParse(eaten)?.toLocal() : null;
      if (at == null) continue;
      final day = AppDates.startOfDay(at);
      final sum = byDay[day] ?? DailyNutritionTotal(day: day);
      byDay[day] = DailyNutritionTotal(
        day: day,
        calories: sum.calories + value(row, 'calories'),
        proteinG: sum.proteinG + value(row, 'protein_g'),
        carbsG: sum.carbsG + value(row, 'carbs_g'),
        fatG: sum.fatG + value(row, 'fat_g'),
        entryCount: sum.entryCount + 1,
      );
    }
    return byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }
}

/// Ay ekranındaki "Ay özeti"nin sağlık bölümü. Verisi olmayan ortalama `null`dır.
class MonthHealthSummary {
  const MonthHealthSummary({
    this.avgSteps,
    this.avgSleepMinutes,
    this.avgCalories,
    this.avgProteinG,
    this.weightStartKg,
    this.weightEndKg,
    this.daysWithData = 0,
  });

  final int? avgSteps;
  final int? avgSleepMinutes;
  final double? avgCalories;
  final double? avgProteinG;

  /// Aydaki ilk ve son ölçüm.
  final double? weightStartKg;
  final double? weightEndKg;

  /// HealthKit özeti bulunan gün sayısı.
  final int daysWithData;

  double? get weightChangeKg =>
      weightStartKg == null || weightEndKg == null
          ? null
          : weightEndKg! - weightStartKg!;

  /// Ortalamalar yalnızca verisi olan günler üzerinden alınır: saat takılmayan
  /// ya da öğün girilmeyen gün ortalamayı sıfıra çekmez.
  factory MonthHealthSummary.from({
    required List<DailyHealthMetric> metrics,
    required List<DailyNutritionTotal> nutrition,
    required List<WeightEntry> weights,
  }) {
    double? mean(Iterable<num> values) {
      final list = values.toList();
      if (list.isEmpty) return null;
      return list.fold<double>(0, (sum, v) => sum + v) / list.length;
    }

    final logged = nutrition.where((n) => n.entryCount > 0).toList();
    final sorted = [...weights]
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return MonthHealthSummary(
      avgSteps:
          mean(metrics.where((m) => m.steps > 0).map((m) => m.steps))?.round(),
      avgSleepMinutes: mean(
        metrics.where((m) => m.sleepMinutes > 0).map((m) => m.sleepMinutes),
      )?.round(),
      avgCalories: mean(logged.map((n) => n.calories)),
      avgProteinG: mean(logged.map((n) => n.proteinG)),
      weightStartKg: sorted.isEmpty ? null : sorted.first.weightKg,
      weightEndKg: sorted.isEmpty ? null : sorted.last.weightKg,
      daysWithData: metrics
          .where((m) => m.steps > 0 || m.activeKcal > 0 || m.sleepMinutes > 0)
          .length,
    );
  }
}
