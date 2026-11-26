import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/friends/data/friends_repository.dart';
import 'package:kisisel_asistan/features/friends/domain/friends_models.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_providers.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_friends_row.dart';

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
      expect(
          GoalSummary.fromMap({'metric': 'x', 'shared': false}).metric, isNull);
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
        'share_details': false,
      });
    });

    test('ayrıntı onayı ayrı alan, eski satırda kapalı', () {
      final old = FriendSharing.fromMap({
        'share_steps': true,
        'share_sleep': false,
        'share_calories': true,
      });
      expect(old.shareDetails, isFalse);
      expect(old.detailValueLabels, hasLength(2));
      expect(old.copyWith(details: true).toMap('u')['share_details'], isTrue);
      expect(formatGoalDays(null), isNull);
      expect(
        formatGoalDays(const GoalSummary(
            metric: GoalMetric.steps, shared: true, goalDays: 3, dataDays: 5)),
        '3/5 gün hedef',
      );
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

  group('sıralama', () {
    LeaderboardEntry e(String id, {num? steps, bool self = false}) =>
        LeaderboardEntry(
          userId: id,
          isSelf: self,
          displayName: id,
          email: '$id@x.com',
          stepsToday: steps,
        );

    test('fromMap: Google adı, foto, ham sayılar, null paylaşılmıyor', () {
      final x = LeaderboardEntry.fromMap({
        'user_id': 'u',
        'is_self': false,
        'display_name': 'Sercan Kılıç',
        'email': 'sercan@gmail.com',
        'avatar_url': 'https://a/b.png',
        'steps_today': 8421,
        'steps_week': 40000,
        'sleep_today': null,
        'kcal_week': '1234.5',
      });
      expect(x.initials, 'SK');
      expect(x.avatarUrl, 'https://a/b.png');
      expect(x.value(GoalMetric.steps, RankPeriod.today), 8421);
      expect(x.value(GoalMetric.sleep, RankPeriod.today), isNull);
      expect(x.value(GoalMetric.calories, RankPeriod.week), 1234.5);
      final y = LeaderboardEntry.fromMap(
          {'user_id': 'v', 'display_name': '', 'email': 'ada.lov@x.com'});
      expect(y.displayName, 'ada.lov@x.com');
      expect(y.initials, 'AL');
      expect(y.avatarUrl, isNull);
    });

    test('en iyi önce, paylaşmayan sona', () {
      final r = rankEntries(
        [
          e('a', steps: 100),
          e('b'),
          e('c', steps: 900, self: true),
          e('d', steps: 500)
        ],
        GoalMetric.steps,
        RankPeriod.today,
      );
      expect(r.map((x) => x.userId), ['c', 'd', 'a', 'b']);
    });

    test('kalori sıralanmaz: kendin önce, sonra ada göre (ICG2-11)', () {
      LeaderboardEntry k(String id, num? kcal, {bool self = false}) =>
          LeaderboardEntry(
            userId: id,
            isSelf: self,
            displayName: id,
            email: '$id@x.com',
            kcalWeek: kcal,
          );
      final r = rankEntries(
        [k('c', 9000), k('a', 3000), k('me', 5000, self: true)],
        GoalMetric.calories,
        RankPeriod.week,
      );
      expect(r.map((x) => x.userId), ['me', 'a', 'c']);
    });

    test('adımını paylaşan arkadaş yoksa sıra yok (ICG2-12)', () {
      LeaderboardEntry w(String id, num? steps, {bool self = false}) =>
          LeaderboardEntry(
            userId: id,
            isSelf: self,
            displayName: id,
            email: '$id@x.com',
            stepsWeek: steps,
          );
      expect(weeklyFriendRank([w('me', 0, self: true), w('a', null)]), isNull);
      expect(weeklyFriendRank([w('me', 100, self: true), w('a', 500)]), 2);
    });

    test('biçim', () {
      expect(formatMetricValue(GoalMetric.steps, RankPeriod.today, 12345),
          '12.345 adım');
      expect(formatMetricValue(GoalMetric.sleep, RankPeriod.week, 425),
          'ort. 7 sa 05 dk');
      expect(formatMetricValue(GoalMetric.calories, RankPeriod.today, null),
          'paylaşmıyor');
    });

    test('demo depo kendini ve arkadaşları döner', () async {
      final l =
          await DemoFriendsRepository().leaderboard(DateTime(2026, 11, 16));
      expect(l.where((x) => x.isSelf).length, 1);
      expect(l.length, 3);
    });
  });
}
