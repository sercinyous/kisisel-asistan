import 'package:flutter/material.dart';

import '../../health/domain/energy_balance.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/onboarding_answers.dart';
import 'onboarding_widgets.dart';

/// 2. adım: sorular (görünen ad, boy, doğum yılı, cinsiyet, kilo, hedef kilo,
/// amaç, isteğe bağlı iş tanımı). Durum üst ekrandadır.
class OnboardingProfileStep extends StatelessWidget {
  const OnboardingProfileStep({
    super.key,
    required this.name,
    required this.height,
    required this.birthYear,
    required this.weight,
    required this.targetWeight,
    required this.work,
    required this.sex,
    required this.onSex,
    required this.goal,
    required this.onGoal,
    required this.nowYear,
  });

  final TextEditingController name;
  final TextEditingController height;
  final TextEditingController birthYear;
  final TextEditingController weight;
  final TextEditingController targetWeight;
  final TextEditingController work;
  final Sex? sex;
  final ValueChanged<Sex> onSex;
  final OnboardingGoal? goal;
  final ValueChanged<OnboardingGoal> onGoal;
  final int nowYear;

  static const List<(Sex, String)> sexOptions = [
    (Sex.female, 'Kadın'),
    (Sex.male, 'Erkek'),
    (Sex.unspecified, 'Belirtmek istemiyorum'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Seni tanıyalım',
          subtitle: 'Hedeflerini senin için hesaplayabilmem için birkaç soru. '
              'Hepsini sonra Ayarlar\'dan değiştirebilirsin.',
        ),
        OnboardingField(
          key: const Key('onboarding-name'),
          controller: name,
          label: 'Görünen ad',
          helper: 'Arkadaşların seni bu adla görür.',
          maxLength: UserSettings.displayNameMax,
          textCapitalization: TextCapitalization.words,
          validator: OnboardingValidators.displayName,
        ),
        const SizedBox(height: 12),
        OnboardingFieldRow(
          left: OnboardingField(
            key: const Key('onboarding-height'),
            controller: height,
            label: 'Boy',
            suffix: 'cm',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            maxLength: 3,
            validator: OnboardingValidators.height,
          ),
          right: OnboardingField(
            key: const Key('onboarding-birth-year'),
            controller: birthYear,
            label: 'Doğum yılı',
            keyboardType: TextInputType.number,
            inputFormatters: OnboardingField.digitsOnly,
            maxLength: 4,
            validator: (value) =>
                OnboardingValidators.birthYear(value, nowYear: nowYear),
          ),
        ),
        const OnboardingLabel('Cinsiyet'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (value, label) in sexOptions)
              ChoiceChip(
                key: Key('onboarding-sex-${value.name}'),
                label: Text(label),
                showCheckmark: false,
                selected: sex == value,
                onSelected: (_) => onSex(value),
              ),
          ],
        ),
        const OnboardingHint(
          'Yalnızca enerji ihtiyacı tahmininde kullanılır.',
        ),
        const SizedBox(height: 16),
        OnboardingFieldRow(
          left: OnboardingField(
            key: const Key('onboarding-weight'),
            controller: weight,
            label: 'Kilo',
            suffix: 'kg',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: OnboardingField.decimal,
            validator: OnboardingValidators.weight,
          ),
          right: OnboardingField(
            key: const Key('onboarding-target-weight'),
            controller: targetWeight,
            label: 'Hedef kilo',
            suffix: 'kg',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: OnboardingField.decimal,
            validator: OnboardingValidators.targetWeight,
          ),
        ),
        const OnboardingHint(
          'Hedef kiloyu boş bırakırsan şimdiki kilon hedef olur.',
        ),
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
          key: const Key('onboarding-work'),
          controller: work,
          label: 'Ne iş yapıyorsun? (isteğe bağlı)',
          helper: 'Yapay zekâ seni daha iyi anlasın diye; yalnızca AI '
              'komutuna girer, kimseyle paylaşılmaz.',
          maxLength: UserSettings.workDescriptionMax,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          validator: OnboardingValidators.workDescription,
        ),
      ],
    );
  }
}
