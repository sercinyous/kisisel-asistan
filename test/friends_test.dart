import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/friends/data/friends_repository.dart';
import 'package:kisisel_asistan/features/friends/domain/friends_models.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_providers.dart';

void main() {
  group('eşlemeler', () {
    test('Friend ve GoalSummary', () {
      final f = Friend.fromMap({
        'friend_id': 'a',
        'display_name': 's***@gmail.com',
        'share_steps': true,
        'share_sleep': null,
        'share_calories': false,
      });
      expect(f.shareSteps, isTrue);
      expect(f.shareSleep, isFalse);
      final s = GoalSummary.fromMap(
        {'metric': 'sleep', 'shared': true, 'goal_days': 3, 'data_days': 5},
      );
      expect(s.metric, GoalMetric.sleep);
      expect(s.goalDays, 3);
      expect(GoalSummary.fromMap({'metric': 'x', 'shared': false}).metric, isNull);
    });

    test('istekler', () {
      final i = IncomingRequest.fromMap({
        'id': '1',
        'from_name': 'Ada',
        'created_at': '2026-11-17T10:00:00Z',
      });
      expect(i.fromName, 'Ada');
      final o = OutgoingRequest.fromMap({
        'id': '2',
        'target_email': 'b@c.com',
        'created_at': '2026-11-17T10:00:00Z',
      });
      expect(o.targetEmail, 'b@c.com');
    });

    test('paylaşım varsayılanı kapalı ve toMap', () {
      final s = FriendSharing.fromMap(null);
      expect(s.shareSteps || s.shareSleep || s.shareCalories, isFalse);
      expect(s.copyWith(sleep: true).toMap('u'), {
        'user_id': 'u',
        'share_steps': false,
        'share_sleep': true,
        'share_calories': false,
      });
    });
  });

  group('hafta başı', () {
    test('Pazartesi', () {
      expect(weekStartOf(DateTime(2026, 11, 16)), DateTime(2026, 11, 16));
      expect(weekStartOf(DateTime(2026, 11, 22, 23)), DateTime(2026, 11, 16));
      expect(weekStartOf(DateTime(2026, 11, 17)), DateTime(2026, 11, 16));
    });
    test('ay sınırı ve biçim', () {
      expect(weekStartOf(DateTime(2026, 12, 2)), DateTime(2026, 11, 30));
      expect(isoDate(DateTime(2026, 3, 5)), '2026-03-05');
    });
  });

  group('rozet sağlayıcısı', () {
    test('gelen davet sayısını verir, kabulden sonra yenilenince düşer',
        () async {
      final repo = DemoFriendsRepository();
      final c = ProviderContainer(
        overrides: [friendsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      expect(await c.read(pendingFriendRequestCountProvider.future), 1);
      await repo.respond('in-1', accept: true);
      c.invalidate(pendingFriendRequestCountProvider);
      expect(await c.read(pendingFriendRequestCountProvider.future), 0);
      expect((await repo.friends()).length, 3);
    });

    test('paylaşmayan arkadaş shared=false döner', () async {
      final repo = DemoFriendsRepository();
      final s = await repo.goalSummary('f-2', DateTime(2026, 11, 16));
      expect(s.every((e) => !e.shared), isTrue);
    });
  });
}
