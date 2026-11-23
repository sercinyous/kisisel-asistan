import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/avatar/avatar_spec.dart';
import 'package:kisisel_asistan/features/health/domain/goal_mode.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/stories/data/stories_repository.dart';
import 'package:kisisel_asistan/features/stories/data/story_publisher.dart';
import 'package:kisisel_asistan/features/stories/data/story_seen_store.dart';
import 'package:kisisel_asistan/features/stories/domain/story_builder.dart';
import 'package:kisisel_asistan/features/stories/domain/story_models.dart';
import 'package:kisisel_asistan/features/stories/presentation/stories_providers.dart';
import 'package:kisisel_asistan/features/stories/presentation/story_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = DateTime(2026, 11, 23);

FriendStory _story(String id, String owner, AchievementKind kind,
        {Duration ago = const Duration(hours: 1)}) =>
    FriendStory(
      id: id,
      ownerId: owner,
      kind: kind,
      createdAt: DateTime.now().subtract(ago),
      expiresAt: DateTime.now().subtract(ago).add(const Duration(hours: 24)),
    );

void main() {
  group('Günün özeti', () {
    test('veri olan başlıklar için kart üretir', () {
      final g = StoryBuilder.dailySummary(DailySummaryInput(
        today: _today,
        stepsToday: 4200,
        stepsYesterday: 9100,
        stepGoal: 8000,
        kcalToday: 1500,
        kcalTarget: 2000,
        tasksDone: 2,
        tasksTotal: 3,
        streaks: const {'Adım': 7, 'Kayıt': 3, 'Açık': 0},
      ));
      expect(g.id, 'daily-2026-11-23');
      expect(g.slides.map((s) => s.id),
          ['steps-yesterday', 'steps-today', 'kcal', 'tasks', 'streaks']);
      expect(g.slides.first.title, 'Adım hedefini tutturdun');
      expect(g.slides.first.value, '9.100 adım');
      expect(g.slides[2].body, 'Hedefin 500 kcal altındasın.');
      expect(g.slides[3].value, '2 / 3');
      expect(g.slides[4].title, 'Adım serin 7 gün');
      expect(g.slides[4].body, 'Kayıt 3 gün');
    });

    test('veri yoksa tek karşılama kartı', () {
      final g = StoryBuilder.dailySummary(DailySummaryInput(today: _today));
      expect(g.slides.single.id, 'empty');
    });
  });

  group('İpuçları', () {
    test('aynı gün aynı, ertesi gün farklı; hedefe göre', () {
      final a = StoryBuilder.dailyTips(GoalMode.fatLoss, _today);
      expect(a, StoryBuilder.dailyTips(GoalMode.fatLoss, _today));
      expect(a, hasLength(2));
      expect(a, isNot(StoryBuilder.dailyTips(
          GoalMode.fatLoss, _today.add(const Duration(days: 1)))));
      final pool = [
        ...StoryBuilder.goalTips[GoalMode.leanGain]!,
        ...StoryBuilder.generalTips,
      ];
      expect(StoryBuilder.dailyTips(GoalMode.leanGain, _today).every(pool.contains), isTrue);
    });

    test('ipucu listesinde tıbbi iddia yok', () {
      final all = [
        for (final l in StoryBuilder.goalTips.values) ...l,
        ...StoryBuilder.generalTips,
      ];
      for (final t in all) {
        expect(t.toLowerCase(), isNot(matches(RegExp(r'tedavi|ilaç|hastalık|garanti|kesin'))));
      }
    });

    test('bugünün hatırlatmaları kart olur', () {
      final g = StoryBuilder.tips(
        today: _today,
        goal: GoalMode.maintain,
        agenda: [StoryAgendaItem(title: 'Su iç', time: DateTime(2026, 11, 23, 15, 5))],
      );
      expect(g.slides.last.id, 'agenda');
      expect(g.slides.last.body, '15:05  Su iç');
    });
  });

  group('Başarı tespiti', () {
    test('seri eşikleri, haftalık hedef pazartesiye, antrenman ve kilo', () {
      final list = StoryBuilder.detectAchievements(AchievementInput(
        today: _today, // pazartesi değil: 23 Kasım 2026 pazartesi
        streaks: const {'Adım': 14, 'Kayıt': 6},
        weeklyGoalHit: true,
        workoutToday: true,
        weightGoalReached: true,
      ));
      expect(list.map((a) => a.kind), [
        AchievementKind.streak14,
        AchievementKind.weeklyGoal,
        AchievementKind.workout,
        AchievementKind.weightGoal,
      ]);
      expect(list.first.payload, {'streak': 'Adım'});
      expect(list[1].day.weekday, DateTime.monday);
    });

    test('eşik dışında seri başarı değildir', () {
      expect(
        StoryBuilder.detectAchievements(
            AchievementInput(today: _today, streaks: const {'Adım': 8})),
        isEmpty,
      );
    });

    test('kilo hedefine ilk kez bugün ulaşılması', () {
      bool reached(List<double> kgs) => weightGoalReachedToday(
            weights: [
              for (final (i, kg) in kgs.indexed)
                (at: _today.subtract(Duration(days: kgs.length - 1 - i)), kg: kg),
            ],
            targetKg: 70,
            startKg: 80,
            goal: GoalMode.fatLoss,
            today: _today,
          );
      expect(reached([70.6, 69.9]), isTrue);
      expect(reached([69.8, 69.9]), isFalse);
      expect(reached([71.0, 70.5]), isFalse);
    });
  });

  group('Gizlilik', () {
    final pending = [PendingAchievement(AchievementKind.workout, _today)];

    test('paylaşım kapalıyken (varsayılan) hiçbir şey yazılmaz', () async {
      final repo = MemoryStoriesRepository();
      final n = await StoryPublisher(repo).publish(const UserSettings.defaults(), pending);
      expect(n, 0);
      expect(repo.published, isEmpty);
      expect(const UserSettings.defaults().shareStories, isFalse);
    });

    test('eski şemada (sütun yok) açık olsa da yazılmaz', () async {
      final repo = MemoryStoriesRepository();
      final settings = const UserSettings.defaults()
          .copyWith(shareStories: true, shareStoriesColumn: false);
      expect(await StoryPublisher(repo).publish(settings, pending), 0);
      expect(repo.published, isEmpty);
      expect(settings.toMap().containsKey('share_stories'), isFalse);
    });

    test('açıkken bir kez yazılır (tür + gün tekil)', () async {
      final repo = MemoryStoriesRepository();
      final publisher = StoryPublisher(repo);
      final settings = const UserSettings.defaults().copyWith(shareStories: true);
      expect(await publisher.publish(settings, pending), 1);
      expect(await publisher.publish(settings, pending), 0);
      expect(repo.published, hasLength(1));
    });
  });

  group('Arkadaş halkaları', () {
    test('kişi başına bir halka, süresi dolan ve tanınmayan atlanır', () {
      final groups = StoryBuilder.friendGroups(
        stories: [
          _story('a', 'f-1', AchievementKind.streak7, ago: const Duration(hours: 5)),
          _story('b', 'f-2', AchievementKind.workout),
          _story('c', 'f-1', AchievementKind.weightGoal, ago: const Duration(hours: 30)),
          _story('d', 'x', AchievementKind.workout),
        ],
        friends: {
          'f-1': (name: 'Elif', avatar: const AvatarChoice()),
          'f-2': (name: 'Can', avatar: const AvatarChoice()),
        },
        now: DateTime.now(),
      );
      expect(groups.map((g) => g.label), ['Can', 'Elif']);
      expect(groups.last.slides.single.title, '7 günlük seri');
    });
  });

  group('Görüntüleyici', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget app(List<StoryGroup> groups, MemoryStoriesRepository repo,
            {bool reduce = false}) =>
        ProviderScope(
          overrides: [storiesRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
              child: StoryViewer(groups: groups),
            ),
          ),
        );

    final daily = StoryBuilder.dailySummary(DailySummaryInput(
      today: _today,
      stepsToday: 5000,
      stepGoal: 8000,
      tasksDone: 1,
      tasksTotal: 2,
    ));

    testWidgets('dokununca ilerler, kartlar görüldü olarak saklanır', (tester) async {
      final repo = MemoryStoriesRepository();
      await tester.pumpWidget(app([daily], repo));
      await tester.pump();
      expect(find.text('Bugünkü adımların'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-progress-1')), findsOneWidget);
      await tester.tapAt(const Offset(350, 400));
      await tester.pump();
      expect(find.text('Bugünün işleri'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(StorySeenStore.prefsKey), daily.seenKeys);
    });

    testWidgets('kendiliğinden ilerler; hareket azaltmada ilerlemez', (tester) async {
      final repo = MemoryStoriesRepository();
      await tester.pumpWidget(app([daily], repo));
      await tester.pump(StoryViewer.slideDuration + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.text('Bugünün işleri'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app([daily], repo, reduce: true));
      await tester.pump(StoryViewer.slideDuration * 2);
      expect(find.text('Bugünkü adımların'), findsOneWidget);
    });

    testWidgets('basılı tutunca duraklar', (tester) async {
      final repo = MemoryStoriesRepository();
      await tester.pumpWidget(app([daily], repo));
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(300, 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Duraklatıldı'), findsOneWidget);
      await tester.pump(StoryViewer.slideDuration * 2);
      expect(find.text('Bugünkü adımların'), findsOneWidget);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('arkadaş story''sine tepki verilir', (tester) async {
      final story = _story('s1', 'f-1', AchievementKind.workout);
      final repo = MemoryStoriesRepository(currentUserId: 'me', friendStories: [story]);
      final groups = StoryBuilder.friendGroups(
        stories: [story],
        friends: {'f-1': (name: 'Elif', avatar: const AvatarChoice())},
        now: DateTime.now(),
      );
      await tester.pumpWidget(app(groups, repo));
      await tester.pump();
      expect(find.text('Bugün antrenman yaptı'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-react-🔥')));
      await tester.pump();
      final after = await repo.friendStories();
      expect(after.single.reactionOf('me'), '🔥');
    });

    testWidgets('aşağı kaydırınca kapanır', (tester) async {
      final repo = MemoryStoriesRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [storiesRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => StoryViewer.open(context, groups: [daily]),
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('story-viewer')), const Offset(0, 400), 1500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    });
  });
}

