import 'package:flutter/material.dart';

import '../domain/onboarding_answers.dart';
import 'onboarding_widgets.dart';

/// 4. adım: boy ve kilo. Bağlı sağlık kaynağında ölçüm varsa alanlar ön
/// doldurulur; kullanıcı onaylar ya da düzeltir.
class OnboardingBodyStep extends StatelessWidget {
  const OnboardingBodyStep({
    super.key,
    required this.height,
    required this.weight,
    required this.loading,
    required this.prefilled,
  });

  final TextEditingController height;
  final TextEditingController weight;

  /// Sağlık kaynağından okunuyor.
  final bool loading;

  /// En az bir alan sağlık kaynağından dolduruldu.
  final bool prefilled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Boy ve kilo',
          subtitle: 'Enerji ihtiyacını ve önerilen hedefleri bunlarla '
              'hesaplıyorum.',
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(
              key: Key('onboarding-body-loading'),
              minHeight: 2,
            ),
          ),
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
            key: const Key('onboarding-weight'),
            controller: weight,
            label: 'Kilo',
            suffix: 'kg',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: OnboardingField.decimal,
            validator: OnboardingValidators.weight,
          ),
        ),
        OnboardingHint(
          prefilled
              ? 'Sağlık kaynağındaki son ölçümlerinle doldurdum. '
                  'Doğruysa devam et, değilse düzelt.'
              : 'Kilo ayrıca ilk tartı kaydın olur.',
          key: const Key('onboarding-body-hint'),
        ),
      ],
    );
  }
}
