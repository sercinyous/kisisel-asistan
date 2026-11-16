import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeRoutinesRepository routines;
  late FakeTasksRepository tasks;
  late FakeHealthRepository health;
  late FakeSettingsRepository settings;
  late FakeNotificationService notifications;

  final today = AppDates.startOfDay(DateTime.now());
  final thisMonth = DateTime(today.year, today.month);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);

  Routine daily(String id, {int? hour}) =>
      Routine(id: id, title: 'Günlük $id', hour: hour, minute: hour == null ? null : 0);
  Routine monthly(String id, int day) => Routine(
        id: id,
        title: 'Aylık $id',
        frequency: RoutineFrequency.monthly,
        dayOfMonth: day,
      );

  setUp(() {
    routines = FakeRoutinesRepository();
    tasks = FakeTasksRepository();
    health = FakeHealthRepository();
    settings = FakeSettingsRepository();
    notifications = FakeNotificationService();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        healthRepositoryProvider.overrideWithValue(health),
        settingsRepositoryProvider.overrideWithValue(settings),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Sağlayıcıyı canlı tutar (dinleyici olmadan invalidate yeniden kurmaz).
  Future<TodayOccurrences> loadToday(ProviderContainer container) {
    container.listen(todayOccurrencesProvider, (_, __) {});
    return container.read(todayOccurrencesProvider.future);
  }

  group('activeRoutinesProvider', () {
    test('yalnızca aktif rutinler', () async {
      routines.routines = [
        daily('a'),
        daily('p').copyWith(isActive: false),
        monthly('m', 15),
      ];
      final list = await makeContainer().read(activeRoutinesProvider.future);
      expect(list.map((r) => r.id), ['a', 'm']);
    });
  });

  group('todayOccurrencesProvider', () {
    test('günlük ve aylık ayrı listelenir', () async {
      routines.routines = [
        daily('aksam', hour: 20),
        daily('sabah', hour: 8),
        Routine(id: 'yarin', title: 'Yarın', daysOfWeek: [tomorrow.weekday]),
        monthly('bugun', today.day),
      ];
      routines.completions = {RoutineCompletionKey('sabah', today)};

      final state = await loadToday(makeContainer());

      expect(state.daily.map((o) => o.routine.id), ['sabah', 'aksam']);
      expect(state.daily.first.completed, isTrue);
      expect(state.daily.last.completed, isFalse);
      final m = state.monthly.singleWhere((o) => o.periodKey == thisMonth);
      expect(m.routine.id, 'bugun');
      expect(m.status, OccurrenceStatus.dueToday);
    });

    test('aylık pencere ayarlardaki monthly_lead_days ile açılır', () async {
      final inFive = DateTime(today.year, today.month, today.day + 5);
      // Ayın 29-31'i her ayda yoktur; o günlerde test, ayın son gününe
      // kırpılan tarihle de tutarlı kalsın diye beklenen gün hesaplanır.
      final routine = monthly('m', inFive.day);
      final due = monthlyDueDate(routine, inFive.year, inFive.month);
      final distance = due.difference(today).inHours / 24;
      routines.routines = [routine];
      // Geçmiş dönemin gecikmiş kaydı sonucu bulandırmasın.
      routines.completions = {
        if (due.month != today.month) RoutineCompletionKey('m', thisMonth),
      };

      bool visible(TodayOccurrences s) => s.monthly.any((o) => o.dueDate == due);

      settings.settings = const UserSettings.defaults(); // 3 gün
      final short = makeContainer();
      await short.read(userSettingsProvider.future);
      expect(visible(await loadToday(short)), distance.round() <= 3);

      settings.settings = const UserSettings.defaults().copyWith(monthlyLeadDays: 7);
      final long = makeContainer();
      await long.read(userSettingsProvider.future);
      expect(visible(await loadToday(long)), isTrue);
    });

    test('ayarlar yüklenince pencere yeniden hesaplanır', () async {
      final inFive = DateTime(today.year, today.month, today.day + 5);
      final routine = monthly('m', inFive.day);
      final due = monthlyDueDate(routine, inFive.year, inFive.month);
      if (due.difference(today).inHours / 24 <= 3) {
        markTestSkipped('ay sonu kırpması: iş zaten varsayılan pencerede');
        return;
      }
      routines.routines = [routine];
      routines.completions = {
        if (due.month != today.month) RoutineCompletionKey('m', thisMonth),
      };
      settings.settings = const UserSettings.defaults().copyWith(monthlyLeadDays: 10);

      final container = makeContainer();
      // Ayarlar henüz okunmadı: varsayılan 3 günle kurulur.
      final first = await loadToday(container);
      expect(first.monthly.where((o) => o.dueDate == due), isEmpty);

      await container.read(userSettingsProvider.future);
      final second = await container.read(todayOccurrencesProvider.future);
      expect(second.monthly.where((o) => o.dueDate == due), hasLength(1));
    });

    test('toggle (günlük): iyimser uygulanır, depo günün anahtarıyla çağrılır',
        () async {
      routines.routines = [daily('a'), daily('b')];
      routines.toggleGate = Completer<void>();
      final container = makeContainer();
      final state = await loadToday(container);

      final pending = container
          .read(todayOccurrencesProvider.notifier)
          .toggle(state.daily.first);
      final optimistic = container.read(todayOccurrencesProvider).value!;
      expect(optimistic.daily.map((o) => o.completed), [true, false]);
      expect(optimistic.daily.first.status, OccurrenceStatus.done);
      expect(routines.toggles, [
        (routineId: 'a', periodKey: today, completed: true),
      ]);

      routines.toggleGate!.complete();
      await pending;
      expect(
        container.read(todayOccurrencesProvider).value!.daily.first.completed,
        isTrue,
      );
      expect(routines.completions, {RoutineCompletionKey('a', today)});
    });

    test('toggle (aylık): ayın 1\'i anahtarıyla yazılır, iş o gün yapıldı '
        'olarak listede kalır', () async {
      routines.routines = [monthly('m', today.day)];
      final container = makeContainer();
      final state = await loadToday(container);
      final occurrence =
          state.monthly.singleWhere((o) => o.periodKey == thisMonth);

      await container.read(todayOccurrencesProvider.notifier).toggle(occurrence);

      expect(routines.toggles, [
        (routineId: 'm', periodKey: thisMonth, completed: true),
      ]);
      final after = container
          .read(todayOccurrencesProvider)
          .value!
          .monthly
          .singleWhere((o) => o.periodKey == thisMonth);
      expect(after.completed, isTrue);
      expect(after.status, OccurrenceStatus.done);

      // Yeniden okuma da aynı sonucu verir (sunucudaki kayıtla).
      container.invalidate(todayOccurrencesProvider);
      final reloaded = await container.read(todayOccurrencesProvider.future);
      expect(
        reloaded.monthly.singleWhere((o) => o.periodKey == thisMonth).completed,
        isTrue,
      );

      // İşareti kaldır.
      await container.read(todayOccurrencesProvider.notifier).toggle(after);
      expect(routines.completions, isEmpty);
      expect(
        container
            .read(todayOccurrencesProvider)
            .value!
            .monthly
            .singleWhere((o) => o.periodKey == thisMonth)
            .status,
        OccurrenceStatus.dueToday,
      );
    });

    test('gecikmiş aylık iş işaretlenince o gün listede kalır', () async {
      if (today.day == 1) {
        markTestSkipped('ayın 1\'inde gecikmiş aylık iş olamaz');
        return;
      }
      routines.routines = [monthly('m', 1)];
      final container = makeContainer();
      final state = await loadToday(container);
      final overdue = state.monthly.singleWhere((o) => o.periodKey == thisMonth);
      expect(overdue.status, OccurrenceStatus.overdue);

      await container.read(todayOccurrencesProvider.notifier).toggle(overdue);
      container.invalidate(todayOccurrencesProvider);
      final reloaded = await container.read(todayOccurrencesProvider.future);
      expect(
        reloaded.monthly.singleWhere((o) => o.periodKey == thisMonth).status,
        OccurrenceStatus.done,
      );
    });

    test('ay sınırını aşan iş gelecek ayın anahtarıyla işaretlenir', () async {
      final routine = monthly('m', tomorrow.day);
      routines.routines = [routine];
      final container = makeContainer();
      final state = await loadToday(container);
      final next = state.monthly.singleWhere((o) => o.dueDate == tomorrow);
      expect(next.periodKey, DateTime(tomorrow.year, tomorrow.month));
      expect(next.status, OccurrenceStatus.upcoming);

      await container.read(todayOccurrencesProvider.notifier).toggle(next);
      expect(routines.toggles.single.periodKey,
          DateTime(tomorrow.year, tomorrow.month));
    });

    test('yazma sürerken yenileme iyimser durumu ezmez', () async {
      routines.routines = [daily('a')];
      routines.toggleGate = Completer<void>();
      final container = makeContainer();
      final state = await loadToday(container);

      final pending = container
          .read(todayOccurrencesProvider.notifier)
          .toggle(state.daily.single);
      // Sunucu henüz yazmadı: yenileme "tamamlanmamış" okur.
      container.invalidate(todayOccurrencesProvider);
      final refreshed = await container.read(todayOccurrencesProvider.future);
      expect(refreshed.daily.single.completed, isTrue,
          reason: 'bekleyen işaretleme yenilemenin üzerine uygulanır');

      routines.toggleGate!.complete();
      await pending;
      expect(
        container.read(todayOccurrencesProvider).value!.daily.single.completed,
        isTrue,
      );
    });

    test('yazma, süren bir okumanın ortasında biterse okuma tekrarlanır',
        () async {
      final slow = _SlowReadRepository(routines: [daily('a')]);
      final container = ProviderContainer(
        overrides: [
          routinesRepositoryProvider.overrideWithValue(slow),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      container.listen(todayOccurrencesProvider, (_, __) {});
      final state = await container.read(todayOccurrencesProvider.future);

      // Okuma başlar ve tamamlanma kayıtlarında bekler (bayat veri: işaretsiz).
      slow.readGate = Completer<void>();
      container.invalidate(todayOccurrencesProvider);
      final reading = container.read(todayOccurrencesProvider.future);
      await slow.readStarted.future;

      // Bu sırada yazma başlar ve biter.
      await container
          .read(todayOccurrencesProvider.notifier)
          .toggle(state.daily.single);

      // Bayat okuma şimdi döner; sonucu yayınlanırsa işaret geri alınmış görünür.
      slow.releaseStale();
      await reading;
      await pumpEventQueue();

      expect(
        container.read(todayOccurrencesProvider).value!.daily.single.completed,
        isTrue,
        reason: 'yazmadan önce başlamış okuma bayattır; yeniden okunur',
      );
      expect(container.read(todayOccurrencesProvider).isLoading, isFalse);
      expect(slow.completionReads, 3);
    });

    test('aynı kalem için yazma sürerken ikinci dokunuş yok sayılır', () async {
      routines.routines = [daily('a')];
      routines.toggleGate = Completer<void>();
      final container = makeContainer();
      final state = await loadToday(container);
      final notifier = container.read(todayOccurrencesProvider.notifier);

      final first = notifier.toggle(state.daily.single);
      await notifier.toggle(
        container.read(todayOccurrencesProvider).value!.daily.single,
      );
      expect(routines.toggles, hasLength(1));

      routines.toggleGate!.complete();
      await first;
    });

    test('hata: yalnızca o kalem geri alınır, hata iletilir', () async {
      routines.routines = [daily('a'), daily('b')];
      final container = makeContainer();
      final state = await loadToday(container);
      final notifier = container.read(todayOccurrencesProvider.notifier);

      // b başarıyla işaretlenir.
      await notifier.toggle(state.daily[1]);

      routines.toggleGate = Completer<void>();
      final failing = notifier.toggle(state.daily[0]);
      expect(
        container.read(todayOccurrencesProvider).value!.daily.map((o) => o.completed),
        [true, true],
      );
      routines.toggleGate!.completeError(Exception('ağ yok'));
      await expectLater(failing, throwsException);

      expect(
        container.read(todayOccurrencesProvider).value!.daily.map((o) => o.completed),
        [false, true],
      );
      expect(routines.completions, {RoutineCompletionKey('b', today)});
    });

    test('okuma hatası sağlayıcıyı hata durumuna alır; toggle etkisizdir',
        () async {
      routines.fetchError = Exception('ağ yok');
      final container = makeContainer();
      container.listen(todayOccurrencesProvider, (_, __) {});
      await expectLater(
        container.read(todayOccurrencesProvider.future),
        throwsException,
      );
      await container.read(todayOccurrencesProvider.notifier).toggle(
            RoutineOccurrence(
              routine: daily('a'),
              periodKey: today,
              dueDate: today,
              completed: false,
              status: OccurrenceStatus.dueToday,
            ),
          );
      expect(routines.toggles, isEmpty);
    });

    test('işaretleme Ay özetini tazeler; aylık iş bildirimleri de eşitler',
        () async {
      routines.routines = [daily('a'), monthly('m', today.day)];
      final container = makeContainer();
      container.listen(monthOverviewProvider(thisMonth), (_, __) {});
      container.listen(notificationSyncProvider, (_, __) {});
      await container.read(notificationSyncProvider.future);
      final state = await loadToday(container);
      final before = await container.read(monthOverviewProvider(thisMonth).future);
      expect(before.weeklyDone, 0);
      expect(notifications.resyncCount, 1);

      await container
          .read(todayOccurrencesProvider.notifier)
          .toggle(state.daily.single);
      final afterDaily =
          await container.read(monthOverviewProvider(thisMonth).future);
      expect(afterDaily.weeklyDone, 1);
      await container.read(notificationSyncProvider.future);
      expect(notifications.resyncCount, 1,
          reason: 'günlük rutin işareti bildirim planını değiştirmez');

      await container.read(todayOccurrencesProvider.notifier).toggle(
            state.monthly.singleWhere((o) => o.periodKey == thisMonth),
          );
      final afterMonthly =
          await container.read(monthOverviewProvider(thisMonth).future);
      expect(afterMonthly.monthly.single.status, OccurrenceStatus.done);
      await container.read(notificationSyncProvider.future);
      expect(notifications.resyncCount, 2);
    });
  });

  group('monthOverviewProvider', () {
    test('içinde bulunulan ay: aylık işler, görevler, bugüne kadarki oran, '
        'sağlık özeti', () async {
      routines.routines = [daily('a'), daily('b'), monthly('m', today.day)];
      routines.completions = {
        RoutineCompletionKey('a', today),
        RoutineCompletionKey('a', thisMonth),
        RoutineCompletionKey('m', thisMonth),
      };
      tasks.tasks = [
        TaskItem(
          id: 't-acik',
          title: 'Açık',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today.add(const Duration(hours: 15)),
        ),
        TaskItem(
          id: 't-bitti',
          title: 'Bitti',
          category: 'Finans',
          priority: 'low',
          status: 'done',
          remindAt: thisMonth.add(const Duration(hours: 9)),
        ),
        TaskItem(
          id: 't-gelecek-ay',
          title: 'Gelecek ay',
          category: 'Kişisel',
          priority: 'low',
          status: 'todo',
          dueAt: DateTime(today.year, today.month + 1, 1, 9),
        ),
        const TaskItem(
          id: 't-tarihsiz',
          title: 'Tarihsiz',
          category: 'Kişisel',
          priority: 'low',
          status: 'todo',
        ),
      ];
      health
        ..metrics = [
          DailyHealthMetric(day: thisMonth, steps: 8000, sleepMinutes: 400),
          DailyHealthMetric(
            day: DateTime(today.year, today.month - 1, 15),
            steps: 99999,
          ),
        ]
        ..nutrition = [DailyNutritionTotal(day: thisMonth, calories: 1900, proteinG: 150, entryCount: 3)]
        ..weights = [
          WeightEntry(id: 'w1', weightKg: 84.5, loggedAt: thisMonth.add(const Duration(hours: 8))),
          WeightEntry(id: 'w0', weightKg: 90, loggedAt: thisMonth.subtract(const Duration(hours: 1))),
        ];

      final overview =
          await makeContainer().read(monthOverviewProvider(thisMonth).future);

      expect(overview.month, thisMonth);
      expect(overview.monthly.single.routine.id, 'm');
      expect(overview.monthly.single.status, OccurrenceStatus.done);
      expect(overview.tasks.map((t) => t.id).toSet(), {'t-acik', 't-bitti'});
      expect(overview.tasksDone, 1);
      expect(overview.weeklyPlanned, 2 * today.day,
          reason: 'gelecek günler planlanmış sayılmaz');
      // 'a' için bugünün kaydı; ayın 1'indeki günlük kayıt da (bugün 1'i
      // değilse) ayrıca sayılır.
      expect(overview.weeklyDone, today.day == 1 ? 1 : 2);
      expect(overview.health.avgSteps, 8000);
      expect(overview.health.avgSleepMinutes, 400);
      expect(overview.health.avgCalories, 1900);
      expect(overview.health.weightStartKg, 84.5);
      expect(overview.health.daysWithData, 1);
    });

    test('geçmiş ay: tüm günler planlı, işaretsiz aylık iş yapılmadı', () async {
      final lastMonth = DateTime(today.year, today.month - 1);
      final days = DateTime(lastMonth.year, lastMonth.month + 1, 0).day;
      routines.routines = [daily('a'), monthly('m', 10)];
      routines.completions = {
        RoutineCompletionKey('a', DateTime(lastMonth.year, lastMonth.month, 3)),
        RoutineCompletionKey('a', today),
      };

      final overview =
          await makeContainer().read(monthOverviewProvider(lastMonth).future);
      expect(overview.weeklyPlanned, days);
      expect(overview.weeklyDone, 1);
      expect(overview.monthly.single.status, OccurrenceStatus.missed);
      expect(overview.monthly.single.periodKey, lastMonth);
    });

    test('gelecek ay: planlanan 0, aylık işler bekliyor', () async {
      final nextMonth = DateTime(today.year, today.month + 1);
      routines.routines = [daily('a'), monthly('m', 10)];
      final overview =
          await makeContainer().read(monthOverviewProvider(nextMonth).future);
      expect(overview.weeklyPlanned, 0);
      expect(overview.weeklyDone, 0);
      expect(overview.monthly.single.status, OccurrenceStatus.upcoming);
      expect(overview.health.daysWithData, 0);
    });

    test('ayın herhangi bir günü verilse de ayın 1\'ine indirgenir', () async {
      final overview = await makeContainer()
          .read(monthOverviewProvider(DateTime(2026, 11, 16, 14)).future);
      expect(overview.month, DateTime(2026, 11));
    });

    test('depo hatası sağlayıcıya yansır', () async {
      tasks.fetchError = Exception('ağ yok');
      final container = makeContainer();
      container.listen(monthOverviewProvider(thisMonth), (_, __) {});
      await expectLater(
        container.read(monthOverviewProvider(thisMonth).future),
        throwsException,
      );
    });
  });

  group('toggleMonthly', () {
    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      RoutineOccurrence Function() occurrence,
      void Function(Object error) onError,
    ) async {
      final container = makeContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  try {
                    await toggleMonthly(ref, occurrence());
                  } catch (e) {
                    onError(e);
                  }
                },
                child: const Text('işaretle'),
              ),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('işaretler, kaldırır ve Gün/Ay verisini tazeler', (tester) async {
      routines.routines = [monthly('m', today.day)];
      late ProviderContainer container;
      RoutineOccurrence current() => container
          .read(monthOverviewProvider(thisMonth))
          .value!
          .monthly
          .single;
      container = await pumpHost(tester, current, (e) => fail('$e'));
      container.listen(monthOverviewProvider(thisMonth), (_, __) {});
      container.listen(todayOccurrencesProvider, (_, __) {});
      await tester.pumpAndSettle();
      expect(current().status, OccurrenceStatus.dueToday);

      await tester.tap(find.text('işaretle'));
      await tester.pumpAndSettle();
      expect(routines.toggles, [
        (routineId: 'm', periodKey: thisMonth, completed: true),
      ]);
      expect(current().status, OccurrenceStatus.done);
      expect(
        container
            .read(todayOccurrencesProvider)
            .value!
            .monthly
            .singleWhere((o) => o.periodKey == thisMonth)
            .completed,
        isTrue,
      );

      await tester.tap(find.text('işaretle'));
      await tester.pumpAndSettle();
      expect(routines.toggles.last.completed, isFalse);
      expect(current().status, OccurrenceStatus.dueToday);
      expect(routines.completions, isEmpty);
    });

    testWidgets('hata çağırana iletilir, veri değişmez', (tester) async {
      routines.routines = [monthly('m', today.day)];
      routines.toggleGate = Completer<void>();
      final errors = <Object>[];
      final occurrence = RoutineOccurrence(
        routine: routines.routines.single,
        periodKey: thisMonth,
        dueDate: today,
        completed: false,
        status: OccurrenceStatus.dueToday,
      );
      await pumpHost(tester, () => occurrence, errors.add);

      await tester.tap(find.text('işaretle'));
      await tester.pump();
      routines.toggleGate!.completeError(Exception('ağ yok'));
      await tester.pumpAndSettle();
      expect(errors, hasLength(1));
      expect(routines.completions, isEmpty);
    });

    testWidgets('yazma bitmeden ekran kapansa da hata vermez', (tester) async {
      routines.routines = [monthly('m', today.day)];
      routines.toggleGate = Completer<void>();
      final errors = <Object>[];
      final occurrence = RoutineOccurrence(
        routine: routines.routines.single,
        periodKey: thisMonth,
        dueDate: today,
        completed: false,
        status: OccurrenceStatus.dueToday,
      );
      final container = await pumpHost(tester, () => occurrence, errors.add);
      await tester.tap(find.text('işaretle'));
      await tester.pump();

      // Ekran ağaçtan çıkar; kapsayıcı (uygulama) yaşamaya devam eder.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox(),
        ),
      );
      routines.toggleGate!.complete();
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
      expect(routines.completions, {RoutineCompletionKey('m', thisMonth)});
    });
  });

  group('userSettingsProvider / settingsOrDefaultProvider', () {
    test('yüklenene kadar varsayılan, sonra veritabanındaki değer', () async {
      settings.settings = const UserSettings.defaults().copyWith(dailyCalories: 2400);
      final container = makeContainer();
      container.listen(settingsOrDefaultProvider, (_, __) {});

      expect(container.read(settingsOrDefaultProvider).dailyCalories, 2000);
      await container.read(userSettingsProvider.future);
      expect(container.read(settingsOrDefaultProvider).dailyCalories, 2400);
    });

    test('satır yoksa varsayılan oluşturulur', () async {
      final container = makeContainer();
      final value = await container.read(userSettingsProvider.future);
      expect(value.toMap(), const UserSettings.defaults().toMap());
      expect(settings.settings, isNotNull);
      expect(settings.fetchCount, 1);
    });

    test('okuma hatasında settingsOrDefault varsayılanı verir', () async {
      settings.fetchError = Exception('ağ yok');
      final container = makeContainer();
      container.listen(userSettingsProvider, (_, __) {});
      await expectLater(
        container.read(userSettingsProvider.future),
        throwsException,
      );
      expect(container.read(userSettingsProvider).hasError, isTrue);
      expect(
        container.read(settingsOrDefaultProvider).toMap(),
        const UserSettings.defaults().toMap(),
      );
    });

    test('save: depoya yazar ve yeni değeri yayınlar', () async {
      final container = makeContainer();
      container.listen(settingsOrDefaultProvider, (_, __) {});
      final current = await container.read(userSettingsProvider.future);

      final saved = await container
          .read(userSettingsProvider.notifier)
          .save(current.copyWith(dailySteps: 12000, teamMembers: ['Ayşe']));

      expect(saved.dailySteps, 12000);
      expect(settings.saved.single.teamMembers, ['Ayşe']);
      expect(container.read(userSettingsProvider).value!.dailySteps, 12000);
      expect(container.read(settingsOrDefaultProvider).teamMembers, ['Ayşe']);
      expect(settings.fetchCount, 1, reason: 'kayıttan sonra yeniden okunmaz');
    });

    test('save hatası iletilir, mevcut değer korunur', () async {
      final container = makeContainer();
      container.listen(userSettingsProvider, (_, __) {});
      final current = await container.read(userSettingsProvider.future);
      settings.saveError = Exception('ağ yok');

      await expectLater(
        container
            .read(userSettingsProvider.notifier)
            .save(current.copyWith(dailySteps: 12000)),
        throwsException,
      );
      expect(container.read(userSettingsProvider).value!.dailySteps, 10000);
    });
  });

  group('notificationSyncProvider', () {
    test('haftalık rutinler ve yaklaşan görevler planlanır; aylık, saatsiz ve '
        'bildirimi kapalı rutinler planlanmaz', () async {
      routines.routines = [
        const Routine(id: 'gunluk', title: 'Günlük', hour: 9, minute: 0),
        const Routine(id: 'pzt', title: 'Pazartesi', daysOfWeek: [1], hour: 11, minute: 0),
        const Routine(id: 'saatsiz', title: 'Saatsiz'),
        const Routine(id: 'sessiz', title: 'Sessiz', hour: 8, minute: 0, notify: false),
        const Routine(id: 'pasif', title: 'Pasif', hour: 8, minute: 0, isActive: false),
        const Routine(
          id: 'aylik',
          title: 'Maaş',
          frequency: RoutineFrequency.monthly,
          dayOfMonth: 15,
          hour: 10,
          minute: 0,
        ),
      ];
      tasks.tasks = [
        TaskItem(
          id: 't1',
          title: 'Vardiya',
          category: 'Ekip',
          priority: 'high',
          status: 'todo',
          assignee: 'Duhan',
          remindAt: DateTime(2099, 1, 5, 14, 30),
          dueAt: DateTime(2099, 1, 5, 15),
        ),
        TaskItem(
          id: 't2',
          title: 'Bitti',
          category: 'Ekip',
          priority: 'low',
          status: 'done',
          dueAt: DateTime(2099, 1, 6),
        ),
        TaskItem(
          id: 't3',
          title: 'Geçmiş',
          category: 'Kişisel',
          priority: 'low',
          status: 'todo',
          dueAt: DateTime(2020),
        ),
      ];

      await makeContainer().read(notificationSyncProvider.future);

      expect(notifications.resyncCount, 1);
      expect(notifications.lastRoutines.map((r) => r.routineId), ['gunluk', 'pzt']);
      expect(notifications.lastRoutines.last.daysOfWeek, [1]);
      final reminder = notifications.lastReminders.single;
      expect(reminder.taskId, 't1');
      expect(reminder.when, DateTime(2099, 1, 5, 14, 30));
      expect(reminder.body, 'Ekip · Duhan');
    });

    test('izin verilmezse hiçbir şey okunmaz ve planlanmaz', () async {
      notifications.permissionGranted = false;
      routines.routines = [const Routine(id: 'a', title: 'A', hour: 9, minute: 0)];
      await makeContainer().read(notificationSyncProvider.future);
      expect(notifications.resyncCount, 0);
      expect(routines.fetchActiveCount, 0);
    });
  });

  test('FakeHealthService hâlâ HealthService sözleşmesine uyar', () async {
    final service = FakeHealthService(
      const HealthSnapshot(status: HealthStatus.ok, steps: 1),
    );
    expect((await service.readToday()).steps, 1);
    expect(await service.readPastDays(), isEmpty);
  });
}

/// Tamamlanma okumasını [readGate] ile bekletir ve beklerken bayat (yazmadan
/// önceki) veriyi döndürür: süren okuma ile biten yazma arasındaki yarışı kurar.
class _SlowReadRepository extends FakeRoutinesRepository {
  _SlowReadRepository({super.routines});

  Completer<void>? readGate;
  Completer<void> readStarted = Completer<void>();
  int completionReads = 0;

  void releaseStale() => readGate?.complete();

  @override
  Future<Set<RoutineCompletionKey>> fetchCompletions(
    DateTime from,
    DateTime to,
  ) async {
    completionReads++;
    final gate = readGate;
    if (gate == null || gate.isCompleted) {
      return super.fetchCompletions(from, to);
    }
    final stale = await super.fetchCompletions(from, to);
    if (!readStarted.isCompleted) readStarted.complete();
    await gate.future;
    return stale;
  }
}
