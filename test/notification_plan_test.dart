import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_plan.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  // 16 Kasım 2026 Pazartesi 10:00 (Kasım 30 gün çeker).
  final now = DateTime(2026, 11, 16, 10);
  const defaults = UserSettings.defaults();

  TaskItem task(String id,
          {DateTime? due, DateTime? remind, String status = 'todo', bool notify = true}) =>
      TaskItem(
        id: id,
        title: 'Görev $id',
        category: 'Ekip',
        priority: 'medium',
        status: status,
        dueAt: due,
        remindAt: remind,
        notify: notify,
      );

  Routine monthly(String id, int day, {int? hour, int? minute}) => Routine(
        id: id,
        title: 'Aylık $id',
        frequency: RoutineFrequency.monthly,
        dayOfMonth: day,
        hour: hour,
        minute: minute,
      );

  List<PlannedNotification> plan({
    UserSettings settings = defaults,
    List<Routine> routines = const [],
    Set<RoutineCompletionKey>? completions,
    List<TaskItem> tasks = const [],
    DateTime? at,
  }) =>
      buildNotificationPlan(
        now: at ?? now,
        settings: settings,
        routines: routines,
        completions: completions ?? {},
        tasks: tasks,
      );

  test('tüm bildirimler kapalıyken hiçbir şey planlanmaz', () {
    final result = plan(
      settings: defaults.copyWith(notificationsEnabled: false),
      routines: [
        const Routine(id: 'g', title: 'Günlük', hour: 9, minute: 0),
        monthly('m', 20),
      ],
      tasks: [task('t', due: DateTime(2026, 11, 20, 12))],
    );
    expect(result, isEmpty);
  });

  test('rutinler: günlük tek, haftalık gün başına tekrar; kapalıysa yok', () {
    final routines = [
      const Routine(id: 'g', title: 'Günlük', hour: 9, minute: 0),
      const Routine(id: 'h', title: 'Haftalık', daysOfWeek: [1, 3], hour: 11, minute: 0),
      const Routine(id: 's', title: 'Sessiz', hour: 8, minute: 0, notify: false),
      const Routine(id: 'z', title: 'Saatsiz'),
    ];
    final result = plan(routines: routines);
    expect(result.map((p) => p.key), ['routine:h:1', 'routine:g', 'routine:h:3']);
    expect(result[0].fireAt, DateTime(2026, 11, 16, 11));
    expect(result[0].repeat, PlannedRepeat.weekly);
    expect(result[1].fireAt, DateTime(2026, 11, 17, 9));
    expect(result[1].repeat, PlannedRepeat.daily);
    expect(result[2].fireAt, DateTime(2026, 11, 18, 11));
    expect(result.map((p) => p.id).toSet().length, 3);

    expect(
      plan(settings: defaults.copyWith(routineNotifications: false), routines: routines),
      isEmpty,
    );
  });

  test('aylık iş: bu ay ve gelecek ay için ön hatırlatma + gün; 31 kısa ayda '
      'son güne çekilir', () {
    final result = plan(routines: [monthly('m', 31), monthly('s', 20, hour: 14, minute: 15)]);
    expect(
      {for (final p in result) p.key: p.fireAt},
      {
        'monthly:s:2026-11:lead': DateTime(2026, 11, 17, 9),
        'monthly:s:2026-11:due': DateTime(2026, 11, 20, 14, 15),
        'monthly:m:2026-11:lead': DateTime(2026, 11, 27, 9),
        'monthly:m:2026-11:due': DateTime(2026, 11, 30, 9),
        'monthly:s:2026-12:lead': DateTime(2026, 12, 17, 9),
        'monthly:s:2026-12:due': DateTime(2026, 12, 20, 14, 15),
        'monthly:m:2026-12:lead': DateTime(2026, 12, 28, 9),
        'monthly:m:2026-12:due': DateTime(2026, 12, 31, 9),
      },
    );
    expect(result.every((p) => !p.isRepeating), isTrue);
    expect(result.first.kind, PlannedKind.monthlyLead);
    // Zamana göre sıralı.
    for (var i = 1; i < result.length; i++) {
      expect(result[i].fireAt.isBefore(result[i - 1].fireAt), isFalse);
    }
  });

  test('aylık iş: tamamlanan dönem ve geçmiş zamanlar atlanır; 0 gün önce '
      'tekrar üretmez', () {
    final done = plan(
      routines: [monthly('m', 20)],
      completions: {RoutineCompletionKey('m', DateTime(2026, 11))},
    );
    expect(done.map((p) => p.key), ['monthly:m:2026-12:lead', 'monthly:m:2026-12:due']);

    final late = plan(routines: [monthly('m', 20)], at: DateTime(2026, 11, 18, 10));
    expect(late.first.key, 'monthly:m:2026-11:due');
    expect(late.length, 3);

    final noLead = plan(
      settings: defaults.copyWith(monthlyLeadDays: 0),
      routines: [monthly('m', 20)],
    );
    expect(noLead.map((p) => p.key), ['monthly:m:2026-11:due', 'monthly:m:2026-12:due']);
  });

  test('görev: remind_at varsa o, yoksa termin − dakika; geçmiş ve biten yok', () {
    final result = plan(
      settings: defaults.copyWith(eventRemindMinutes: 45),
      tasks: [
        task('a', due: DateTime(2026, 11, 17, 15), remind: DateTime(2026, 11, 17, 12)),
        task('b', due: DateTime(2026, 11, 17, 15)),
        task('c', due: DateTime(2026, 11, 16, 10, 30)),
        task('d', due: DateTime(2026, 11, 18, 15), status: 'done'),
        task('e'),
      ],
    );
    expect(result.map((p) => p.key), ['task:a', 'task:b']);
    expect(result[0].fireAt, DateTime(2026, 11, 17, 12));
    expect(result[1].fireAt, DateTime(2026, 11, 17, 14, 15));
    expect(result[1].kind, PlannedKind.task);
  });

  test('sessiz saatler gece yarısını aşar: aralıktaki bildirim bitişe ertelenir', () {
    final tasks = [
      task('aksam', remind: DateTime(2026, 11, 16, 23, 30)),
      task('gece', remind: DateTime(2026, 11, 17, 2)),
      task('once', remind: DateTime(2026, 11, 16, 22, 59)),
      task('bitis', remind: DateTime(2026, 11, 17, 7, 30)),
    ];
    final shifted = {for (final p in plan(tasks: tasks)) p.sourceId: p.fireAt};
    expect(shifted, {
      'aksam': DateTime(2026, 11, 17, 7, 30),
      'gece': DateTime(2026, 11, 17, 7, 30),
      'once': DateTime(2026, 11, 16, 22, 59),
      'bitis': DateTime(2026, 11, 17, 7, 30),
    });

    // Kapalıyken ya da başlangıç = bitiş iken dokunulmaz.
    for (final s in [
      defaults.copyWith(quietHoursEnabled: false),
      defaults.copyWith(quietStart: const TimeOfDayValue(8, 0), quietEnd: const TimeOfDayValue(8, 0)),
    ]) {
      final raw = {for (final p in plan(settings: s, tasks: tasks)) p.sourceId: p.fireAt};
      expect(raw['aksam'], DateTime(2026, 11, 16, 23, 30));
      expect(raw['gece'], DateTime(2026, 11, 17, 2));
    }

    // Pazartesi 23:30 rutini salı 07:30'a kayar.
    final routine = plan(
      routines: [
        const Routine(id: 'r', title: 'Gece', daysOfWeek: [1], hour: 23, minute: 30),
      ],
    ).single;
    expect(routine.fireAt, DateTime(2026, 11, 17, 7, 30));
    expect(routine.fireAt.weekday, DateTime.tuesday);
  });

  test('64 sınırı: en yakınlar kalır, uzaktakiler atılır', () {
    final tasks = [
      for (var i = 69; i >= 0; i--)
        task('t$i', remind: DateTime(2026, 11, 17, 12).add(Duration(days: i))),
    ];
    final result = plan(tasks: tasks);
    expect(result.length, maxPendingNotifications);
    expect(result.first.sourceId, 't0');
    expect(result.last.sourceId, 't63');
  });

  group('görev hatırlatması kapalı (notify = false)', () {
    final due = DateTime(2026, 11, 17, 15);

    test('termini olsa da bildirim planlanmaz', () {
      expect(plan(tasks: [task('t1', due: due, notify: false)]), isEmpty);
    });

    test('kayıtlı hatırlatma saati olsa da planlanmaz', () {
      final remind = due.subtract(const Duration(minutes: 30));
      expect(
        plan(tasks: [task('t1', due: due, remind: remind, notify: false)]),
        isEmpty,
      );
    });

    test('açık görev etkilenmez: termin − varsayılan süre', () {
      final result = plan(tasks: [
        task('kapali', due: due, notify: false),
        task('acik', due: due),
      ]);
      expect(result.map((p) => p.key), ['task:acik']);
      expect(
        result.single.fireAt,
        due.subtract(Duration(minutes: defaults.eventRemindMinutes)),
      );
    });
  });
}
