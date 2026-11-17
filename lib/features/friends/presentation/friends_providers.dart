import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/friends_repository.dart';
import '../domain/friends_models.dart';

final incomingRequestsProvider = FutureProvider<List<IncomingRequest>>(
  (ref) => ref.watch(friendsRepositoryProvider).incomingRequests(),
);

final outgoingRequestsProvider = FutureProvider<List<OutgoingRequest>>(
  (ref) => ref.watch(friendsRepositoryProvider).outgoingRequests(),
);

final mySharingProvider = FutureProvider<FriendSharing>(
  (ref) => ref.watch(friendsRepositoryProvider).mySharing(),
);

/// Arkadaşlar ve bu haftanın (Pazartesi başlangıçlı) hedef özetleri.
final friendsWithSummaryProvider =
    FutureProvider<List<FriendWithSummary>>((ref) async {
  final repo = ref.watch(friendsRepositoryProvider);
  final week = weekStartOf(DateTime.now());
  final list = await repo.friends();
  return Future.wait(
    list.map(
      (f) async => FriendWithSummary(
        friend: f,
        summaries: await repo
            .goalSummary(f.friendId, week)
            .catchError((_) => <GoalSummary>[]),
      ),
    ),
  );
});

/// Bekleyen gelen davet sayısı (rozet). Uygulama açılınca ve öne gelince
/// `FriendsButton` tarafından yenilenir.
final pendingFriendRequestCountProvider = FutureProvider<int>((ref) async {
  final list = await ref.watch(friendsRepositoryProvider).incomingRequests();
  return list.length;
});

/// Tüm arkadaşlık verisini yeniden okutur.
void refreshFriends(WidgetRef ref) {
  ref.invalidate(incomingRequestsProvider);
  ref.invalidate(outgoingRequestsProvider);
  ref.invalidate(friendsWithSummaryProvider);
  ref.invalidate(mySharingProvider);
  ref.invalidate(pendingFriendRequestCountProvider);
}
