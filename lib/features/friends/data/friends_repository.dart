import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/friends_models.dart';

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SupabaseFriendsRepository(ref.watch(supabaseClientProvider));
});

abstract class FriendsRepository {
  /// Her durumda 'İstek gönderildi' döner (e-posta sorgulanamaz).
  Future<String> sendRequest(String targetEmail);
  Future<List<IncomingRequest>> incomingRequests();
  Future<List<OutgoingRequest>> outgoingRequests();
  Future<void> cancelRequest(String requestId);
  Future<void> respond(String requestId, {required bool accept});
  Future<List<Friend>> friends();
  Future<List<GoalSummary>> goalSummary(String friendId, DateTime weekStart);
  Future<List<LeaderboardEntry>> leaderboard(DateTime weekStart);
  Future<void> leave(String friendId);
  Future<FriendSharing> mySharing();
  Future<FriendSharing> saveSharing(FriendSharing sharing);
}

List<Map<String, dynamic>> _rows(Object? data) =>
    (data as List? ?? const []).cast<Map<String, dynamic>>();

class SupabaseFriendsRepository implements FriendsRepository {
  const SupabaseFriendsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  @override
  Future<String> sendRequest(String targetEmail) async {
    final res = await _client
        .rpc('send_friend_request', params: {'target_email': targetEmail.trim()});
    return res as String? ?? 'İstek gönderildi';
  }

  @override
  Future<List<IncomingRequest>> incomingRequests() async =>
      _rows(await _client.rpc('my_incoming_requests'))
          .map(IncomingRequest.fromMap)
          .toList();

  @override
  Future<List<OutgoingRequest>> outgoingRequests() async =>
      _rows(await _client.rpc('my_outgoing_requests'))
          .map(OutgoingRequest.fromMap)
          .toList();

  @override
  Future<void> cancelRequest(String requestId) =>
      _client.rpc('cancel_friend_request', params: {'request_id': requestId});

  @override
  Future<void> respond(String requestId, {required bool accept}) =>
      _client.rpc('respond_friend_request',
          params: {'request_id': requestId, 'accept': accept});

  @override
  Future<List<Friend>> friends() async =>
      _rows(await _client.rpc('my_friends')).map(Friend.fromMap).toList();

  @override
  Future<List<GoalSummary>> goalSummary(
    String friendId,
    DateTime weekStart,
  ) async =>
      _rows(await _client.rpc('friend_goal_summary', params: {
        'friend': friendId,
        'week_start': isoDate(weekStart),
      })).map(GoalSummary.fromMap).toList();

  @override
  Future<List<LeaderboardEntry>> leaderboard(DateTime weekStart) async =>
      _rows(await _client.rpc('friend_leaderboard', params: {
        'week_start': isoDate(weekStart),
      })).map(LeaderboardEntry.fromMap).toList();

  @override
  Future<void> leave(String friendId) =>
      _client.rpc('leave_friendship', params: {'friend': friendId});

  @override
  Future<FriendSharing> mySharing() async => FriendSharing.fromMap(
        await _client
            .from('friend_sharing')
            .select()
            .eq('user_id', _userId)
            .maybeSingle(),
      );

  @override
  Future<FriendSharing> saveSharing(FriendSharing sharing) async =>
      FriendSharing.fromMap(
        await _client
            .from('friend_sharing')
            .upsert(sharing.toMap(_userId), onConflict: 'user_id')
            .select()
            .single(),
      );
}

/// Tarayıcı demosu: bellekte duran tutarlı sahte depo.
class DemoFriendsRepository implements FriendsRepository {
  DemoFriendsRepository()
      : _incoming = [
          IncomingRequest(
            id: 'in-1',
            fromName: 'Deniz',
            createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          ),
        ],
        _outgoing = [],
        _friends = [
          const Friend(
            friendId: 'f-1',
            displayName: 'Elif',
            shareSteps: true,
            shareSleep: true,
            shareCalories: false,
          ),
          const Friend(
            friendId: 'f-2',
            displayName: 'm***@gmail.com',
            shareSteps: false,
            shareSleep: false,
            shareCalories: false,
          ),
        ];

  final List<IncomingRequest> _incoming;
  final List<OutgoingRequest> _outgoing;
  final List<Friend> _friends;
  FriendSharing _sharing = const FriendSharing();
  int _seq = 0;

  @override
  Future<String> sendRequest(String targetEmail) async {
    _outgoing.add(OutgoingRequest(
      id: 'out-${_seq++}',
      targetEmail: targetEmail.trim().toLowerCase(),
      createdAt: DateTime.now(),
    ));
    return 'İstek gönderildi';
  }

  @override
  Future<List<IncomingRequest>> incomingRequests() async => [..._incoming];

  @override
  Future<List<OutgoingRequest>> outgoingRequests() async => [..._outgoing];

  @override
  Future<void> cancelRequest(String requestId) async =>
      _outgoing.removeWhere((r) => r.id == requestId);

  @override
  Future<void> respond(String requestId, {required bool accept}) async {
    final i = _incoming.indexWhere((r) => r.id == requestId);
    if (i < 0) return;
    final r = _incoming.removeAt(i);
    if (accept) {
      _friends.add(Friend(
        friendId: 'f-${r.id}',
        displayName: r.fromName,
        shareSteps: false,
        shareSleep: false,
        shareCalories: false,
      ));
    }
  }

  @override
  Future<List<Friend>> friends() async => [..._friends];

  @override
  Future<List<GoalSummary>> goalSummary(
    String friendId,
    DateTime weekStart,
  ) async {
    final f = _friends.firstWhere((e) => e.friendId == friendId);
    GoalSummary s(GoalMetric m, bool shared, int goal) => GoalSummary(
          metric: m,
          shared: shared,
          goalDays: shared ? goal : 0,
          dataDays: shared ? 5 : 0,
        );
    return [
      s(GoalMetric.steps, f.shareSteps, 4),
      s(GoalMetric.sleep, f.shareSleep, 3),
      s(GoalMetric.calories, f.shareCalories, 2),
    ];
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(DateTime weekStart) async {
    final out = <LeaderboardEntry>[
      const LeaderboardEntry(
        userId: 'me',
        isSelf: true,
        displayName: 'Sen',
        email: 'ben@example.com',
        stepsToday: 6420,
        stepsWeek: 31250,
        sleepToday: 412,
        sleepWeekAvg: 428,
        kcalToday: 1840,
        kcalWeek: 9870,
      ),
    ];
    var i = 0;
    for (final f in _friends) {
      i++;
      out.add(LeaderboardEntry(
        userId: f.friendId,
        isSelf: false,
        displayName: f.displayName,
        email: f.displayName.contains('@')
            ? f.displayName
            : '${f.displayName.toLowerCase()}@example.com',
        stepsToday: f.shareSteps ? 4000 + i * 2100 : null,
        stepsWeek: f.shareSteps ? 25000 + i * 9000 : null,
        sleepToday: f.shareSleep ? 380 + i * 20 : null,
        sleepWeekAvg: f.shareSleep ? 400 + i * 15 : null,
        kcalToday: f.shareCalories ? 1600 + i * 150 : null,
        kcalWeek: f.shareCalories ? 9000 + i * 700 : null,
      ));
    }
    return out;
  }

  @override
  Future<void> leave(String friendId) async =>
      _friends.removeWhere((f) => f.friendId == friendId);

  @override
  Future<FriendSharing> mySharing() async => _sharing;

  @override
  Future<FriendSharing> saveSharing(FriendSharing sharing) async =>
      _sharing = sharing;
}
