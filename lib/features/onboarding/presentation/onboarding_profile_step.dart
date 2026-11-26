import 'package:flutter/material.dart';

import '../../health/domain/energy_balance.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/onboarding_answers.dart';
import 'onboarding_widgets.dart';

/// Profil adımında seçilebilen saat dilimleri (IANA). Cihazın dilimi listede
/// yoksa başa eklenir.
const List<(String, String)> onboardingTimezones = [
  ('Europe/Istanbul', 'İstanbul (GMT+3)'),
  ('Europe/London', 'Londra'),
  ('Europe/Berlin', 'Berlin'),
  ('Europe/Amsterdam', 'Amsterdam'),
  ('Europe/Paris', 'Paris'),
  ('Europe/Moscow', 'Moskova'),
  ('Asia/Dubai', 'Dubai'),
  ('Asia/Baku', 'Bakü'),
  ('Asia/Tokyo', 'Tokyo'),
  ('America/New_York', 'New York'),
  ('America/Chicago', 'Chicago'),
  ('America/Los_Angeles', 'Los Angeles'),
  ('UTC', 'UTC'),
];

/// 2. adım: profil (görünen ad, doğum yılı, isteğe bağlı cinsiyet, saat
/// dilimi, isteğe bağlı iş tanımı). Durum üst ekrandadır.
class OnboardingProfileStep extends StatelessWidget {
  const OnboardingProfileStep({
    super.key,
    required this.name,
    required this.birthYear,
    required this.work,
    required this.sex,
    required this.onSex,
    required this.timezone,
    required this.onTimezone,
    required this.nowYear,
  });

  final TextEditingController name;
  final TextEditingController birthYear;
  final TextEditingController work;
  final Sex? sex;
  final ValueChanged<Sex> onSex;
  final String timezone;
  final ValueChanged<String> onTimezone;
  final int nowYear;

  static const List<(Sex, String)> sexOptions = [
    (Sex.female, 'Kadın'),
    (Sex.male, 'Erkek'),
    (Sex.unspecified, 'Belirtmek istemiyorum'),
  ];

  @override
  Widget build(BuildContext context) {
    final zones = [
      if (!onboardingTimezones.any((z) => z.$1 == timezone))
        (timezone, timezone),
      ...onboardingTimezones,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Seni tanıyalım',
          subtitle: 'Birkaç kısa soru. Hepsini sonra Hesap > Profil ve '
              'hedefler\'den değiştirebilirsin.',
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
        OnboardingField(
          key: const Key('onboarding-birth-year'),
          controller: birthYear,
          label: 'Doğum yılı (isteğe bağlı)',
          keyboardType: TextInputType.number,
          inputFormatters: OnboardingField.digitsOnly,
          maxLength: 4,
          validator: (value) =>
              OnboardingValidators.birthYear(value, nowYear: nowYear),
        ),
        const OnboardingLabel('Cinsiyet (isteğe bağlı)'),
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
        DropdownButtonFormField<String>(
          key: const Key('onboarding-timezone'),
          initialValue: timezone,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Saat dilimi',
            helperText: 'Günlük ve haftalık raporlar bu saate göre kesilir.',
          ),
          items: [
            for (final (id, label) in zones)
              DropdownMenuItem(value: id, child: Text(label)),
          ],
          onChanged: (value) {
            if (value != null) onTimezone(value);
          },
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
