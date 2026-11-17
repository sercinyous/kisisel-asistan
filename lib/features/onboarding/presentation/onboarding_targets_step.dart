import 'package:flutter/material.dart';

import '../domain/goal_suggestion.dart';
import '../domain/onboarding_answers.dart';
import 'onboarding_widgets.dart';

/// 3. adım: hesaplanan önerilen hedefler; hepsi düzenlenebilir.
class OnboardingTargetsStep extends StatelessWidget {
  const OnboardingTargetsStep({
    super.key,
    required this.goal,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.steps,
    required this.sleep,
    required this.onReset,
  });

  final OnboardingGoal goal;
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
          subtitle: 'Boyun, kilon, yaşın ve amacına göre hesapladım. '
              'İstediğini değiştir.',
        ),
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
          'Kalori: bazal metabolizma × 1,4 → ${_goalText()}. Protein: kilo başına '
          '1,8 g. Adım 8000, uyku 7,5 saat. Bunlar tahmindir, tıbbi tavsiye '
          'değildir.',
        ),
      ],
    );
  }
}
