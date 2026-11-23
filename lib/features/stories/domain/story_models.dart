import '../../../core/avatar/avatar_spec.dart';

/// Story halkasının türü.
enum StoryKind {
  /// Günün özeti (kendi verinden).
  daily,

  /// Hedefe göre ipucu ve bugünün hatırlatmaları.
  tips,

  /// Arkadaşın otomatik başarıları (24 saat).
  friend,
}

/// Kartın pastel tonu; sunum katmanında `AppColors` rolüne çevrilir.
enum StoryTone { mint, peach, lav, sky, butter, rose }

/// Arkadaşlara verilebilen tepkiler (sunucudaki check ile aynı küme).
const List<String> storyReactionEmojis = ['👏', '🔥', '💪'];

/// Story'de bir kart.
class StorySlide {
  const StorySlide({
    required this.id,
    required this.eyebrow,
    required this.title,
    this.value,
    this.body,
    this.progress,
    this.tone = StoryTone.mint,
  });

  final String id;

  /// Üstteki küçük etiket ("DÜN", "İPUCU" …).
  final String eyebrow;
  final String title;

  /// Büyük sayı ("8.240 adım"); yoksa `null`.
  final String? value;
  final String? body;

  /// 0–1 ilerleme halkası/çubuğu; yoksa `null`.
  final double? progress;
  final StoryTone tone;
}

/// Bir halka: aynı kaynaktan gelen kartlar.
class StoryGroup {
  const StoryGroup({
    required this.id,
    required this.kind,
    required this.label,
    required this.slides,
    this.friendId,
    this.avatar,
    this.stories = const [],
  });

  /// Görülme anahtarı ("daily-2026-11-23", "friend-`uid`").
  final String id;
  final StoryKind kind;

  /// Halkanın altındaki kısa ad.
  final String label;
  final List<StorySlide> slides;
  final String? friendId;
  final AvatarChoice? avatar;

  /// Arkadaş halkasında kart sırasıyla eşleşen story satırları.
  final List<FriendStory> stories;

  /// Her kartın ayrı görülme anahtarı.
  List<String> get seenKeys => [for (final s in slides) '$id/${s.id}'];
}

/// Arkadaşlara paylaşılan başarı türleri (sunucudaki check ile aynı).
enum AchievementKind {
  streak7('streak_7'),
  streak14('streak_14'),
  streak30('streak_30'),
  weeklyGoal('weekly_goal'),
  workout('workout'),
  weightGoal('weight_goal');

  const AchievementKind(this.dbValue);

  final String dbValue;

  static AchievementKind? tryParse(Object? value) {
    for (final k in values) {
      if (k.dbValue == value) return k;
    }
    return null;
  }

  /// Seri eşikleri (gün) ve karşılık gelen tür.
  static const Map<int, AchievementKind> streakMilestones = {
    7: streak7,
    14: streak14,
    30: streak30,
  };
}

/// Yazılmayı bekleyen başarı (istemcide tespit edildi).
class PendingAchievement {
  const PendingAchievement(this.kind, this.day, [this.payload = const {}]);

  final AchievementKind kind;

  /// Yerel gün (00:00); tür + gün başına tek satır.
  final DateTime day;

  /// Küçük, kimlik içermeyen ayrıntı (ör. {'streak': 'Adım'}).
  final Map<String, Object> payload;

  String get dedupeKey => '${kind.dbValue}:${day.year}-${day.month}-${day.day}';
}

/// Bir story'ye verilen tepki.
class StoryReaction {
  const StoryReaction({required this.userId, required this.emoji});

  factory StoryReaction.fromMap(Map<String, dynamic> m) => StoryReaction(
        userId: m['user_id'] as String,
        emoji: m['emoji'] as String,
      );

  final String userId;
  final String emoji;
}

/// friend_stories satırı.
class FriendStory {
  const FriendStory({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
    this.payload = const {},
    this.reactions = const [],
  });

  static FriendStory? tryFromMap(Map<String, dynamic> m) {
    final kind = AchievementKind.tryParse(m['kind']);
    final created = DateTime.tryParse('${m['created_at']}');
    final expires = DateTime.tryParse('${m['expires_at']}');
    if (kind == null || created == null || expires == null) return null;
    final payload = m['payload'];
    final reactions = m['story_reactions'];
    return FriendStory(
      id: m['id'] as String,
      ownerId: m['user_id'] as String,
      kind: kind,
      createdAt: created.toLocal(),
      expiresAt: expires.toLocal(),
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
      reactions: reactions is List
          ? reactions
              .whereType<Map<dynamic, dynamic>>()
              .map((r) => StoryReaction.fromMap(Map<String, dynamic>.from(r)))
              .toList()
          : const [],
    );
  }

  final String id;
  final String ownerId;
  final AchievementKind kind;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic> payload;
  final List<StoryReaction> reactions;

  bool isVisibleAt(DateTime now) => expiresAt.isAfter(now);

  /// [userId]'nin bu story'ye verdiği tepki.
  String? reactionOf(String? userId) {
    for (final r in reactions) {
      if (r.userId == userId) return r.emoji;
    }
    return null;
  }

  FriendStory withReaction(String userId, String? emoji) => FriendStory(
        id: id,
        ownerId: ownerId,
        kind: kind,
        createdAt: createdAt,
        expiresAt: expiresAt,
        payload: payload,
        reactions: [
          for (final r in reactions)
            if (r.userId != userId) r,
          if (emoji != null) StoryReaction(userId: userId, emoji: emoji),
        ],
      );
}
