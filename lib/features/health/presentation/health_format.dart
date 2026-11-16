import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../core/utils/date_utils.dart';
import '../domain/health_models.dart';

/// Sağlık sekmesinin ortak metin biçimleri ve etiketleri.
abstract final class HealthFormat {
  static final NumberFormat _thousands = NumberFormat.decimalPattern('tr_TR');
  static final NumberFormat _plain = NumberFormat('0.##', 'tr_TR');
  static final NumberFormat _oneDecimal = NumberFormat('0.#', 'tr_TR');

  static String mealLabel(String mealType) => switch (mealType) {
        'breakfast' => 'Kahvaltı',
        'lunch' => 'Öğle',
        'dinner' => 'Akşam',
        _ => 'Ara öğün',
      };

  static String workoutLabel(String workoutType) => switch (workoutType) {
        'weights' => 'Ağırlık antrenmanı',
        'kickboxing' => 'Kickboks',
        'running' => 'Koşu',
        'football' => 'Halı saha',
        _ => 'Diğer',
      };

  static final NumberFormat _kg = NumberFormat('0.0', 'tr_TR');

  /// "83,6" (kilo her zaman tek ondalıkla).
  static String kg(double value) => _kg.format(value);

  /// "1.960 kcal"
  static String kcal(num value) => '${_thousands.format(value.round())} kcal';

  /// "8.240"
  static String count(num value) => _thousands.format(value.round());

  /// "28 g" / "27,5 g"
  static String grams(num value) => '${_oneDecimal.format(value)} g';

  /// Gereksiz ondalık olmadan sayı: "5" / "5,25". Form alanlarını doldurur.
  static String plain(num value) => _plain.format(value);

  /// Başlık girilmemişse tür etiketi.
  static String workoutTitle(WorkoutLog workout) {
    final title = workout.title?.trim() ?? '';
    return title.isEmpty ? workoutLabel(workout.workoutType) : title;
  }

  /// "Bugün 19:30 · 60 dk · 5,2 km"
  static String workoutDetail(WorkoutLog workout, {DateTime? now}) {
    final duration = workout.durationMin;
    final distance = workout.distanceKm;
    return [
      AppDates.relativeDayTime(workout.loggedAt, now: now),
      if (duration != null) '$duration dk',
      if (distance != null && distance > 0) '${plain(distance)} km',
    ].join(' · ');
  }
}

/// Virgül ya da noktayla yazılmış ondalık sayıyı okur ve [decimals] basamağa
/// yuvarlar (veritabanı `numeric` ölçeği). Boş ya da geçersizse `null`.
double? parseDecimal(String? text, {int decimals = 2}) {
  final cleaned = (text ?? '').trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) return null;
  final factor = math.pow(10, decimals);
  return (value * factor).round() / factor;
}

String _rangeMessage(num min, num max) =>
    '${HealthFormat.plain(min)} ile ${HealthFormat.plain(max)} arasında olmalı.';

/// Ondalıklı sayı alanı doğrulaması; sınırlar dahildir.
String? validateDecimal(
  String? value, {
  required double min,
  required double max,
  bool required = false,
  int decimals = 1,
}) {
  if ((value ?? '').trim().isEmpty) {
    return required ? 'Bu alan boş olamaz.' : null;
  }
  final parsed = parseDecimal(value, decimals: decimals);
  if (parsed == null) return 'Geçerli bir sayı gir.';
  if (parsed < min || parsed > max) return _rangeMessage(min, max);
  return null;
}

/// Tam sayı alanı doğrulaması; sınırlar dahildir.
String? validateInteger(
  String? value, {
  required int min,
  required int max,
  bool required = false,
}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return required ? 'Bu alan boş olamaz.' : null;
  final parsed = int.tryParse(text);
  if (parsed == null) return 'Tam sayı gir.';
  if (parsed < min || parsed > max) return _rangeMessage(min, max);
  return null;
}

/// Veritabanı `char_length` kod noktası sayar; aynı ölçüyle doğrularız.
String? validateFoodName(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'Ad boş olamaz.';
  if (text.runes.length > NutritionLog.foodNameMaxLength) {
    return 'En fazla ${NutritionLog.foodNameMaxLength} karakter.';
  }
  return null;
}

/// Kilo kartının özet sayıları.
class WeightTrend {
  const WeightTrend({
    required this.latestKg,
    required this.firstKg,
    required this.remainingKg,
    required this.reached,
    this.monthChangeKg,
  });

  /// Penceredeki son ve ilk ölçüm.
  final double latestKg;
  final double firstKg;

  /// İçinde bulunulan aydaki değişim; karşılaştıracak ölçüm yoksa `null`.
  final double? monthChangeKg;

  /// Hedefe kalan mutlak fark.
  final double remainingKg;
  final bool reached;

  /// [series] eskiden yeniye sıralıdır. Aylık değişimin tabanı, rapor
  /// kuralıyla aynı biçimde ay başından önceki son ölçümdür; yoksa ayın ilk
  /// ölçümü.
  static WeightTrend? from(
    List<WeightEntry> series, {
    required double startKg,
    required double targetKg,
    required DateTime now,
  }) {
    if (series.isEmpty) return null;
    final latest = series.last;
    final monthStart = DateTime(now.year, now.month);

    double? monthChange;
    if (!latest.loggedAt.isBefore(monthStart)) {
      final before =
          series.where((e) => e.loggedAt.isBefore(monthStart)).toList();
      final base = before.isNotEmpty
          ? before.last
          : series.firstWhere((e) => !e.loggedAt.isBefore(monthStart));
      if (!identical(base, latest)) {
        monthChange = latest.weightKg - base.weightKg;
      }
    }

    // Hedef başlangıcın altındaysa kilo verme, üstündeyse kilo alma hedefidir.
    final losing = startKg >= targetKg;
    return WeightTrend(
      latestKg: latest.weightKg,
      firstKg: series.first.weightKg,
      monthChangeKg: monthChange,
      remainingKg: (latest.weightKg - targetKg).abs(),
      reached:
          losing ? latest.weightKg <= targetKg : latest.weightKg >= targetKg,
    );
  }
}

/// Bir öğünün kalemleri ve toplamı.
class MealGroup {
  const MealGroup({required this.mealType, required this.logs});

  final String mealType;
  final List<NutritionLog> logs;

  double get calories => logs.fold(0, (sum, l) => sum + l.calories);
  double get proteinG => logs.fold(0, (sum, l) => sum + l.proteinG);
}

/// Günün kayıtlarını öğüne göre gruplar. Üç ana öğün boş olsa da listelenir
/// (taslaktaki "Henüz kayıt yok" satırı); ara öğün yalnızca kayıt varsa.
List<MealGroup> groupMeals(List<NutritionLog> logs) {
  const main = ['breakfast', 'lunch', 'dinner'];
  final snacks = [
    for (final l in logs)
      if (!main.contains(l.mealType)) l,
  ];
  return [
    for (final type in main)
      MealGroup(
        mealType: type,
        logs: [
          for (final l in logs)
            if (l.mealType == type) l,
        ],
      ),
    if (snacks.isNotEmpty) MealGroup(mealType: 'snack', logs: snacks),
  ];
}
