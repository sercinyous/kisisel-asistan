import '../core/utils/date_utils.dart';
import '../features/health/data/water_repository.dart';
import '../features/reports/data/weekly_checkin_repository.dart';

/// Bellekte su kayıtları (demo ve testler).
class FakeWaterRepository implements WaterRepository {
  FakeWaterRepository(
      {List<WaterLog>? logs, this.targetMl = defaultDailyWaterMl})
      : logs = logs ?? [];

  final List<WaterLog> logs;
  int targetMl;
  int _nextId = 1;

  @override
  Future<List<WaterLog>> fetchDay(DateTime day) async {
    final d = AppDates.startOfDay(day);
    return [
      for (final l in logs)
        if (l.loggedOn == d) l,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<WaterLog> add(DateTime day, int ml) async {
    if (ml < 1 || ml > maxWaterLogMl) {
      throw ArgumentError.value(ml, 'ml', '1–$maxWaterLogMl arası olmalı');
    }
    final log = WaterLog(
      id: 'water-${_nextId++}',
      loggedOn: AppDates.startOfDay(day),
      ml: ml,
      createdAt: DateTime.now(),
    );
    logs.add(log);
    return log;
  }

  @override
  Future<void> delete(String id) async => logs.removeWhere((l) => l.id == id);

  @override
  Future<int> fetchDailyTarget() async => targetMl;

  @override
  Future<void> setDailyTarget(int ml) async => targetMl = ml;
}

/// Bellekte haftalık check-in'ler (demo ve testler).
class FakeWeeklyCheckinRepository implements WeeklyCheckinRepository {
  final Map<DateTime, WeeklyCheckin> checkins = {};

  @override
  Future<WeeklyCheckin?> fetch(DateTime weekStart) async =>
      checkins[AppDates.startOfDay(weekStart)];

  @override
  Future<WeeklyCheckin> save(WeeklyCheckin checkin) async {
    final note = checkin.note?.trim();
    final saved = WeeklyCheckin(
      weekStart: AppDates.startOfDay(checkin.weekStart),
      mood: checkin.mood,
      note: note == null || note.isEmpty ? null : note,
    );
    checkins[saved.weekStart] = saved;
    return saved;
  }
}
