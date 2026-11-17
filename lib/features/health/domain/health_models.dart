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

/// `nutrition_logs` satırı (bir öğün kalemi). Alanlar tablo sütunlarıyla bire birdir.
class NutritionLog {
  const NutritionLog({
    required this.id,
    required this.foodName,
    required this.eatenAt,
    this.mealType = 'snack',
    this.quantityText,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.source = 'manual',
  });

  /// Veritabanı check listesi (gösterim sırası: kahvaltı → ara öğün).
  static const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

  // Veritabanı check sınırları; formlar aynı sınırlarla doğrular.
  static const int foodNameMaxLength = 200;

  /// `numeric(7,1)`: kalori üst sınırı.
  static const double caloriesMax = 99999.9;

  /// `numeric(6,1)`: makro üst sınırı.
  static const double macroMax = 9999.9;

  final String id;

  /// 'breakfast' | 'lunch' | 'dinner' | 'snack'
  final String mealType;
  final String foodName;
  final String? quantityText;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Yerel saat.
  final DateTime eatenAt;

  /// 'manual' | 'ai'
  final String source;

  factory NutritionLog.fromMap(Map<String, dynamic> map) => NutritionLog(
        id: map['id'] as String,
        mealType: map['meal_type'] as String? ?? 'snack',
        foodName: map['food_name'] as String? ?? '',
        quantityText: map['quantity_text'] as String?,
        calories: (map['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (map['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (map['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (map['fat_g'] as num?)?.toDouble() ?? 0,
        eatenAt: DateTime.parse(map['eaten_at'] as String).toLocal(),
        source: map['source'] as String? ?? 'manual',
      );

  /// Düzenlenebilir sütunlar (insert ve update için; id/user_id/source içermez).
  Map<String, dynamic> toWriteMap() => {
        'meal_type': mealType,
        'food_name': foodName,
        'quantity_text': quantityText,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'eaten_at': eatenAt.toUtc().toIso8601String(),
      };

  NutritionLog copyWith({
    String? id,
    String? mealType,
    String? foodName,
    String? quantityText,
    bool clearQuantityText = false,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    DateTime? eatenAt,
    String? source,
  }) =>
      NutritionLog(
        id: id ?? this.id,
        mealType: mealType ?? this.mealType,
        foodName: foodName ?? this.foodName,
        quantityText:
            clearQuantityText ? null : quantityText ?? this.quantityText,
        calories: calories ?? this.calories,
        proteinG: proteinG ?? this.proteinG,
        carbsG: carbsG ?? this.carbsG,
        fatG: fatG ?? this.fatG,
        eatenAt: eatenAt ?? this.eatenAt,
        source: source ?? this.source,
      );
}

/// `fitness_logs` içindeki bir antrenman (log_type = 'workout').
/// Alanlar tablo sütunlarıyla bire birdir.
class WorkoutLog {
  const WorkoutLog({
    required this.id,
    required this.loggedAt,
    this.workoutType = 'other',
    this.title,
    this.durationMin,
    this.distanceKm,
    this.caloriesBurned,
    this.notes,
    this.source = 'manual',
  });

  /// Veritabanı check listesi.
  static const workoutTypes = [
    'weights',
    'kickboxing',
    'running',
    'football',
    'other',
  ];

  // Veritabanı check sınırları; formlar aynı sınırlarla doğrular.
  static const int durationMinMin = 1;
  static const int durationMinMax = 600;

  /// `numeric(6,2)`: mesafe üst sınırı.
  static const double distanceKmMax = 9999.99;

  final String id;

  /// 'weights' | 'kickboxing' | 'running' | 'football' | 'other'
  final String workoutType;
  final String? title;
  final int? durationMin;
  final double? distanceKm;
  final int? caloriesBurned;
  final String? notes;

  /// Yerel saat.
  final DateTime loggedAt;

  /// 'manual' | 'ai' | 'healthkit' | 'google'
  final String source;

  factory WorkoutLog.fromMap(Map<String, dynamic> map) => WorkoutLog(
        id: map['id'] as String,
        workoutType: map['workout_type'] as String? ?? 'other',
        title: map['title'] as String?,
        durationMin: (map['duration_min'] as num?)?.toInt(),
        distanceKm: (map['distance_km'] as num?)?.toDouble(),
        caloriesBurned: (map['calories_burned'] as num?)?.toInt(),
        notes: map['notes'] as String?,
        loggedAt: DateTime.parse(map['logged_at'] as String).toLocal(),
        source: map['source'] as String? ?? 'manual',
      );

  /// Düzenlenebilir sütunlar (insert ve update için; id/user_id/source içermez).
  Map<String, dynamic> toWriteMap() => {
        'log_type': 'workout',
        'workout_type': workoutType,
        'title': title,
        'duration_min': durationMin,
        'distance_km': distanceKm,
        'calories_burned': caloriesBurned,
        'notes': notes,
        'logged_at': loggedAt.toUtc().toIso8601String(),
      };

  WorkoutLog copyWith({
    String? id,
    String? workoutType,
    String? title,
    bool clearTitle = false,
    int? durationMin,
    bool clearDurationMin = false,
    double? distanceKm,
    bool clearDistanceKm = false,
    int? caloriesBurned,
    bool clearCaloriesBurned = false,
    String? notes,
    bool clearNotes = false,
    DateTime? loggedAt,
    String? source,
  }) =>
      WorkoutLog(
        id: id ?? this.id,
        workoutType: workoutType ?? this.workoutType,
        title: clearTitle ? null : title ?? this.title,
        durationMin: clearDurationMin ? null : durationMin ?? this.durationMin,
        distanceKm: clearDistanceKm ? null : distanceKm ?? this.distanceKm,
        caloriesBurned:
            clearCaloriesBurned ? null : caloriesBurned ?? this.caloriesBurned,
        notes: clearNotes ? null : notes ?? this.notes,
        loggedAt: loggedAt ?? this.loggedAt,
        source: source ?? this.source,
      );
}

/// Dış kaynaktan içe aktarılan antrenman (`fitness_logs`, source = 'google').
/// [externalId] kaynaktaki kimliktir; `(user_id, source, external_id)` tekil
/// dizini yeniden eşitlemede aynı oturumun ikinci kez yazılmasını önler.
class ExternalWorkout {
  const ExternalWorkout({
    required this.source,
    required this.externalId,
    required this.workout,
  });

  /// `fitness_logs.source` değeri ('google').
  final String source;

  /// Kaynaktaki kimlik (Google Health veri noktası adı).
  final String externalId;

  /// Yazılacak antrenman; `id` ve `source` alanları kullanılmaz.
  final WorkoutLog workout;

  /// `external_id` sütun sınırı (schema.sql check'i).
  static const int externalIdMaxLength = 300;

  /// Tek satırlık ekleme gövdesi.
  Map<String, dynamic> toInsertMap(String userId) => {
        ...workout.toWriteMap(),
        'user_id': userId,
        'source': source,
        'external_id': externalId,
      };
}

/// Kilo ölçümünün veritabanı check sınırları (`fitness_logs.weight_kg`).
abstract final class WeightLimits {
  static const double minKg = 30;
  static const double maxKg = 250;
}
