import '../features/stories/data/stories_repository.dart';
import '../features/stories/domain/story_models.dart';

/// Demo: iki arkadaşın (Elif, f-1 ve m***, f-2) son 24 saatteki başarıları.
/// Kimlikler `DemoFriendsRepository` ile aynıdır.
MemoryStoriesRepository demoStoriesRepository(DateTime now) {
  FriendStory story(
    String id,
    String owner,
    AchievementKind kind,
    Duration ago, {
    Map<String, dynamic> payload = const {},
    List<StoryReaction> reactions = const [],
  }) {
    final created = now.subtract(ago);
    return FriendStory(
      id: id,
      ownerId: owner,
      kind: kind,
      createdAt: created,
      expiresAt: created.add(const Duration(hours: 24)),
      payload: payload,
      reactions: reactions,
    );
  }

  return MemoryStoriesRepository(
    currentUserId: 'demo-me',
    friendStories: [
      story('demo-s1', 'f-1', AchievementKind.streak7, const Duration(hours: 6),
          payload: const {'streak': 'Adım'}),
      story('demo-s2', 'f-1', AchievementKind.workout, const Duration(hours: 2),
          reactions: const [StoryReaction(userId: 'demo-me', emoji: '💪')]),
      story('demo-s3', 'f-2', AchievementKind.weeklyGoal,
          const Duration(hours: 9)),
    ],
  );
}
