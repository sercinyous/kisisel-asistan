import '../../../../core/utils/date_utils.dart';
import '../../domain/task_item.dart';

/// Bir haftanın tamamlanan görev sayısı.
class WeekCount {
  const WeekCount(this.weekStart, this.count);

  final DateTime weekStart;
  final int count;
}

/// Görev panosunun türetilmiş istatistikleri.
class TaskDashboardStats {
  const TaskDashboardStats({
    required this.weeks,
    required this.categories,
    required this.completionRate,
    required this.scheduledCount,
    required this.scheduledDone,
    required this.overdueCount,
    required this.weekdayCounts,
    required this.bestWeekday,
    required this.weekChangePercent,
  });

  /// Eskiden yeniye; son eleman bu hafta.
  final List<WeekCount> weeks;

  /// Kategori → görev sayısı, çoktan aza.
  final List<MapEntry<String, int>> categories;

  /// Pencerede zamanı gelmiş görevlerden tamamlananların oranı (0–1);
  /// görev yoksa `null`.
  final double? completionRate;
  final int scheduledCount;
  final int scheduledDone;

  /// Termini geçmiş açık görevler.
  final int overdueCount;

  /// Pazartesi (0) … Pazar (6) tamamlanma sayıları.
  final List<int> weekdayCounts;

  /// En çok tamamlama yapılan gün ([DateTime.monday]…[DateTime.sunday]);
  /// tamamlama yoksa `null`.
  final int? bestWeekday;

  /// Bu haftanın geçen haftaya göre yüzde değişimi; geçen hafta 0 ise `null`.
  final int? weekChangePercent;

  int get thisWeek => weeks.isEmpty ? 0 : weeks.last.count;
  int get lastWeek => weeks.length < 2 ? 0 : weeks[weeks.length - 2].count;

  /// "Bu hafta geçen haftaya göre %X" özet satırı.
  String get summary {
    final change = weekChangePercent;
    if (change == null) {
      return thisWeek == 0
          ? 'Bu hafta ve geçen hafta tamamlanan görev yok'
          : 'Bu hafta $thisWeek görev tamamlandı; geçen hafta hiç yoktu';
    }
    if (change == 0) return 'Bu hafta geçen haftaya göre %0 (aynı)';
    return change > 0
        ? 'Bu hafta geçen haftaya göre %$change daha fazla'
        : 'Bu hafta geçen haftaya göre %${-change} daha az';
  }
}

/// Saf istatistik hesabı. [tasks] tekrar içerebilir (id ile tekilleştirilir).
/// [weekCount] haftalık grafiğin uzunluğu; oran ve kategori penceresi de
/// aynı haftaları kapsar.
TaskDashboardStats computeTaskDashboardStats(
  Iterable<TaskItem> tasks, {
  required DateTime now,
  int weekCount = 8,
}) {
  final unique = <String, TaskItem>{for (final t in tasks) t.id: t};
  final thisWeek = AppDates.weekStart(now);
  final windowStart = AppDates.addDays(thisWeek, -7 * (weekCount - 1));

  final weekCounts = List<int>.filled(weekCount, 0);
  final weekdayCounts = List<int>.filled(7, 0);
  final categories = <String, int>{};
  var scheduled = 0, scheduledDone = 0, overdue = 0;

  for (final t in unique.values) {
    final done = t.completedAt;
    final inWindow = t.isDone &&
        done != null &&
        !done.isBefore(windowStart) &&
        done.isBefore(AppDates.addDays(thisWeek, 7));
    if (inWindow) {
      final ws = AppDates.weekStart(done);
      final index = ws.difference(windowStart).inDays ~/ 7;
      if (index >= 0 && index < weekCount) weekCounts[index]++;
      weekdayCounts[done.weekday - 1]++;
    }

    final at = t.scheduledAt;
    final relevant =
        !t.isDone || inWindow || (at != null && !at.isBefore(windowStart));
    if (relevant) categories[t.category] = (categories[t.category] ?? 0) + 1;

    if (at != null && !at.isBefore(windowStart) && !at.isAfter(now)) {
      scheduled++;
      if (t.isDone) scheduledDone++;
    }
    final due = t.dueAt;
    if (!t.isDone && due != null && due.isBefore(now)) overdue++;
  }

  int? best;
  var bestCount = 0;
  for (var i = 0; i < 7; i++) {
    if (weekdayCounts[i] > bestCount) {
      bestCount = weekdayCounts[i];
      best = i + 1;
    }
  }

  final current = weekCounts.last;
  final previous = weekCount >= 2 ? weekCounts[weekCount - 2] : 0;
  final change =
      previous == 0 ? null : ((current - previous) * 100 / previous).round();

  final sortedCategories = categories.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });

  return TaskDashboardStats(
    weeks: [
      for (var i = 0; i < weekCount; i++)
        WeekCount(AppDates.addDays(windowStart, 7 * i), weekCounts[i]),
    ],
    categories: sortedCategories,
    completionRate: scheduled == 0 ? null : scheduledDone / scheduled,
    scheduledCount: scheduled,
    scheduledDone: scheduledDone,
    overdueCount: overdue,
    weekdayCounts: weekdayCounts,
    bestWeekday: best,
    weekChangePercent: change,
  );
}

/// Pazartesi = 1 … Pazar = 7.
String turkishWeekday(int weekday) => const [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ][weekday - 1];
