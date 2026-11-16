// HealthKit'in biten günleri: bugünün okuması günü ancak o ana kadar görür;
// gün bittikten sonra tablo gün sonu değeriyle tamamlanmalıdır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';

import 'helpers/fakes.dart';

void main() {
  group('healthDayWindows', () {
    // 16 Kasım 2026 Pazartesi 09:10.
    final now = DateTime(2026, 11, 16, 9, 10);

    test('son 7 tamamlanmış gün + bugün, eskiden yeniye', () {
      final windows = healthDayWindows(now);
      expect(windows, hasLength(HealthService.backfillDays + 1));
      expect(windows.first.day, DateTime(2026, 11, 9));
      expect(windows.last.day, DateTime(2026, 11, 16));
      expect(
        [for (final w in windows) w.day.day],
        [9, 10, 11, 12, 13, 14, 15, 16],
      );
    });

    test('geçmiş gün: gece yarısından gece yarısına; uyku 18:00 → 18:00', () {
      final yesterday = healthDayWindows(now)[HealthService.backfillDays - 1];
      expect(yesterday.day, DateTime(2026, 11, 15));
      expect(yesterday.end, DateTime(2026, 11, 16));
      expect(yesterday.sleepStart, DateTime(2026, 11, 14, 18));
      expect(yesterday.sleepEnd, DateTime(2026, 11, 15, 18));
    });

    test('bugün şu anda biter; uyku penceresi en geç 18:00\'de kapanır', () {
      final morning = healthDayWindows(now, pastDays: 0).single;
      expect(morning.day, DateTime(2026, 11, 16));
      expect(morning.end, now);
      expect(morning.sleepStart, DateTime(2026, 11, 15, 18));
      expect(morning.sleepEnd, now);

      // Akşam uykusu ertesi günün penceresine aittir; iki güne sayılmaz.
      final night = DateTime(2026, 11, 16, 23, 30);
      final late = healthDayWindows(night, pastDays: 0).single;
      expect(late.end, night);
      expect(late.sleepEnd, DateTime(2026, 11, 16, 18));
    });

    test('ay ve yıl sınırını takvim günüyle aşar', () {
      final windows = healthDayWindows(DateTime(2027, 1, 2, 8), pastDays: 3);
      expect(
        [for (final w in windows) w.day],
        [
          DateTime(2026, 12, 30),
          DateTime(2026, 12, 31),
          DateTime(2027, 1, 1),
          DateTime(2027, 1, 2),
        ],
      );
      expect(windows[1].end, DateTime(2027, 1, 1));
    });
  });

  group('backfillHealthKit', () {
    late DateTime today;
    late DateTime yesterday;
    late DateTime twoDaysAgo;
    late FakeHealthRepository health;
    late FakeHealthService healthKit;

    HealthDayReading reading(
      DateTime day, {
      int steps = 0,
      int activeKcal = 0,
      int sleepMinutes = 0,
    }) =>
        (
          day: day,
          snapshot: HealthSnapshot(
            status: HealthStatus.ok,
            steps: steps,
            activeKcal: activeKcal,
            sleepMinutes: sleepMinutes,
          ),
        );

    setUp(() {
      today = AppDates.startOfDay(DateTime.now());
      yesterday = AppDates.addDays(today, -1);
      twoDaysAgo = AppDates.addDays(today, -2);
      // Dün uygulama son kez 09:00'da açılmış: tabloda o ana kadarki 700 adım.
      health = FakeHealthRepository(
        metrics: [DailyHealthMetric(day: yesterday, steps: 700)],
      );
      healthKit = FakeHealthService(
        HealthSnapshot(
          status: HealthStatus.ok,
          steps: 400,
          readAt: DateTime.now(),
        ),
        pastDays: [
          reading(twoDaysAgo),
          reading(yesterday, steps: 11000, activeKcal: 480, sleepMinutes: 430),
        ],
      );
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          healthRepositoryProvider.overrideWithValue(health),
          healthServiceProvider.overrideWithValue(healthKit),
          routinesRepositoryProvider
              .overrideWithValue(FakeRoutinesRepository()),
          tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    DailyHealthMetric rowOf(Iterable<DailyHealthMetric> days, DateTime day) =>
        days.firstWhere((m) => m.day == day);

    test('dünün satırı gün sonu değeriyle yeniden yazılır ve 7 günlük grafik '
        'tazelenir', () async {
      final container = makeContainer();
      // Sağlık sekmesi gibi: grafik dinleniyor.
      container.listen(weekStepsProvider, (_, __) {});
      expect(
        rowOf(await container.read(weekStepsProvider.future), yesterday).steps,
        700,
      );

      await backfillHealthKit(container);

      final stored = rowOf(health.metrics, yesterday);
      expect(stored.steps, 11000);
      expect(stored.activeKcal, 480);
      expect(stored.sleepMinutes, 430);
      expect(
        health.metrics.where((m) => m.day == twoDaysAgo),
        isEmpty,
        reason: 'verisi olmayan gün yazılmaz (kayıtlı geçmiş sıfırlanmaz)',
      );
      expect(health.upsertedDays, [yesterday]);

      final week = await container.read(weekStepsProvider.future);
      expect(rowOf(week, yesterday).steps, 11000);
      expect(rowOf(week, today).steps, 400, reason: 'bugünün yedeği de görünür');
    });

    test('Ay özetinin sağlık ortalaması da tazelenir', () async {
      final container = makeContainer();
      final month = DateTime(yesterday.year, yesterday.month);
      container.listen(monthOverviewProvider(month), (_, __) {});
      final before = await container.read(monthOverviewProvider(month).future);
      expect(before.health.avgSteps, 700);

      await backfillHealthKit(container);

      final after = await container.read(monthOverviewProvider(month).future);
      expect(after.health.avgSteps, isNot(700));
      expect(after.health.avgSteps, greaterThan(700));
    });

    test('izin yoksa geçmiş günler okunmaz, tablo değişmez', () async {
      healthKit.snapshot = const HealthSnapshot(status: HealthStatus.denied);
      final container = makeContainer();

      await backfillHealthKit(container);

      expect(healthKit.pastDayReads, 0);
      expect(rowOf(health.metrics, yesterday).steps, 700);
      expect(health.upsertedDays, isEmpty);
    });

    test('yedekleme hatası dışarı sızmaz', () async {
      health.upsertError = Exception('ağ yok');
      final container = makeContainer();

      await backfillHealthKit(container);

      expect(rowOf(health.metrics, yesterday).steps, 700);
    });

    test('resyncHealthKit bugünü de yeniden okur', () async {
      final container = makeContainer();
      await backfillHealthKit(container);
      expect(rowOf(health.metrics, today).steps, 400);

      healthKit.snapshot = HealthSnapshot(
        status: HealthStatus.ok,
        steps: 9000,
        readAt: DateTime.now(),
      );
      await resyncHealthKit(container);

      expect(rowOf(health.metrics, today).steps, 9000);
      expect(healthKit.pastDayReads, 2);
    });
  });
}
