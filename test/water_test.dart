import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_health_extras.dart';
import 'package:kisisel_asistan/features/health/presentation/water_providers.dart';
import 'package:kisisel_asistan/features/reports/domain/weekly_checkin.dart';

WaterLog _log(String id, DateTime day, int ml) =>
    WaterLog(id: id, loggedOn: day, ml: ml, createdAt: day);

void main() {
  final day = DateTime(2026, 11, 18);

  group('su toplamları', () {
    test('yalnızca o günün kayıtları toplanır', () {
      final logs = [
        _log('a', day, 250),
        _log('b', day, 500),
        _log('c', DateTime(2026, 11, 17), 1000),
      ];
      expect(waterTotalForDay(logs, day), 750);
      expect(waterTotalForDay(logs, DateTime(2026, 11, 17, 15)), 1000);
      expect(waterTotalForDay(const [], day), 0);
    });

    test('ilerleme 0–1 arasına kırpılır', () {
      expect(waterProgress(1000, 2000), 0.5);
      expect(waterProgress(2500, 2000), 1);
      expect(waterProgress(500, 0), 0);
    });

    test('biçim', () {
      expect(formatWaterMl(750), '750 ml');
      expect(formatWaterMl(1000), '1 L');
      expect(formatWaterMl(1250), '1,25 L');
      expect(formatWaterMl(1500), '1,5 L');
    });

    test('satırdan model', () {
      final log = WaterLog.fromMap({
        'id': 'x',
        'logged_on': '2026-11-18',
        'ml': 250,
        'created_at': '2026-11-18T08:00:00Z',
      });
      expect(log.loggedOn, day);
      expect(log.ml, 250);
    });
  });

  test('sağlayıcı: ekle, toplam, geri al', () async {
    final repo = FakeWaterRepository(targetMl: 2500);
    final container = ProviderContainer(
      overrides: [waterRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    var today = await container.read(waterTodayProvider.future);
    expect(today.totalMl, 0);
    expect(today.targetMl, 2500);
    expect(today.canUndo, isFalse);

    final notifier = container.read(waterTodayProvider.notifier);
    await notifier.add(250);
    await notifier.add(500);
    today = container.read(waterTodayProvider).requireValue;
    expect(today.totalMl, 750);
    expect(today.day, AppDates.startOfDay(DateTime.now()));

    await notifier.undo();
    today = container.read(waterTodayProvider).requireValue;
    expect(today.totalMl, 250);
    expect(repo.logs, hasLength(1));
  });

  group('haftalık check-in günü', () {
    test('Pazar akşamı bu hafta, Pazartesi geçen hafta', () {
      // 22 Kasım 2026 Pazar, 23 Kasım Pazartesi.
      expect(checkinWeekFor(DateTime(2026, 11, 22, 18)), DateTime(2026, 11, 16));
      expect(checkinWeekFor(DateTime(2026, 11, 22, 10)), isNull);
      expect(checkinWeekFor(DateTime(2026, 11, 23, 9)), DateTime(2026, 11, 16));
      expect(checkinWeekFor(DateTime(2026, 11, 18, 20)), isNull);
    });

    test('demo deposu notu kırpar ve haftaya yazar', () async {
      final repo = FakeWeeklyCheckinRepository();
      await repo.save(WeeklyCheckin(
          weekStart: DateTime(2026, 11, 16), mood: 4, note: '  '));
      final saved = await repo.fetch(DateTime(2026, 11, 16));
      expect(saved!.mood, 4);
      expect(saved.note, isNull);
    });
  });
}
