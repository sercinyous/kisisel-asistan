import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../domain/privacy_text.dart';
import '../domain/terms_text.dart';

/// Metin bölümlerini kart kart gösteren basit okuma ekranı (koşullar ve
/// giriş öncesi gizlilik metni).
class LegalTextScreen extends StatelessWidget {
  const LegalTextScreen({
    super.key,
    required this.title,
    required this.sections,
  });

  /// Kullanım koşulları.
  const LegalTextScreen.terms({super.key})
      : title = 'Kullanım koşulları',
        sections = termsSections;

  /// Gizlilik metni (oturum açmadan okunabilir; AI onay anahtarı yok).
  const LegalTextScreen.privacy({super.key})
      : title = 'Gizlilik metni',
        sections = privacySections;

  final String title;
  final List<PrivacySection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          120,
        ),
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.grid),
              child: BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title, style: theme.textTheme.titleMedium),
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
