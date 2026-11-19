import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/kokpit/domain/month_calendar.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_format.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

Routine monthlyRoutine(String id, int day) => Routine(
      id: id,
      title: 'Aylık $id',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: day,
    );

RoutineOccurrence occurrence(
  Routine routine,
  DateTime due, {
  bool completed = false,
  OccurrenceStatus status = OccurrenceStatus.upcoming,
}) =>
    RoutineOccurrence(
      routine: routine,
      periodKey: DateTime(due.year, due.month),
      dueDate: due,
      completed: completed,
      status: completed ? OccurrenceStatus.done : status,
    );

TaskItem task(String id, {DateTime? dueAt, DateTime? remindAt, bool done = false}) =>
    TaskItem(
      id: id,
      title: 'Görev $id',
      category: 'Kişisel',
      priority: 'medium',
      status: done ? 'done' : 'todo',
      dueAt: dueAt,
      remindAt: remindAt,
    );

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('monthGrid', () {
    void expectShape(
      int year,
      int month, {
      required int weeks,
      required int leading,
      required int trailing,
      required int days,
    }) {
      final grid = monthGrid(year, month);
      expect(grid, hasLength(weeks), reason: '$year-$month hafta sayısı');
      expect(grid.every((week) => week.length == 7), isTrue);
      final cells = grid.expand((week) => week).toList();
      expect(cells.takeWhile((c) => c == null).length, leading);
      expect(cells.reversed.takeWhile((c) => c == null).length, trailing);
      final dates = cells.whereType<DateTime>().toList();
      expect(dates, [for (var d = 1; d <= days; d++) DateTime(year, month, d)]);
      // Her gün kendi hafta günü sütununda (Pzt = 0 … Paz = 6).
      for (final week in grid) {
        for (final (column, day) in week.indexed) {
          if (day != null) expect(day.weekday - 1, column);
        }
      }
    }

    test('Pazar başlayan, artık olmayan Şubat (2026): 6 boş + 28 gün + 1 boş',
        () {
      expectShape(2026, 2, weeks: 5, leading: 6, trailing: 1, days: 28);
    });

    test('Pazartesi başlayan 28 günlük Şubat (2027): tam 4 hafta, boş yok', () {
      expectShape(2027, 2, weeks: 4, leading: 0, trailing: 0, days: 28);
    });

    test('artık yıl Şubatı (2028): 29 gün', () {
      expectShape(2028, 2, weeks: 5, leading: 1, trailing: 5, days: 29);
    });

    test('Pazar başlayan 31 günlük ay (Mart 2026): 6 hafta', () {
      expectShape(2026, 3, weeks: 6, leading: 6, trailing: 5, days: 31);
    });

    test('Cumartesi başlayan 31 günlük ay (Ağustos 2026): 6 hafta', () {
      expectShape(2026, 8, weeks: 6, leading: 5, trailing: 6, days: 31);
    });

    test('Pazar başlayan 30 günlük ay (Kasım 2026): son gün Pazartesi', () {
      expectShape(2026, 11, weeks: 6, leading: 6, trailing: 6, days: 30);
    });

    test('yıl sınırı: Aralık ve Ocak', () {
      expectShape(2026, 12, weeks: 5, leading: 1, trailing: 3, days: 31);
      expectShape(2027, 1, weeks: 5, leading: 4, trailing: 0, days: 31);
    });
  });

  group('dayMarksFor', () {
    final month = DateTime(2026, 11);

    test('aylık işler ve görevler günlerine dağıtılır', () {
      final salary = occurrence(monthlyRoutine('m1', 15), DateTime(2026, 11, 15));
      final report = occurrence(
        monthlyRoutine('m2', 15),
        DateTime(2026, 11, 15),
        completed: true,
      );
      final late = task('t2', dueAt: DateTime(2026, 11, 15, 18));
      final early = task('t1', dueAt: DateTime(2026, 11, 15, 9));
      final remindOnly = task('t3', remindAt: DateTime(2026, 11, 20, 8));

      final marks = dayMarksFor(month, [salary, report], [late, early, remindOnly]);

      expect(marks.keys.toSet(), {15, 20});
      expect(marks[15]!.monthly, [salary, report]);
      expect(marks[15]!.tasks.map((t) => t.id), ['t1', 't2'],
          reason: 'görevler saate göre sıralanır');
      expect(marks[15]!.monthlyAllDone, isFalse);
      expect(marks[20]!.hasMonthly, isFalse);
      expect(marks[20]!.tasks.single.id, 't3');
    });

    test('başka aya ait ya da tarihsiz kayıtlar yok sayılır', () {
      final marks = dayMarksFor(
        month,
        [occurrence(monthlyRoutine('m1', 1), DateTime(2026, 12, 1))],
        [
          task('t1'),
          task('t2', dueAt: DateTime(2026, 10, 31, 23, 59)),
          task('t3', dueAt: DateTime(2027, 11, 15)),
        ],
      );
      expect(marks, isEmpty);
    });

    test('hepsi kapanınca "allDone" olur', () {
      final marks = dayMarksFor(
        month,
        [
          occurrence(
            monthlyRoutine('m1', 3),
            DateTime(2026, 11, 3),
            completed: true,
          ),
        ],
        [task('t1', dueAt: DateTime(2026, 11, 3, 10), done: true)],
      );
      expect(marks[3]!.monthlyAllDone, isTrue);
      expect(marks[3]!.tasksAllDone, isTrue);
      expect(DayMarks.empty.isEmpty, isTrue);
      expect(DayMarks.empty.monthlyAllDone, isFalse);
    });
  });

  group('withCompletion', () {
    final today = DateTime(2026, 11, 16);
    RoutineOccurrence due(int day, {bool completed = false}) => occurrence(
          monthlyRoutine('m', day),
          DateTime(2026, 11, day),
          completed: completed,
        );

    test('işaretlenince done', () {
      final result = withCompletion(due(20), true, today);
      expect(result.completed, isTrue);
      expect(result.status, OccurrenceStatus.done);
      expect(result.completionKey, due(20).completionKey);
    });

    test('işaret kalkınca güne göre durum', () {
      expect(withCompletion(due(20, completed: true), false, today).status,
          OccurrenceStatus.upcoming);
      expect(withCompletion(due(16, completed: true), false, today).status,
          OccurrenceStatus.dueToday);
      expect(withCompletion(due(10, completed: true), false, today).status,
          OccurrenceStatus.overdue);
    });
  });

  test('completionPercent', () {
    expect(completionPercent(0, 0), isNull);
    expect(completionPercent(0, 10), 0);
    expect(completionPercent(14, 28), 50);
    expect(completionPercent(2, 3), 67);
    expect(completionPercent(10, 10), 100);
  });

  group('KokpitFormat', () {
    test('durum rozetleri ve renkleri', () {
      expect(
        OccurrenceStatus.values.map(KokpitFormat.statusLabel),
        ['Yapıldı', 'Bugün', 'Bekliyor', 'Gecikti', 'Yapılmadı'],
      );
      expect(KokpitFormat.statusColor(OccurrenceStatus.overdue), AppColors.danger);
      expect(KokpitFormat.statusColor(OccurrenceStatus.done), AppColors.accent);
    });

    test('ay başlığı, uyku ve kilo biçimleri', () {
      expect(KokpitFormat.monthTitle(DateTime(2026, 11)), 'Kasım 2026');
      expect(KokpitFormat.monthTitle(DateTime(2026, 2)), 'Şubat 2026');
      expect(KokpitFormat.dayMonth(DateTime(2026, 11, 15)), '15 Kasım');
      expect(KokpitFormat.sleep(450), '7 sa 30 dk');
      expect(KokpitFormat.sleep(0), '—');
      expect(KokpitFormat.sleep(null), '—');
      expect(KokpitFormat.weightChange(-1.2), '−1,2 kg');
      expect(KokpitFormat.weightChange(0.84), '+0,8 kg');
      expect(KokpitFormat.weightChange(-0.04), '0,0 kg');
      expect(KokpitFormat.kg(84.5), '84,5');
      expect(KokpitFormat.percent(82), '%82');
    });
  });
}
