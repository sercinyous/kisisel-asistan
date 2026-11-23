import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../friends/data/friends_repository.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/providers/streaks_providers.dart';
import '../../health/presentation/providers/week_deficit_providers.dart';
import '../../health/domain/goal_mode.dart';
import '../../kokpit/presentation/kokpit_day_view.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/stories_repository.dart';
import '../data/story_publisher.dart';
import '../data/story_seen_store.dart';
import '../domain/story_builder.dart';
import '../domain/story_models.dart';

final storySeenStoreProvider = Provider<StorySeenStore>((ref) => StorySeenStore());

/// Görülmüş kart anahtarları (cihazda).
final storySeenProvider =
    AsyncNotifierProvider<StorySeenNotifier, Set<String>>(StorySeenNotifier.new);

class StorySeenNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(storySeenStoreProvider).load();

  Future<void> _queue = Future<void>.value();

  /// Sırayla yazar: üst üste gelen çağrılar birbirinin anahtarını ezmesin.
  Future<void> markSeen(Iterable<String> keys) {
    final list = keys.toList();
    return _queue = _queue.then((_) async {
      final current = await future;
      if (list.every(current.contains)) return;
      state = AsyncData({...current, ...list});
      final saved =
          await ref.read(storySeenStoreProvider).markSeen(current, list);
      state = AsyncData(saved);
    });
  }
}

/// Arkadaşların story'leri ve adları/avatarları.
final friendStoryGroupsProvider = FutureProvider<List<StoryGroup>>((ref) async {
  final stories = await ref.watch(storiesRepositoryProvider).friendStories();
  if (stories.isEmpty) return const [];
  final friends = await ref.watch(friendsRepositoryProvider).friends();
  return StoryBuilder.friendGroups(
    stories: stories,
    friends: {
      for (final f in friends)
        f.friendId: (name: f.displayName, avatar: f.avatar),
    },
    now: DateTime.now(),
  );
});

/// Dün ve bugünün adımları (sağlık kaynağından).
final _storyStepsProvider = FutureProvider<HealthDays>((ref) {
  final today = AppDates.startOfDay(ref.watch(kokpitClockProvider));
  return ref.watch(healthDaysProvider((
    from: AppDates.addDays(today, -1),
    to: today,
  )).future);
});

Map<String, int> _streakMap(StreaksState? s) => {
      for (final st in s?.streaks ?? const <StreakStatus>[])
        st.kind.label: st.current,
    };

/// Kokpit'teki halkaların sırası: Günün özeti, İpuçları, arkadaşlar.
List<StoryGroup> watchStoryGroups(WidgetRef ref) {
  final now = ref.watch(kokpitClockProvider);
  final today = AppDates.startOfDay(now);
  final settings = ref.watch(settingsOrDefaultProvider);
  final steps = ref.watch(_storyStepsProvider).valueOrNull;
  int? stepsOn(DateTime day) {
    for (final d in steps?.days ?? const <StreakDay>[]) {
      if (_sameDay(d.date, day)) return d.steps;
    }
    return null;
  }

  final items = watchKokpitTodayItems(ref)
          ?.where((i) => i is! KokpitCheckinItem)
          .toList() ??
      const <KokpitTodayItem>[];
  final nutrition = ref.watch(todayNutritionProvider).valueOrNull;
  final streaks = ref.watch(streaksProvider).valueOrNull;

  final daily = StoryBuilder.dailySummary(DailySummaryInput(
    today: today,
    stepsToday: stepsOn(today),
    stepsYesterday: stepsOn(AppDates.addDays(today, -1)),
    stepGoal: settings.dailySteps,
    kcalToday: nutrition?.calories,
    kcalTarget: settings.dailyCalories,
    tasksDone: items.where((i) => i.done).length,
    tasksTotal: items.length,
    streaks: _streakMap(streaks),
  ));

  final agenda = <StoryAgendaItem>[
    for (final i in items)
      if (!i.done && (i.time == null || !i.time!.isBefore(now)))
        StoryAgendaItem(
          title: switch (i) {
            KokpitRoutineItem(:final occurrence) => occurrence.routine.title,
            KokpitTaskItem(:final task) => task.title,
            KokpitCheckinItem() => KokpitCheckinItem.title,
          },
          time: i.time,
        ),
  ]..sort((a, b) {
      if (a.time == null) return b.time == null ? 0 : 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });
  final tips = StoryBuilder.tips(
    today: today,
    goal: settings.goalMode,
    agenda: agenda,
  );

  final friends =
      ref.watch(friendStoryGroupsProvider).valueOrNull ?? const <StoryGroup>[];
  return [daily, tips, ...friends];
}

final storyPublisherProvider = Provider<StoryPublisher>(
  (ref) => StoryPublisher(ref.watch(storiesRepositoryProvider)),
);

/// Bugünün başarılarını tespit eder ve (paylaşım açıksa) yazar. Kapalıyken
/// hiçbir veri okunmaz ve yazılmaz.
final storyAchievementSyncProvider = FutureProvider<int>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!settings.shareStories || !settings.shareStoriesColumn) return 0;
  final today = AppDates.startOfDay(ref.watch(kokpitClockProvider));
  final streaks = await ref.watch(streaksProvider.future);
  final monday = AppDates.addDays(today, -(today.weekday - 1));
  final week = await ref.watch(healthDaysProvider((from: monday, to: today)).future);
  final goalDays = week.days
      .where((d) => d.steps != null && d.steps! >= settings.dailySteps)
      .length;
  final workouts = await ref.watch(recentWorkoutsProvider.future);
  final weights = await ref.watch(weightSeriesProvider(30).future);
  return ref.read(storyPublisherProvider).publish(
        settings,
        StoryBuilder.detectAchievements(AchievementInput(
          today: today,
          streaks: _streakMap(streaks),
          weeklyGoalHit: goalDays >= 5,
          workoutToday:
              workouts.any((w) => _sameDay(w.loggedAt, today)),
          weightGoalReached: weightGoalReachedToday(
            weights: [for (final w in weights) (at: w.loggedAt, kg: w.weightKg)],
            targetKg: settings.targetWeightKg,
            startKg: settings.startWeightKg,
            goal: settings.goalMode,
            today: today,
          ),
        )),
      );
});

/// Bugünkü tartı hedefe ilk kez ulaştıysa `true` (önceki tartı ulaşmamıştı).
/// Hedef yönü başlangıç ile hedef arasından çıkar; korumada başarı yok.
bool weightGoalReachedToday({
  required List<({DateTime at, double kg})> weights,
  required double targetKg,
  required double startKg,
  required GoalMode goal,
  required DateTime today,
}) {
  if (goal == GoalMode.maintain || weights.isEmpty) return false;
  if ((startKg - targetKg).abs() < 0.1) return false;
  final losing = targetKg < startKg;
  bool reached(double kg) => losing ? kg <= targetKg : kg >= targetKg;
  final sorted = [...weights]..sort((a, b) => a.at.compareTo(b.at));
  final last = sorted.last;
  if (!_sameDay(last.at, today) || !reached(last.kg)) return false;
  final before = sorted.where((w) => w.at.isBefore(AppDates.startOfDay(today)));
  return before.isEmpty || !reached(before.last.kg);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
