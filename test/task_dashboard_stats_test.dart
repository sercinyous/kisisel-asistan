import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/presentation/dashboard/task_dashboard_providers.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/operations/presentation/dashboard/task_dashboard_stats.dart';

/// 17 Kasım 2026 Salı; bu hafta 16–22 Kasım, geçen hafta 9–15 Kasım.
final _now = DateTime(2026, 11, 17, 12);

TaskItem _task(
  String id, {
  String category = 'İş',
  bool done = false,
  DateTime? completedAt,
  DateTime? dueAt,
}) =>
    TaskItem(
      id: id,
      title: id,
      category: category,
      priority: 'medium',
      status: done ? 'done' : 'todo',
      completedAt: completedAt,
      dueAt: dueAt,
    );

void main() {
  test('haftalık sayılar, değişim yüzdesi ve özet', () {
    final stats = computeTaskDashboardStats([
      _task('a', done: true, completedAt: DateTime(2026, 11, 16, 9)),
      _task('b', done: true, completedAt: DateTime(2026, 11, 17, 9)),
      _task('c', done: true, completedAt: DateTime(2026, 11, 17, 10)),
      _task('d', done: true, completedAt: DateTime(2026, 11, 10, 9)),
      _task('e', done: true, completedAt: DateTime(2026, 11, 11, 9)),
      _task('a', done: true, completedAt: DateTime(2026, 11, 16, 9)),
    ], now: _now);
    expect(stats.weeks, hasLength(8));
    expect(stats.weeks.last.weekStart, DateTime(2026, 11, 16));
    expect(stats.thisWeek, 3);
    expect(stats.lastWeek, 2);
    expect(stats.weekChangePercent, 50);
    expect(stats.summary, 'Bu hafta geçen haftaya göre %50 daha fazla');
    expect(stats.bestWeekday, DateTime.tuesday);
    expect(turkishWeekday(stats.bestWeekday!), 'Salı');
  });

  test('azalış ve geçen hafta sıfır', () {
    final down = computeTaskDashboardStats([
      _task('a', done: true, completedAt: DateTime(2026, 11, 16)),
      _task('b', done: true, completedAt: DateTime(2026, 11, 10)),
      _task('c', done: true, completedAt: DateTime(2026, 11, 12)),
      _task('d', done: true, completedAt: DateTime(2026, 11, 13)),
      _task('e', done: true, completedAt: DateTime(2026, 11, 14)),
    ], now: _now);
    expect(down.weekChangePercent, -75);
    expect(down.summary, 'Bu hafta geçen haftaya göre %75 daha az');

    final empty = computeTaskDashboardStats(const [], now: _now);
    expect(empty.weekChangePercent, isNull);
    expect(empty.completionRate, isNull);
    expect(empty.bestWeekday, isNull);
    expect(empty.categories, isEmpty);
  });

  test('geciken, tamamlama oranı ve kategori dağılımı', () {
    final stats = computeTaskDashboardStats([
      _task('late', dueAt: DateTime(2026, 11, 15), category: 'Ev'),
      _task('future', dueAt: DateTime(2026, 11, 20)),
      _task('nodate', category: 'Ev'),
      _task('ok',
          done: true,
          dueAt: DateTime(2026, 11, 14),
          completedAt: DateTime(2026, 11, 14)),
      _task('old',
          done: true,
          dueAt: DateTime(2025, 1, 1),
          completedAt: DateTime(2025, 1, 1)),
    ], now: _now);
    expect(stats.overdueCount, 1);
    expect(stats.scheduledCount, 2);
    expect(stats.scheduledDone, 1);
    expect(stats.completionRate, 0.5);
    expect(
        stats.categories.map((e) => '${e.key}:${e.value}'), ['Ev:2', 'İş:2']);
  });

  test('terminsiz tamamlanan görev haftalık sayıya girer', () {
    final stats = computeTaskDashboardStats([
      _task('nodate-done', done: true, completedAt: DateTime(2026, 11, 16, 8)),
    ], now: _now);
    expect(stats.thisWeek, 1);
    expect(stats.weekdayCounts[0], 1);
  });

  test('pano sağlayıcısı terminsiz tamamlananları da çeker', () async {
    final now = DateTime.now();
    final repo = FakeTasksRepository(tasks: [
      _task('nodate-done', done: true, completedAt: now),
      _task('very-old', done: true, completedAt: DateTime(2020, 1, 1)),
    ]);
    expect(await repo.fetchCompletedSince(now.subtract(const Duration(days: 1))),
        hasLength(1));
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final stats = await container.read(taskDashboardProvider.future);
    expect(stats.thisWeek, 1);
  });
}
