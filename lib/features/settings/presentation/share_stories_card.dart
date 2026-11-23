import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'settings_providers.dart';
import 'settings_widgets.dart';

/// Ayarlar: "Başarılarımı story olarak paylaş" (varsayılan kapalı).
/// Kapalıyken arkadaşlara hiçbir başarı yazılmaz; kapatınca sunucu mevcut
/// story'leri siler.
class ShareStoriesCard extends ConsumerStatefulWidget {
  const ShareStoriesCard({super.key});

  @override
  ConsumerState<ShareStoriesCard> createState() => _ShareStoriesCardState();
}

class _ShareStoriesCardState extends ConsumerState<ShareStoriesCard> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    final current = ref.read(userSettingsProvider).valueOrNull;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(userSettingsProvider.notifier)
          .save(current.copyWith(shareStories: value));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedilemedi. Tekrar dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    final available = settings != null && settings.shareStoriesColumn;
    return BentoCard(
      key: const Key('settings-share-stories'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPadding),
      child: SettingsSwitchRow(
        title: 'Başarılarımı story olarak paylaş',
        subtitle: available
            ? 'Seri, haftalık hedef, antrenman ve kilo hedefi başarıların '
                'arkadaşlarına 24 saat görünür. Sayılar ve sağlık verilerin paylaşılmaz.'
            : 'Bu özellik için sunucu güncellemesi bekleniyor.',
        value: settings?.shareStories ?? false,
        onChanged: !available || _saving ? null : _toggle,
      ),
    );
  }
}
