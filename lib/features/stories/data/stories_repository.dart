import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/story_models.dart';

final storiesRepositoryProvider = Provider<StoriesRepository>((ref) {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SupabaseStoriesRepository(ref.watch(supabaseClientProvider));
});

abstract class StoriesRepository {
  /// Oturumdaki kullanıcının kimliği (tepkileri eşlemek için).
  String? get currentUserId;

  /// Arkadaşların süresi dolmamış story'leri (benim tepkimle birlikte).
  Future<List<FriendStory>> friendStories();

  /// Başarıyı yazar; aynı tür + gün zaten varsa sessizce atlanır.
  Future<void> publish(PendingAchievement achievement);

  /// Tepki verir; [emoji] `null` ise tepkiyi kaldırır.
  Future<void> react(String storyId, String? emoji);
}

class SupabaseStoriesRepository implements StoriesRepository {
  const SupabaseStoriesRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  String get _userId {
    final id = currentUserId;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  @override
  Future<List<FriendStory>> friendStories() async {
    final rows = await _client
        .from('friend_stories')
        .select('id, user_id, kind, payload, created_at, expires_at, '
            'story_reactions(user_id, emoji)')
        .neq('user_id', _userId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at');
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        if (FriendStory.tryFromMap(row) case final story?) story,
    ];
  }

  @override
  Future<void> publish(PendingAchievement achievement) async {
    final d = achievement.day;
    await _client.from('friend_stories').upsert(
      {
        'user_id': _userId,
        'kind': achievement.kind.dbValue,
        'day': '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
        'payload': achievement.payload,
      },
      onConflict: 'user_id,kind,day',
      ignoreDuplicates: true,
    );
  }

  @override
  Future<void> react(String storyId, String? emoji) async {
    final uid = _userId;
    await _client
        .from('story_reactions')
        .delete()
        .eq('story_id', storyId)
        .eq('user_id', uid);
    if (emoji == null) return;
    await _client
        .from('story_reactions')
        .insert({'story_id': storyId, 'user_id': uid, 'emoji': emoji});
  }
}

/// Bellekte duran depo: demo ve testler.
class MemoryStoriesRepository implements StoriesRepository {
  MemoryStoriesRepository({
    this.currentUserId = 'me',
    List<FriendStory> friendStories = const [],
  }) : _friendStories = [...friendStories];

  @override
  final String? currentUserId;

  final List<FriendStory> _friendStories;

  /// [publish] ile yazılan başarılar.
  final List<PendingAchievement> published = [];

  @override
  Future<List<FriendStory>> friendStories() async {
    final now = DateTime.now();
    return [
      for (final s in _friendStories)
        if (s.isVisibleAt(now)) s,
    ];
  }

  @override
  Future<void> publish(PendingAchievement achievement) async {
    if (published.any((p) => p.dedupeKey == achievement.dedupeKey)) return;
    published.add(achievement);
  }

  @override
  Future<void> react(String storyId, String? emoji) async {
    final uid = currentUserId;
    if (uid == null) return;
    for (var i = 0; i < _friendStories.length; i++) {
      if (_friendStories[i].id == storyId) {
        _friendStories[i] = _friendStories[i].withReaction(uid, emoji);
      }
    }
  }
}
