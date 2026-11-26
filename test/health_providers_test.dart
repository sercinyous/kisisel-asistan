import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/week_deficit_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeHealthRepository health;
  late FakeRoutinesRepository routines;

  final today = AppDates.startOfDay(DateTime.now());
  DateTime daysAgo(int n, {int hour = 0}) =>
      AppDates.addDays(today, -n).add(Duration(hours: hour));

  setUp(() {
    health = FakeHealthRepository();
    routines = FakeRoutinesRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        routinesRepositoryProvider.overrideWithValue(routines),
        kokpitRepositoryProvider
            .overrideWithValue(FakeKokpitRepository(health: health)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  WeightEntry weight(String id, double kg, DateTime at) =>
      WeightEntry(id: id, weightKg: kg, loggedAt: at);
  WorkoutLog workout(String id, DateTime at, {String type = 'weights'}) =>
      WorkoutLog(id: id, workoutType: type, loggedAt: at);
  NutritionLog meal(String id, DateTime at, {double calories = 100}) =>
      NutritionLog(id: id, foodName: id, calories: calories, eatenAt: at);

  group('weightSeriesProvider', () {
    setUp(() {
      health.weights = [
        weight('bugün', 83.6, daysAgo(0, hour: 8)),
        weight('29', 84.4, daysAgo(29, hour: 8)),
        weight('30', 84.5, daysAgo(30, hour: 8)),
        weight('89', 86.0, daysAgo(89, hour: 8)),
        weight('90', 86.2, daysAgo(90, hour: 8)),
      ];
    });

    test('30 gün: bugün dahil son 30 gün, eskiden yeniye', () async {
      final container = makeContainer();
      final series = await container.read(weightSeriesProvider(30).future);
      expect(series.map((w) => w.id), ['29', 'bugün']);
    });

    test('90 gün penceresi daha eskiyi de alır', () async {
      final container = makeContainer();
      final series = await container.read(weightSeriesProvider(90).future);
      expect(series.map((w) => w.id), ['89', '30', '29', 'bugün']);
    });

    test('pencereler 30 ve 90 gündür', () {
      expect(weightSeriesWindows, [30, 90]);
    });
  });

  group('dayNutritionLogsProvider', () {
    test('yalnızca o günün kayıtları, saat sırasıyla', () async {
      health.nutritionLogs = [
        meal('akşam', daysAgo(0, hour: 19)),
        meal('dün', daysAgo(1, hour: 23)),
        meal('sabah', daysAgo(0, hour: 8)),
      ];
      final container = makeContainer();
      final logs = await container.read(dayNutritionLogsProvider(today).future);
      expect(logs.map((l) => l.id), ['sabah', 'akşam']);
      final yesterday =
          await container.read(dayNutritionLogsProvider(daysAgo(1)).future);
      expect(yesterday.map((l) => l.id), ['dün']);
    });

    test('kayıt yoksa boş liste', () async {
      final container = makeContainer();
      expect(await container.read(dayNutritionLogsProvider(today).future), isEmpty);
    });
  });

  test('recentWorkoutsProvider: son 30 gün, yeniden eskiye', () async {
    health.workouts = [
      workout('eski', daysAgo(30, hour: 19)),
      workout('sınır', daysAgo(29, hour: 19)),
      workout('dün', daysAgo(1, hour: 19)),
      workout('bugün', daysAgo(0, hour: 7)),
    ];
    final container = makeContainer();
    final list = await container.read(recentWorkoutsProvider.future);
    expect(list.map((w) => w.id), ['bugün', 'dün', 'sınır']);
  });

  group('buildWeekWorkoutPlan', () {
    final monday = DateTime(2026, 9, 28); // 28 Eylül 2026 Pazartesi
    final old = DateTime(2026, 9, 1);
    Routine sport(String id, List<int> days, {DateTime? created, bool active = true}) =>
        Routine(
          id: id,
          title: id,
          category: 'spor',
          daysOfWeek: days,
          isActive: active,
          createdAt: created ?? old,
        );

    test('7 gün; spor rutinleri günlerine yerleşir', () {
      final plan = buildWeekWorkoutPlan(
        [sport('ağırlık', [1, 2, 4, 5]), sport('kickboks', [3])],
        const [],
        monday,
      );
      expect(plan.weekStart, monday);
      expect(plan.days.map((d) => d.date), [
        for (var i = 0; i < 7; i++) DateTime(2026, 9, 28 + i),
      ]);
      expect(plan.days.map((d) => d.planned.map((r) => r.id).toList()), [
        ['ağırlık'],
        ['ağırlık'],
        ['kickboks'],
        ['ağırlık'],
        ['ağırlık'],
        <String>[],
        <String>[],
      ]);
      expect(plan.plannedCount, 5);
      expect(plan.doneCount, 0);
      expect(plan.days[5].isPlanned, isFalse);
    });

    test('spor olmayan ve pasif rutinler plana girmez', () {
      final plan = buildWeekWorkoutPlan(
        [
          Routine(id: 'iş', title: 'iş', category: 'operasyon', createdAt: old),
          sport('pasif', Routine.everyDay, active: false),
        ],
        const [],
        monday,
      );
      expect(plan.plannedCount, 0);
    });

    test('hafta ortasında oluşturulan rutin öncesinde planlı sayılmaz', () {
      final plan = buildWeekWorkoutPlan(
        [sport('yeni', Routine.everyDay, created: DateTime(2026, 10, 1, 0, 30))],
        const [],
        monday,
      );
      expect(plan.days.map((d) => d.isPlanned),
          [false, false, false, true, true, true, true]);
    });

    test('aylık spor rutini günü haftaya düşüyorsa planlı; 31 → 30 Eylül', () {
      final plan = buildWeekWorkoutPlan(
        [
          Routine(
            id: 'ay sonu',
            title: 'ay sonu',
            category: 'spor',
            frequency: RoutineFrequency.monthly,
            dayOfMonth: 31,
            createdAt: old,
          ),
          Routine(
            id: 'ayın 15i',
            title: 'ayın 15i',
            category: 'spor',
            frequency: RoutineFrequency.monthly,
            dayOfMonth: 15,
            createdAt: old,
          ),
        ],
        const [],
        monday,
      );
      expect(plan.plannedCount, 1);
      expect(plan.days[2].date, DateTime(2026, 9, 30));
      expect(plan.days[2].planned.single.id, 'ay sonu');
    });

    test('antrenmanlar günlerine, saat sırasıyla; hafta dışı sayılmaz', () {
      final plan = buildWeekWorkoutPlan(
        const [],
        [
          workout('akşam', DateTime(2026, 9, 28, 19)),
          workout('sabah', DateTime(2026, 9, 28, 7)),
          workout('gece', DateTime(2026, 9, 28, 23, 30)),
          workout('salı', DateTime(2026, 9, 29, 0, 30)),
          workout('önceki', DateTime(2026, 9, 27, 23, 59)),
          workout('sonraki', DateTime(2026, 10, 5, 0, 0)),
        ],
        monday,
      );
      expect(plan.days[0].done.map((w) => w.id), ['sabah', 'akşam', 'gece']);
      expect(plan.days[1].done.map((w) => w.id), ['salı']);
      expect(plan.doneCount, 4);
      expect(plan.days[0].isDone, isTrue);
      expect(plan.days[2].isDone, isFalse);
    });

    test('hafta içi bir gün verilirse Pazartesi\'ye indirgenir', () {
      final plan = buildWeekWorkoutPlan(const [], const [], DateTime(2026, 10, 1, 15));
      expect(plan.weekStart, monday);
    });
  });

  group('weekWorkoutPlanProvider', () {
    test('bu haftanın planı ve yapılanları', () async {
      final monday = AppDates.weekStart(today);
      routines.routines = [
        Routine(
          id: 'spor',
          title: 'Ağırlık',
          category: 'spor',
          createdAt: DateTime(2020),
        ),
        Routine(id: 'iş', title: 'Kontrol', category: 'operasyon', createdAt: DateTime(2020)),
      ];
      health.workouts = [
        workout('bu hafta', monday.add(const Duration(hours: 7))),
        workout('geçen hafta', monday.subtract(const Duration(hours: 1))),
      ];
      final container = makeContainer();
      final plan = await container.read(weekWorkoutPlanProvider.future);
      expect(plan.weekStart, monday);
      expect(plan.plannedCount, 7);
      expect(plan.doneCount, 1);
      expect(plan.days.first.done.single.id, 'bu hafta');
    });

    test('okuma hatası iletilir', () async {
      routines.fetchError = Exception('ağ yok');
      final container = makeContainer();
      container.listen(weekWorkoutPlanProvider, (_, __) {});
      await expectLater(
        container.read(weekWorkoutPlanProvider.future),
        throwsException,
      );
    });
  });

  group('weekStepsProvider', () {
    test('tam 7 gün, eskiden yeniye; kaydı olmayan gün sıfır', () async {
      health.metrics = [
        DailyHealthMetric(day: daysAgo(0), steps: 9000, sleepMinutes: 430),
        DailyHealthMetric(day: daysAgo(6), steps: 6000),
        DailyHealthMetric(day: daysAgo(7), steps: 1234),
      ];
      final container = makeContainer();
      final days = await container.read(weekStepsProvider.future);
      expect(days.map((d) => d.day), [
        for (var n = 6; n >= 0; n--) daysAgo(n),
      ]);
      expect(days.map((d) => d.steps), [6000, 0, 0, 0, 0, 0, 9000]);
      expect(days.last.sleepMinutes, 430);
    });

    test('averageSteps yalnızca verisi olan günleri sayar', () {
      expect(
        averageSteps([
          DailyHealthMetric(day: daysAgo(2), steps: 6000),
          DailyHealthMetric(day: daysAgo(1)),
          DailyHealthMetric(day: daysAgo(0), steps: 9001),
        ]),
        7501,
      );
      expect(averageSteps([DailyHealthMetric(day: today)]), isNull);
      expect(averageSteps(const []), isNull);
    });
  });

  test('invalidateHealthData: Sağlık sekmesi ve Kokpit özeti yeniden okunur',
      () async {
    final container = makeContainer();
    container.listen(weightSeriesProvider(30), (_, __) {});
    container.listen(dayNutritionLogsProvider(today), (_, __) {});
    container.listen(recentWorkoutsProvider, (_, __) {});
    container.listen(weekWorkoutPlanProvider, (_, __) {});
    container.listen(todayNutritionProvider, (_, __) {});
    await container.read(weightSeriesProvider(30).future);
    await container.read(dayNutritionLogsProvider(today).future);
    await container.read(recentWorkoutsProvider.future);
    await container.read(weekWorkoutPlanProvider.future);
    expect((await container.read(todayNutritionProvider.future)).entryCount, 0);

    final now = DateTime.now();
    await health.addWeight(83.2, at: now);
    await health.createNutritionLog(meal('yeni', now, calories: 420));
    await health.createWorkout(workout('', now));
    invalidateHealthData(container);

    expect(await container.read(weightSeriesProvider(30).future), hasLength(1));
    expect(
      await container.read(dayNutritionLogsProvider(today).future),
      hasLength(1),
    );
    expect(await container.read(recentWorkoutsProvider.future), hasLength(1));
    expect((await container.read(weekWorkoutPlanProvider.future)).doneCount, 1);
    final summary = await container.read(todayNutritionProvider.future);
    expect(summary.entryCount, 1);
    expect(summary.calories, 420);
  });

  test('invalidateEnergyData: açık/seri girdisi (healthDaysProvider) tazelenir',
      () async {
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
    );
    addTearDown(container.dispose);
    final window = (from: today, to: today);
    container.listen(healthDaysProvider(window), (_, __) {});
    final before = await container.read(healthDaysProvider(window).future);
    expect(before.days.single.mealCount, 0);

    await health.createNutritionLog(meal('yeni', DateTime.now(), calories: 500));
    invalidateEnergyData(container);

    final after = await container.read(healthDaysProvider(window).future);
    expect(after.days.single.mealCount, 1);
    expect(after.days.single.intakeKcal, 500);
  });
}
