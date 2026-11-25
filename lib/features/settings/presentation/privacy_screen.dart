import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../data/settings_repository.dart';
import '../domain/privacy_text.dart';
import 'settings_providers.dart';

/// Hesap > Gizlilik ve koşullar: AI onayı anahtarı; hangi verinin toplandığı,
/// kimin gördüğü, saklama ve silme.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Gizlilik ve koşullar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          120,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.grid),
            child: AiConsentCard(),
          ),
          for (final section in privacySections)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.grid),
              child: BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final paragraph in section.paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          paragraph,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// AI (Gemini) onayını veren ya da geri alan anahtar.
class AiConsentCard extends ConsumerStatefulWidget {
  const AiConsentCard({super.key});

  @override
  ConsumerState<AiConsentCard> createState() => _AiConsentCardState();
}

class _AiConsentCardState extends ConsumerState<AiConsentCard> {
  bool _saving = false;

  Future<void> _set(bool granted) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).setAiConsent(granted);
      ref.invalidate(aiConsentProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi. Tekrar dene.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final consent = ref.watch(aiConsentProvider).valueOrNull ?? false;
    return BentoCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: SwitchListTile.adaptive(
        key: const Key('privacy-ai-consent'),
        value: consent,
        onChanged: _saving ? null : _set,
        title: const Text('AI özellikleri (Google Gemini)'),
        subtitle: Text(
          consent
              ? 'Hızlı ekleme metnin ve rapor sayıları Gemini\'ye gönderilir.'
              : 'Kapalı: hiçbir veri Gemini\'ye gönderilmez, raporlar AI '
                  'yorumu olmadan oluşur.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
