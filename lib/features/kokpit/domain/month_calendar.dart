import '../../operations/domain/task_item.dart';
import '../../routines/domain/routine.dart';

/// Pazartesi başlangıçlı ay ızgarası. Her hafta 7 hücredir; ayın dışında
/// kalan baştaki ve sondaki hücreler `null` olur.
List<List<DateTime?>> monthGrid(int year, int month) {
  final first = DateTime(year, month);
  final dayCount = DateTime(first.year, first.month + 1, 0).day;
  final cells = <DateTime?>[
    for (var i = DateTime.monday; i < first.weekday; i++) null,
    for (var d = 1; d <= dayCount; d++) DateTime(first.year, first.month, d),
  ];
  while (cells.length % DateTime.daysPerWeek != 0) {
    cells.add(null);
  }
  return [
    for (var i = 0; i < cells.length; i += DateTime.daysPerWeek)
      cells.sublist(i, i + DateTime.daysPerWeek),
  ];
}

/// Takvimde bir güne düşen kayıtlar.
class DayMarks {
  const DayMarks({this.monthly = const [], this.tasks = const []});

  static const DayMarks empty = DayMarks();

  /// Günü bu tarihe denk gelen aylık işler.
  final List<RoutineOccurrence> monthly;

  /// Takvim anı bu güne düşen görev/randevular (saate göre sıralı).
  final List<TaskItem> tasks;

  bool get isEmpty => monthly.isEmpty && tasks.isEmpty;
  bool get hasMonthly => monthly.isNotEmpty;
  bool get hasTasks => tasks.isNotEmpty;

  /// Hepsi kapandıysa nokta soluk çizilir.
  bool get monthlyAllDone => hasMonthly && monthly.every((o) => o.completed);
  bool get tasksAllDone => hasTasks && tasks.every((t) => t.isDone);
}

/// Verilen ayın günlerine (1..31) düşen aylık işler ve görevler.
/// Başka aya ait ya da takvim anı olmayan kayıtlar yok sayılır.
Map<int, DayMarks> dayMarksFor(
  DateTime month,
  Iterable<RoutineOccurrence> monthly,
  Iterable<TaskItem> tasks,
) {
  bool inMonth(DateTime d) => d.year == month.year && d.month == month.month;

  final monthlyByDay = <int, List<RoutineOccurrence>>{};
  for (final occurrence in monthly) {
    if (!inMonth(occurrence.dueDate)) continue;
    (monthlyByDay[occurrence.dueDate.day] ??= []).add(occurrence);
  }

  final tasksByDay = <int, List<TaskItem>>{};
  for (final task in tasks) {
    final at = task.scheduledAt;
    if (at == null || !inMonth(at)) continue;
    (tasksByDay[at.day] ??= []).add(task);
  }
  for (final list in tasksByDay.values) {
    list.sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
  }

  return {
    for (final day in {...monthlyByDay.keys, ...tasksByDay.keys})
      day: DayMarks(
        monthly: monthlyByDay[day] ?? const [],
        tasks: tasksByDay[day] ?? const [],
      ),
  };
}

/// Tamamlanma yüzdesi (0..100). Planlanan yoksa oran anlamsızdır: `null`.
int? completionPercent(int done, int planned) =>
    planned <= 0 ? null : (done * 100 / planned).round().clamp(0, 100);
