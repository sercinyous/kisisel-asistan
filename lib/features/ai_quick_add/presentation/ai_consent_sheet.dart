import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/settings_providers.dart';

/// AI hızlı eklemeden önce bir kez açık onay ister. Onay zaten varsa hemen
/// `true` döner; kullanıcı vazgeçerse ya da onay kaydedilemezse `false`.
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref) async {
  if (await ref.read(aiConsentProvider.future)) return true;
  if (!context.mounted) return false;
  final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const AiConsentSheet(),
      ) ??
      false;
  if (!accepted) return false;
  try {
    await ref.read(settingsRepositoryProvider).setAiConsent(true);
    ref.invalidate(aiConsentProvider);
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onay kaydedilemedi. Tekrar dene.')),
      );
    }
    return false;
  }
}

/// AI onay sayfası: neyin, kime gönderildiğini anlatır; Kabul / Vazgeç.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: AppColors.textSecondary, height: 1.4);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'AI kullanımına izin ver',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Hızlı eklemede yazdığın metin, kayda dönüştürülmesi için '
              "Google Gemini'ye gönderilir.",
              style: muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Raporlarının kısa yorumu için yalnızca hesaplanmış sayılar '
              '(ör. görev oranı, ortalama uyku) gönderilir; adın ve e-postan '
              'gönderilmez.',
              style: muted,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Onayını Hesap > Gizlilik ve koşullar ekranından istediğin '
              'zaman geri alabilirsin.',
              style: muted,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('ai-consent-accept'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Kabul ediyorum'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('ai-consent-decline'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
