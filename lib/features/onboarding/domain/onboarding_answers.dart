import '../../health/domain/energy_balance.dart';
import '../../health/domain/health_models.dart';
import '../../settings/domain/user_settings.dart';

/// Kilo amacı: önerilen kalori hedefini belirler.
enum OnboardingGoal {
  lose('Kilo ver', -500),
  maintain('Koru', 0),
  gain('Kilo al', 300);

  const OnboardingGoal(this.label, this.kcalDelta);

  /// Seçim çipindeki ad.
  final String label;

  /// Günlük enerji ihtiyacına eklenen kcal (negatif = açık).
  final int kcalDelta;
}

/// Soru adımının metin alanları için doğrulayıcılar. Hata metni `null`
/// dönerse alan geçerlidir. Sınırlar `UserSettings` ve schema.sql ile aynıdır.
abstract final class OnboardingValidators {
  /// En küçük kabul edilen yaş (Kullanım koşulları ve Ayarlar ile aynı).
  static const int minAge = 13;

  static const String underAgeMessage =
      "Ritim'i kullanmak için en az $minAge yaşında olmalısın.";

  /// Virgül ya da nokta ondalıklı sayı; sonlu değilse `null`.
  static double? parseDecimal(String? text) {
    final value = double.tryParse((text ?? '').trim().replaceAll(',', '.'));
    return value == null || !value.isFinite ? null : value;
  }

  static int? parseInt(String? text) => int.tryParse((text ?? '').trim());

  static String? displayName(String? text) {
    final value = (text ?? '').trim();
    if (value.isEmpty) return 'Bir ad yaz.';
    if (value.runes.length > UserSettings.displayNameMax) {
      return 'En fazla ${UserSettings.displayNameMax} karakter.';
    }
    return null;
  }

  static String? height(String? text) {
    final value = parseInt(text);
    if (value == null) return 'Boyunu cm olarak yaz.';
    if (value < UserSettings.heightCmMin || value > UserSettings.heightCmMax) {
      return '${UserSettings.heightCmMin}–${UserSettings.heightCmMax} arasında olmalı.';
    }
    return null;
  }

  static String? birthYear(String? text, {required int nowYear}) {
    final value = parseInt(text);
    if ((text ?? '').trim().isEmpty) return null;
    if (value == null) return 'Doğum yılını yaz.';
    final max = nowYear - minAge;
    if (value > max) return underAgeMessage;
    if (value < UserSettings.birthYearMin) {
      return '${UserSettings.birthYearMin}–$max arasında olmalı.';
    }
    return null;
  }

  static String? weight(String? text) {
    final value = parseDecimal(text);
    if (value == null) return 'Kilonu kg olarak yaz.';
    if (value < WeightLimits.minKg || value > WeightLimits.maxKg) {
      return '${WeightLimits.minKg.round()}–${WeightLimits.maxKg.round()} '
          'arasında olmalı.';
    }
    return null;
  }

  /// Hedef kilo boş bırakılabilir (o zaman mevcut kilo hedef olur).
  static String? targetWeight(String? text) =>
      (text ?? '').trim().isEmpty ? null : weight(text);

  static String? workDescription(String? text) {
    final value = (text ?? '').trim();
    if (value.runes.length > UserSettings.workDescriptionMax) {
      return 'En fazla ${UserSettings.workDescriptionMax} karakter.';
    }
    return null;
  }
}

/// Soru adımının doğrulanmış cevapları.
class OnboardingAnswers {
  const OnboardingAnswers({
    required this.displayName,
    required this.heightCm,
    required this.birthYear,
    required this.sex,
    required this.weightKg,
    required this.targetWeightKg,
    required this.goal,
    this.workDescription,
    this.activity = ActivityLevel.light,
  });

  final String displayName;
  final int heightCm;

  /// Doğum yılı isteğe bağlıdır; boşsa `null`.
  final int? birthYear;

  /// Öneri hesabındaki yaş; doğum yılı yoksa [defaultAge].
  int ageAt(int nowYear) =>
      birthYear == null ? defaultAge : nowYear - birthYear!;

  /// Doğum yılı verilmediğinde kalori önerisinde kullanılan yaş.
  static const int defaultAge = 30;
  final Sex sex;
  final double weightKg;
  final double targetWeightKg;
  final OnboardingGoal goal;

  /// Günlük hareket düzeyi (kalori önerisinin katsayısı).
  final ActivityLevel activity;

  /// "Ne iş yapıyorsun"; boşsa `null`.
  final String? workDescription;

  /// Ham girdilerden cevapları kurar; bir alan geçersizse `null`. Seçilmemiş
  /// cinsiyet "belirtmek istemiyorum", seçilmemiş amaç "koru" sayılır. Boş hedef kilo mevcut kiloya eşitlenir; kilolar `numeric(5,2)`
  /// için iki ondalığa yuvarlanır.
  static OnboardingAnswers? tryParse({
    required String displayName,
    required String height,
    required String birthYear,
    required Sex? sex,
    required String weight,
    required String targetWeight,
    required OnboardingGoal? goal,
    required String workDescription,
    required int nowYear,
    ActivityLevel activity = ActivityLevel.light,
  }) {
    if (OnboardingValidators.displayName(displayName) != null ||
        OnboardingValidators.height(height) != null ||
        OnboardingValidators.birthYear(birthYear, nowYear: nowYear) != null ||
        OnboardingValidators.weight(weight) != null ||
        OnboardingValidators.targetWeight(targetWeight) != null ||
        OnboardingValidators.workDescription(workDescription) != null) {
      return null;
    }
    final weightKg = _round2(OnboardingValidators.parseDecimal(weight)!);
    final target = targetWeight.trim().isEmpty
        ? weightKg
        : _round2(OnboardingValidators.parseDecimal(targetWeight)!);
    final work = workDescription.trim();
    return OnboardingAnswers(
      displayName: displayName.trim(),
      heightCm: OnboardingValidators.parseInt(height)!,
      birthYear: OnboardingValidators.parseInt(birthYear),
      sex: sex ?? Sex.unspecified,
      weightKg: weightKg,
      targetWeightKg: target,
      goal: goal ?? OnboardingGoal.maintain,
      workDescription: work.isEmpty ? null : work,
      activity: activity,
    );
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  /// Hedef hesabını etkileyen alanların imzası: değişmediyse düzenlenmiş
  /// hedefler korunur, değiştiyse yeniden önerilir.
  String get targetsSignature =>
      '$weightKg|$heightCm|$birthYear|${sex.name}|${goal.name}|${activity.name}';
}
