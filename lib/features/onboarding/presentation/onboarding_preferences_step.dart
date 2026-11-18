import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/domain/user_settings.dart';
import 'onboarding_widgets.dart';

/// Bildirim izninin bu adımdaki durumu.
enum OnboardingPermission { unknown, requesting, granted, denied }

/// 4. adım: bildirim izni ve sessiz saatler.
class OnboardingPreferencesStep extends StatelessWidget {
  const OnboardingPreferencesStep({
    super.key,
    required this.notificationsEnabled,
    required this.onNotifications,
    required this.permission,
    required this.onRequestPermission,
    required this.quietEnabled,
    required this.onQuiet,
    required this.quietStart,
    required this.quietEnd,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final bool notificationsEnabled;
  final ValueChanged<bool> onNotifications;
  final OnboardingPermission permission;
  final VoidCallback onRequestPermission;
  final bool quietEnabled;
  final ValueChanged<bool> onQuiet;
  final TimeOfDayValue quietStart;
  final TimeOfDayValue quietEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  String _permissionText() => switch (permission) {
        OnboardingPermission.granted => 'İzin verildi.',
        OnboardingPermission.denied =>
          'İzin verilmedi. iPhone Ayarlar > Bildirimler\'den açabilirsin.',
        OnboardingPermission.requesting => 'İzin isteniyor…',
        OnboardingPermission.unknown =>
          'Hatırlatmaların gelmesi için izin gerekir.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted = permission == OnboardingPermission.granted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Bildirimler',
          subtitle: 'Görev, rutin ve aylık iş hatırlatmaları. İstersen '
              'kapalı bırak, sonra Ayarlar\'dan açabilirsin.',
        ),
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.notifications_rounded,
                label: 'Hatırlatmalar',
                color: AppColors.accent,
              ),
              SwitchListTile(
                key: const Key('onboarding-notifications'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Bildirimler açık'),
                value: notificationsEnabled,
                onChanged: onNotifications,
              ),
              if (notificationsEnabled) ...[
                Text(
                  _permissionText(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: granted ? AppColors.accent : AppColors.textSecondary,
                  ),
                ),
                if (!granted)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      key: const Key('onboarding-request-permission'),
                      onPressed: permission == OnboardingPermission.requesting
                          ? null
                          : onRequestPermission,
                      child: const Text('İzin iste'),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.grid),
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.bedtime_rounded,
                label: 'Sessiz saatler',
                color: AppColors.fitness,
              ),
              SwitchListTile(
                key: const Key('onboarding-quiet'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Sessiz saatlerde bildirim gelmesin'),
                value: quietEnabled,
                onChanged: onQuiet,
              ),
              if (quietEnabled) ...[
                ListTile(
                  key: const Key('onboarding-quiet-start'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.nightlight_round),
                  title: const Text('Başlangıç'),
                  trailing: Text(quietStart.format(),
                      style: theme.textTheme.titleMedium),
                  onTap: onPickStart,
                ),
                ListTile(
                  key: const Key('onboarding-quiet-end'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wb_sunny_rounded),
                  title: const Text('Bitiş'),
                  trailing: Text(quietEnd.format(),
                      style: theme.textTheme.titleMedium),
                  onTap: onPickEnd,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
