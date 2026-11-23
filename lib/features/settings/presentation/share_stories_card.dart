import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../stories/domain/story_builder.dart';
import '../../stories/domain/story_models.dart';
import '../../stories/presentation/stories_providers.dart';
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
    final sharing = available && settings.shareStories;
    final mine = sharing
        ? ref.watch(myStoriesProvider).valueOrNull ?? const <FriendStory>[]
        : const <FriendStory>[];
    final names = mine.isEmpty
        ? const <String, String>{}
        : ref.watch(storyFriendNamesProvider).valueOrNull ??
            const <String, String>{};
    final toggle = SettingsSwitchRow(
      title: 'Başarılarımı story olarak paylaş',
      subtitle: available
          ? 'Seri, haftalık hedef, antrenman ve kilo hedefi başarıların '
              'arkadaşlarına 24 saat görünür. Arkadaşların başarının türünü '
              '(ör. "7 günlük Adım serisi", "Kilo hedefine ulaştı") görür; '
              'adım, kalori ve kilo değerlerin paylaşılmaz.'
          : 'Bu özellik için sunucu güncellemesi bekleniyor.',
      value: settings?.shareStories ?? false,
      onChanged: !available || _saving ? null : _toggle,
    );
    return BentoCard(
      key: const Key('settings-share-stories'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPadding),
      child: mine.isEmpty
          ? toggle
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                toggle,
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    key: const Key('settings-my-stories'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Yayındaki story\'lerin',
                        style: TextStyle(
                          fontSize: AppType.cardTitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      for (final story in mine)
                        _MyStoryRow(story: story, names: names),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Kendi story'm ve kimin hangi tepkiyi verdiği.
class _MyStoryRow extends StatelessWidget {
  const _MyStoryRow({required this.story, required this.names});

  final FriendStory story;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final reactions = story.reactions.isEmpty
        ? 'Henüz tepki yok'
        : story.reactions
            .map((r) => '${names[r.userId] ?? 'Arkadaşın'} ${r.emoji}')
            .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            StoryBuilder.achievementSlide(story).title,
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            reactions,
            style: TextStyle(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
