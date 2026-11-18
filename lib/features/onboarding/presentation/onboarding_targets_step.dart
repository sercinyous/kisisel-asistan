import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/goal_suggestion.dart';
import '../domain/onboarding_answers.dart';
import 'onboarding_widgets.dart';

/// 5. adım: hareket düzeyi ve amaç seçilir; VKİ gösterilir, hedef kilo ve
/// günlük hedefler önerilir; hepsi düzenlenebilir.
class OnboardingTargetsStep extends StatelessWidget {
  const OnboardingTargetsStep({
    super.key,
    required this.goal,
    required this.onGoal,
    required this.activity,
    required this.onActivity,
    required this.bmi,
    required this.targetWeight,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.steps,
    required this.sleep,
    required this.onReset,
  });

  final OnboardingGoal goal;
  final ValueChanged<OnboardingGoal> onGoal;
  final ActivityLevel activity;
  final ValueChanged<ActivityLevel> onActivity;

  /// Şimdiki boy ve kiloyla vücut kitle indeksi.
  final double bmi;
  final TextEditingController targetWeight;
  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;
  final TextEditingController steps;
  final TextEditingController sleep;

  /// Alanları yeniden önerilen değerlere döndürür.
  final VoidCallback onReset;

  String _goalText() => switch (goal) {
        OnboardingGoal.lose => 'günlük ihtiyacından 500 kcal eksik',
        OnboardingGoal.maintain => 'günlük ihtiyacın kadar',
        OnboardingGoal.gain => 'günlük ihtiyacından 300 kcal fazla',
      };

  static String? _validator(String? value, int min, int max, String unit) {
    final parsed = TargetLimits.parse(value, min, max);
    return parsed == null ? '$min–$max $unit arasında olmalı.' : null;
  }

  static String? _sleepHelper(String text) {
    final minutes = int.tryParse(text.trim());
    if (minutes == null || minutes <= 0) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Önerilen hedeflerin',
          subtitle: 'Boyun, kilon, yaşın, hareket düzeyin ve amacına göre '
              'hesapladım. İstediğini değiştir.',
        ),
        BentoCard(
          key: const Key('onboarding-bmi'),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Vücut kitle indeksi',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                '${bmi.toStringAsFixed(1).replaceAll('.', ',')} · '
                '${bmiCategory(bmi)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.accent),
              ),
            ],
          ),
        ),
        const OnboardingLabel('Hareket düzeyin'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final level in ActivityLevel.values)
              ChoiceChip(
                key: Key('onboarding-activity-${level.name}'),
                label: Text(level.label),
                showCheckmark: false,
                selected: activity == level,
                onSelected: (_) => onActivity(level),
              ),
          ],
        ),
        OnboardingHint(activity.description),
        const OnboardingLabel('Amacın'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in OnboardingGoal.values)
              ChoiceChip(
                key: Key('onboarding-goal-${option.name}'),
                label: Text(option.label),
                showCheckmark: false,
                selected: goal == option,
                onSelected: (_) => onGoal(option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OnboardingField(
          key: const Key('onboarding-target-weight'),
          controller: targetWeight,
          label: 'Hedef kilo',
          suffix: 'kg',
          helper: 'Sağlıklı VKİ aralığına (18,5–24,9) göre önerildi.',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: OnboardingField.decimal,
          validator: OnboardingValidators.targetWeight,
        ),
        const SizedBox(height: 12),
        OnboardingFieldRow(
          left: OnboardingField(
            key: const Key('onboarding-calories'),
            controller: calories,
            label: 'Kalori',
            suffix: 'kcal',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            validator: (v) => _validator(
              v,
              TargetLimits.caloriesMin,
              TargetLimits.caloriesMax,
              'kcal',
            ),
          ),
          right: OnboardingField(
            key: const Key('onboarding-protein'),
            controller: protein,
            label: 'Protein',
            suffix: 'g',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            validator: (v) => _validator(
              v,
              TargetLimits.proteinMin,
              TargetLimits.proteinMax,
              'g',
            ),
          ),
        ),
        const SizedBox(height: 12),
        OnboardingFieldRow(
          left: OnboardingField(
            key: const Key('onboarding-carbs'),
            controller: carbs,
            label: 'Karbonhidrat',
            suffix: 'g',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            validator: (v) => _validator(
              v,
              TargetLimits.carbsMin,
              TargetLimits.carbsMax,
              'g',
            ),
          ),
          right: OnboardingField(
            key: const Key('onboarding-fat'),
            controller: fat,
            label: 'Yağ',
            suffix: 'g',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            validator: (v) =>
                _validator(v, TargetLimits.fatMin, TargetLimits.fatMax, 'g'),
          ),
        ),
        const SizedBox(height: 12),
        OnboardingFieldRow(
          left: OnboardingField(
            key: const Key('onboarding-steps'),
            controller: steps,
            label: 'Adım',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            validator: (v) => _validator(
              v,
              TargetLimits.stepsMin,
              TargetLimits.stepsMax,
              'adım',
            ),
          ),
          right: ValueListenableBuilder<TextEditingValue>(
            valueListenable: sleep,
            builder: (context, value, _) => OnboardingField(
              key: const Key('onboarding-sleep'),
              controller: sleep,
              label: 'Uyku',
              suffix: 'dk',
              helper: _sleepHelper(value.text),
              keyboardType: TextInputType.number,
              inputFormatters: OnboardingField.digitsOnly,
              textInputAction: TextInputAction.done,
              validator: (v) => _validator(
                v,
                TargetLimits.sleepMin,
                TargetLimits.sleepMax,
                'dk',
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('onboarding-targets-reset'),
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Önerilene dön'),
          ),
        ),
        OnboardingHint(
          'Kalori: bazal metabolizma (Mifflin–St Jeor) × '
          '${activity.factor.toString().replaceAll('.', ',')} → ${_goalText()}. '
          'Protein: kilo başına 1,6 g. Adım 8000, uyku 7,5 saat. Bunlar tahmindir, tıbbi tavsiye '
          'değildir.',
        ),
      ],
    );
  }
}
