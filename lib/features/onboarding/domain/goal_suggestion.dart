import '../../health/domain/energy_balance.dart';
import '../../health/domain/health_models.dart';
import '../../settings/domain/user_settings.dart';
import 'onboarding_answers.dart';

/// `user_settings` hedef sütunlarının veritabanı sınırları (schema.sql ve
/// Ayarlar ekranıyla aynı).
abstract final class TargetLimits {
  static const int caloriesMin = 800, caloriesMax = 6000;
  static const int proteinMin = 0, proteinMax = 500;
  static const int carbsMin = 0, carbsMax = 800;
  static const int fatMin = 0, fatMax = 400;
  static const int stepsMin = 1000, stepsMax = 60000;
  static const int sleepMin = 180, sleepMax = 900;

  /// Tam sayı ve [min]..[max] aralığındaysa değer, değilse `null`.
  static int? parse(String? text, int min, int max) {
    final value = int.tryParse((text ?? '').trim());
    return value == null || value < min || value > max ? null : value;
  }
}

/// Önerilen (ve düzenlenebilen) günlük hedefler.
class OnboardingTargets {
  const OnboardingTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.steps,
    required this.sleepMinutes,
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int steps;
  final int sleepMinutes;

  @override
  bool operator ==(Object other) =>
      other is OnboardingTargets &&
      other.calories == calories &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG &&
      other.steps == steps &&
      other.sleepMinutes == sleepMinutes;

  @override
  int get hashCode =>
      Object.hash(calories, proteinG, carbsG, fatG, steps, sleepMinutes);

  @override
  String toString() =>
      'OnboardingTargets($calories kcal, $proteinG/$carbsG/$fatG g, '
      '$steps adım, $sleepMinutes dk)';
}

/// Vücut kitle indeksi: kg / m². Geçersiz girdi [ArgumentError] fırlatır.
double bodyMassIndex({required double weightKg, required int heightCm}) {
  if (!weightKg.isFinite || weightKg <= 0) {
    throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
  }
  if (heightCm <= 0) {
    throw ArgumentError.value(heightCm, 'heightCm', 'must be positive');
  }
  final m = heightCm / 100;
  return weightKg / (m * m);
}

/// VKİ'nin Türkçe sınıfı (DSÖ eşikleri).
String bmiCategory(double bmi) {
  if (bmi < GoalSuggestion.healthyBmiMin) return 'Zayıf';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Fazla kilolu';
  return 'Obez';
}

/// Cevaplardan önerilen hedefler. Formüller sabittir ve tıbbi tavsiye değildir:
///
/// * kalori = bazal (Mifflin–St Jeor, 4A'nın [basalKcal]'i) × hareket
///   katsayısı ([ActivityLevel.factor]) + amaç farkı (−500 / 0 / +300);
///   18 yaş altında açık uygulanmaz ve sonuç [minCalories]'in altına inmez;
/// * protein = 1,6 g × kilo;
/// * yağ = kalorinin %27'si (9 kcal/g), karbonhidrat = kalan kalori (4 kcal/g);
/// * adım 8000, uyku 7,5 saat;
/// * hedef kilo: VKİ sağlıklı aralıktaysa (18,5–24,9) mevcut kilo, değilse
///   aralığın en yakın ucundaki kilo.
abstract final class GoalSuggestion {
  static const double proteinPerKg = 1.6;
  static const double fatShare = 0.27;
  static const int steps = 8000;
  static const int sleepMinutes = 450;
  static const double healthyBmiMin = 18.5;
  static const double healthyBmiMax = 24.9;

  /// Açıkla bile önerilen en düşük günlük kalori.
  static const int minCalories = 1200;

  /// Sağlıklı VKİ aralığında kalan önerilen hedef kilo (bir ondalık).
  static double suggestTargetWeight({
    required double weightKg,
    required int heightCm,
  }) {
    final bmi = bodyMassIndex(weightKg: weightKg, heightCm: heightCm);
    final m2 = (heightCm / 100) * (heightCm / 100);
    final double target;
    if (bmi > healthyBmiMax) {
      target = healthyBmiMax * m2;
    } else if (bmi < healthyBmiMin) {
      target = healthyBmiMin * m2;
    } else {
      target = weightKg;
    }
    return ((target * 10).roundToDouble() / 10)
        .clamp(WeightLimits.minKg, WeightLimits.maxKg)
        .toDouble();
  }

  static OnboardingTargets compute(
    OnboardingAnswers answers, {
    required int nowYear,
  }) {
    final age = answers.ageAt(nowYear);
    final basal = basalKcal(
      weightKg: answers.weightKg,
      heightCm: answers.heightCm,
      age: age,
      sex: answers.sex,
    );
    final delta = age < EnergyBands.adultAge ? 0 : answers.goal.kcalDelta;
    final calories = (basal * answers.activity.factor + delta)
        .round()
        .clamp(minCalories, TargetLimits.caloriesMax);
    final protein = (proteinPerKg * answers.weightKg)
        .round()
        .clamp(TargetLimits.proteinMin, TargetLimits.proteinMax);
    final fat = (calories * fatShare / 9)
        .round()
        .clamp(TargetLimits.fatMin, TargetLimits.fatMax);
    final carbs = ((calories - protein * 4 - fat * 9) / 4)
        .round()
        .clamp(TargetLimits.carbsMin, TargetLimits.carbsMax);
    return OnboardingTargets(
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      steps: GoalSuggestion.steps,
      sleepMinutes: GoalSuggestion.sleepMinutes,
    );
  }
}
