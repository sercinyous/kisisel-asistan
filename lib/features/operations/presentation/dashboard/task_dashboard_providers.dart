import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart';
import '../../data/tasks_repository.dart';
import 'task_dashboard_stats.dart';

/// Pano: açık görevler + son 8 haftaya (ve bu haftanın sonuna) planlanmış
/// görevler + son 8 haftada tamamlananlar (terminsiz olanlar da sayılsın); istatistikler [computeTaskDashboardStats] ile türetilir.
final taskDashboardProvider =
    FutureProvider.autoDispose<TaskDashboardStats>((ref) async {
  final repo = ref.watch(tasksRepositoryProvider);
  final now = DateTime.now();
  const weeks = 8;
  final thisWeek = AppDates.weekStart(now);
  final from = AppDates.addDays(thisWeek, -7 * (weeks - 1));
  final to = AppDates.addDays(thisWeek, 7);
  final results = await Future.wait([
    repo.fetchOpen(),
    repo.fetchInRange(from, to),
    repo.fetchCompletedSince(from),
  ]);
  return computeTaskDashboardStats(
    [for (final list in results) ...list],
    now: now,
    weekCount: weeks,
  );
});

/// Operasyon ekranında görev panosu açık mı (başlıktaki grafik düğmesi).
final opsDashboardVisibleProvider = StateProvider<bool>((ref) => false);
