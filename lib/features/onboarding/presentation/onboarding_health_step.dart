import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'onboarding_widgets.dart';

/// Apple Health izninin bu adımdaki durumu.
enum OnboardingHealthAccess { idle, requesting, granted, denied, unavailable }

/// 6. adım: sağlık kaynağı. Apple Health izni burada istenir; Google Health
/// sonra Ayarlar'dan bağlanır.
class OnboardingHealthStep extends StatelessWidget {
  const OnboardingHealthStep({
    super.key,
    required this.access,
    required this.onRequest,
  });

  final OnboardingHealthAccess access;
  final VoidCallback onRequest;

  String _statusText() => switch (access) {
        OnboardingHealthAccess.granted => 'İzin verildi.',
        OnboardingHealthAccess.denied =>
          'İzin verilmedi. iPhone Ayarlar > Sağlık > Veri Erişimi\'nden '
              'açabilirsin.',
        OnboardingHealthAccess.unavailable =>
          'Bu cihazda Apple Health yok. Verilerini elle girebilirsin.',
        OnboardingHealthAccess.requesting => 'İzin isteniyor…',
        OnboardingHealthAccess.idle =>
          'Adım, uyku ve aktif kalori Apple Health\'ten okunur.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = access == OnboardingHealthAccess.granted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Sağlık verisi',
          subtitle: 'Adım, uyku ve aktif kalori için bir kaynak bağla. '
              'Atlayıp sonra da yapabilirsin.',
        ),
        BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.favorite_rounded,
                label: 'Apple Health',
                color: AppColors.danger,
              ),
              const SizedBox(height: 8),
              Text(
                _statusText(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: done ? AppColors.accent : AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (!done && access != OnboardingHealthAccess.unavailable)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    key: const Key('onboarding-health-request'),
                    onPressed: access == OnboardingHealthAccess.requesting
                        ? null
                        : onRequest,
                    child: const Text('Apple Health izni ver'),
                  ),
                ),
            ],
          ),
        ),
        const OnboardingHint(
          'Google Health\'i kullanmak istersen Ayarlar > Bağlantılar\'dan '
          'sonra bağlayabilirsin. Aynı anda tek kaynak veri yazar.',
        ),
      ],
    );
  }
}
