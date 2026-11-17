import '../../../core/templates/routine_templates.dart';
import '../../routines/domain/routine.dart';
import '../../settings/domain/user_settings.dart';
import 'goal_suggestion.dart';
import 'onboarding_answers.dart';

/// Bildirim izni ve sessiz saat tercihleri (4. adım).
class OnboardingPreferences {
  const OnboardingPreferences({
    this.notificationsEnabled = true,
    this.quietHoursEnabled = true,
    this.quietStart = const TimeOfDayValue(23, 0),
    this.quietEnd = const TimeOfDayValue(7, 30),
  });

  final bool notificationsEnabled;
  final bool quietHoursEnabled;
  final TimeOfDayValue quietStart;
  final TimeOfDayValue quietEnd;
}

/// İlk kurulumun yazılacak sonucu: tek `user_settings` kaydı, eklenecek
/// rutinler ve tartı kaydı olacak kilo.
class OnboardingResult {
  const OnboardingResult({
    required this.settings,
    required this.routines,
    required this.weightKg,
  });

  /// `onboarded_at` dolu, tüm cevapları taşıyan tek kayıt.
  final UserSettings settings;

  /// Seçilen başlangıç rutinleri (`id` boş taslaklar, sıra numaralı).
  final List<Routine> routines;

  /// "Kilo" cevabı; ayrıca tartı kaydı olarak yazılır.
  final double weightKg;
}

/// Cevaplardan, hedeflerden ve tercihlerden sonucu kurar. [base] mevcut ayar
/// satırıdır (ekip, bildirim saatleri gibi sorulmayan alanlar korunur);
/// [now] `onboarded_at` olur.
OnboardingResult buildOnboardingResult({
  required UserSettings base,
  required OnboardingAnswers answers,
  required OnboardingTargets targets,
  required OnboardingPreferences preferences,
  required Iterable<RoutineTemplate> routines,
  required DateTime now,
}) {
  final work = answers.workDescription;
  final settings = base.copyWith(
    startWeightKg: answers.weightKg,
    targetWeightKg: answers.targetWeightKg,
    dailyCalories: targets.calories,
    dailyProteinG: targets.proteinG,
    dailyCarbsG: targets.carbsG,
    dailyFatG: targets.fatG,
    dailySteps: targets.steps,
    sleepMinutes: targets.sleepMinutes,
    notificationsEnabled: preferences.notificationsEnabled,
    quietHoursEnabled: preferences.quietHoursEnabled,
    quietStart: preferences.quietStart,
    quietEnd: preferences.quietEnd,
    heightCm: answers.heightCm,
    birthYear: answers.birthYear,
    sex: answers.sex.name,
    displayName: answers.displayName,
    workDescription: work,
    clearWorkDescription: work == null,
    onboardedAt: now,
  );
  return OnboardingResult(
    settings: settings,
    routines: [
      for (final (index, template) in routines.indexed)
        template.toRoutine(sortOrder: index),
    ],
    weightKg: answers.weightKg,
  );
}
