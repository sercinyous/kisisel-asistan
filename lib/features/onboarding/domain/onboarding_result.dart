import '../../../core/templates/routine_templates.dart';
import '../../routines/domain/routine.dart';
import '../../health/domain/energy_balance.dart' show Sex;
import '../../health/domain/targets_engine.dart';
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
    this.timezone,
  });

  /// `onboarded_at` dolu, tüm cevapları taşıyan tek kayıt.
  final UserSettings settings;

  /// Seçilen başlangıç rutinleri (`id` boş taslaklar, sıra numaralı).
  final List<Routine> routines;

  /// "Kilo" cevabı; ayrıca tartı kaydı olarak yazılır.
  final double weightKg;

  /// Seçilen IANA saat dilimi (rapor günü bununla kesilir); `null` = değişmez.
  final String? timezone;
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
  String? timezone,
}) {
  final work = answers.workDescription;
  final suggested = suggestOnboardingTargets(answers, now: now);
  // Önerilen kalori/makrolar aynen kabul edildiyse kaynak 'onboarding'
  // (motor sonraki tartılarda günceller); elle değiştirildiyse ya da kilo
  // alma hedefiyse 'manual'.
  final fromPlan = usesPlanEngine(answers) &&
      targets.calories == suggested.calories &&
      targets.proteinG == suggested.proteinG &&
      targets.carbsG == suggested.carbsG &&
      targets.fatG == suggested.fatG;
  final settings = base.copyWith(
    targetsSource: fromPlan ? TargetsSource.onboarding : TargetsSource.manual,
    targetsUpdatedAt: now,
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
    activityLevel: answers.activity,
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
    timezone: timezone,
  );
}

/// Öneri tek motordan mı ([resolveTargets])? Koruma hedefinde ve hedef kilosu
/// şimdikinden düşük kilo verme hedefinde evet. Kilo almada (motor fazla
/// vermez) ve hedef kilo şimdiki kiloya eşitken "kilo ver" seçildiğinde
/// [GoalSuggestion] kullanılır; bu durumda kaynak 'manual' olur.
bool usesPlanEngine(OnboardingAnswers answers) => switch (answers.goal) {
      OnboardingGoal.maintain => true,
      OnboardingGoal.lose => answers.targetWeightKg < answers.weightKg - 0.05,
      OnboardingGoal.gain => false,
    };

/// İlk kurulumun hedef adımında önerilen değerler (bkz. [usesPlanEngine];
/// motorun varsayılan hızı Klasik).
OnboardingTargets suggestOnboardingTargets(
  OnboardingAnswers answers, {
  required DateTime now,
}) {
  if (!usesPlanEngine(answers)) {
    return GoalSuggestion.compute(answers, nowYear: now.year);
  }
  final settings = const UserSettings.defaults().copyWith(
    startWeightKg: answers.weightKg,
    // Korumada hedef kilo şimdiki kilo sayılır (motor koruma verir).
    targetWeightKg: answers.goal == OnboardingGoal.maintain
        ? answers.weightKg
        : answers.targetWeightKg,
    heightCm: answers.heightCm,
    birthYear: answers.birthYear,
    sex: answers.sex.name,
    activityLevel: answers.activity,
    dailySteps: GoalSuggestion.steps,
  );
  final resolved = resolveTargets(
    settings: settings,
    latestWeightKg: answers.weightKg,
    age: now.year - answers.birthYear,
    sex: Sex.tryParse(answers.sex.name),
  );
  final written = planWrite(
    settings: settings,
    resolved: resolved,
    trigger: PlanTrigger.onboarding,
    now: now,
  )!
      .settings;
  return OnboardingTargets(
    calories: written.dailyCalories,
    proteinG: written.dailyProteinG,
    carbsG: written.dailyCarbsG,
    fatG: written.dailyFatG,
    steps: GoalSuggestion.steps,
    sleepMinutes: GoalSuggestion.sleepMinutes,
  );
}
