import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/avatar/avatar_spec.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_avatar.dart';
import '../domain/story_models.dart';
import 'stories_providers.dart';
import 'story_viewer.dart';

/// Kokpit'in tepesindeki yatay story halkaları (Instagram benzeri).
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  static const double ringSize = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Paylaşım açıksa bugünün başarıları arka planda yazılır.
    ref.watch(storyAchievementSyncProvider);
    final groups = watchStoryGroups(ref);
    final seen = ref.watch(storySeenProvider).valueOrNull ?? const <String>{};

    return SizedBox(
      key: const ValueKey('stories-row'),
      height: ringSize + 26,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final g = groups[i];
          return StoryRing(
            key: ValueKey('story-ring-${g.id}'),
            group: g,
            unseen: g.seenKeys.any((k) => !seen.contains(k)),
            onTap: () => StoryViewer.open(context, groups: groups, initial: i),
          );
        },
      ),
    );
  }
}

/// Tek halka: görülmemişse gün batımı geçişi, görülmüşse gri.
class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.group,
    required this.unseen,
    required this.onTap,
  });

  final StoryGroup group;
  final bool unseen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = StoriesRow.ringSize;
    final Widget inner = switch (group.kind) {
      StoryKind.daily => _IconFace(icon: Icons.wb_sunny_outlined, color: AppColors.sunsetMid),
      StoryKind.tips => _IconFace(icon: Icons.lightbulb_outline_rounded, color: AppColors.accent),
      StoryKind.friend => RitimAvatar(
          choice: group.avatar ?? const AvatarChoice(),
          name: group.label,
          userId: group.friendId,
          size: size - 10,
        ),
    };
    return Semantics(
      button: true,
      label: '${group.label} story${unseen ? ', yeni' : ''}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size + 4,
          child: Column(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: unseen
                        ? SweepGradient(
                            colors: [...AppColors.sunset, AppColors.sunsetStart],
                          )
                        : null,
                    color: unseen ? null : AppColors.textMuted,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                    ),
                    child: ClipOval(child: Center(child: inner)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ExcludeSemantics(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: unseen ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconFace extends StatelessWidget {
  const _IconFace({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceHigh),
      child: SizedBox.expand(child: Icon(icon, color: color, size: 26)),
    );
  }
}
