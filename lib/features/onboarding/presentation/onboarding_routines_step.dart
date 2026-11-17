import 'package:flutter/material.dart';

import '../../../core/templates/routine_templates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'onboarding_widgets.dart';

/// 5. adım: başlangıç rutinleri seçimi (taslak listesi). Hiçbiri seçilmezse
/// kullanıcı boş başlar.
class OnboardingRoutinesStep extends StatelessWidget {
  const OnboardingRoutinesStep({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
  });

  final Set<String> selected;
  final void Function(String id, bool value) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final templates = RoutineTemplates.starters;
    final all = selected.length == templates.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Başlangıç rutinleri',
          subtitle: 'İstediklerini seç; Gün ekranına eklenir. Hiçbirini '
              'seçmezsen boş başlarsın.',
        ),
        BentoCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (final template in templates)
                CheckboxListTile(
                  key: Key('onboarding-routine-${template.id}'),
                  value: selected.contains(template.id),
                  onChanged: (value) => onToggle(template.id, value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.accent,
                  checkColor: AppColors.onAccent,
                  title: Text(template.title),
                  subtitle: Text(template.scheduleLabel),
                ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('onboarding-routines-toggle-all'),
            onPressed: all ? onClear : onSelectAll,
            child: Text(all ? 'Seçimi temizle' : 'Hepsini seç'),
          ),
        ),
        const OnboardingHint(
          'Sonradan Operasyon > Sabitler\'den ekleyip düzenleyebilirsin.',
        ),
      ],
    );
  }
}
