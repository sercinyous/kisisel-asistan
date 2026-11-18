import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/reminders/data/reminder_action_inbox.dart';
import 'package:kisisel_asistan/features/reminders/domain/reminder.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

Reminder _r({
  ReminderRepeat repeat = ReminderRepeat.daily,
  TimeOfDayValue time = const TimeOfDayValue(22, 0),
  DateTime? onDate,
  int mask = 0,
  bool enabled = true,
}) =>
    Reminder(
      id: 'r1',
      userId: 'u1',
      title: 'Su iç',
      time: time,
      repeat: repeat,
      onDate: onDate,
      daysMask: mask,
      enabled: enabled,
    );

void main() {
  // 2026-11-18 Çarşamba.
  final wed = DateTime(2026, 11, 18, 21, 0);

  group('nextFire', () {
    test('günlük: bugün saat gelmediyse bugün, geçtiyse yarın', () {
      expect(_r().nextFire(wed), DateTime(2026, 11, 18, 22));
      expect(
        _r().nextFire(DateTime(2026, 11, 18, 22, 0)),
        DateTime(2026, 11, 19, 22),
      );
    });

    test('hafta içi: cuma geceden sonra pazartesi', () {
      final r = _r(repeat: ReminderRepeat.weekdays, time: const TimeOfDayValue(9, 0));
      expect(r.nextFire(DateTime(2026, 11, 20, 10)), DateTime(2026, 11, 23, 9));
      expect(r.nextFire(wed), DateTime(2026, 11, 19, 9));
    });

    test('özel günler: yalnızca seçili günler (Pzt + Cmt)', () {
      final r = _r(
        repeat: ReminderRepeat.custom,
        time: const TimeOfDayValue(8, 0),
        mask: ReminderDays.maskOf([1, 6]),
      );
      expect(r.nextFire(wed), DateTime(2026, 11, 21, 8));
      expect(r.nextFire(DateTime(2026, 11, 21, 8, 0)), DateTime(2026, 11, 23, 8));
    });

    test('bir kez: ileri tarihte o an, geçtiyse null; kapalıysa null', () {
      final r = _r(repeat: ReminderRepeat.once, onDate: DateTime(2026, 11, 19));
      expect(r.nextFire(wed), DateTime(2026, 11, 19, 22));
      expect(r.nextFire(DateTime(2026, 11, 19, 22, 1)), isNull);
      expect(_r(enabled: false).nextFire(wed), isNull);
    });

    test('maske dönüşümü', () {
      expect(ReminderDays.maskOf([1, 2, 3, 4, 5]), 0x1F);
      expect(ReminderDays.daysOf(0x41), [1, 7]);
    });
  });

  group('streak', () {
    final today = DateTime(2026, 11, 18);
    DateTime d(int day) => DateTime(2026, 11, day);

    test('günlük: bugün dahil arka arkaya günler', () {
      expect(_r().streak({d(16), d(17), d(18)}, today), 3);
    });

    test('bugün henüz yapılmadıysa seri bozulmaz', () {
      expect(_r().streak({d(16), d(17)}, today), 2);
    });

    test('dün atlandıysa seri sıfırlanır', () {
      expect(_r().streak({d(15), d(16)}, today), 0);
      expect(_r().streak({d(15), d(16), d(18)}, today), 1);
    });

    test('hafta içi: hafta sonu seriyi bozmaz', () {
      final r = _r(repeat: ReminderRepeat.weekdays);
      // Pzt 23 Kasım; önceki Cuma 20 Kasım.
      expect(r.streak({d(19), d(20), d(23)}, d(23)), 3);
    });

    test('bir kezlikte seri yok', () {
      final r = _r(repeat: ReminderRepeat.once, onDate: today);
      expect(r.streak({today}, today), 0);
    });
  });

  test('planlama: kapalılar ve geçmiş bir kezlikler atlanır, sahip yükte', () {
    final list = habitSchedulesOf([
      _r(),
      _r(enabled: false),
      _r(repeat: ReminderRepeat.once, onDate: DateTime(2026, 11, 1)),
    ], wed);
    expect(list, hasLength(1));
    expect(list.single.payload, 'reminder:r1:u1');
    expect(list.single.slots, 1);
    final parsed = ReminderPayload.tryParse(list.single.payload)!;
    expect((parsed.reminderId, parsed.ownerId), ('r1', 'u1'));
    final action = ReminderDoneAction.fromPayload(list.single.payload, wed)!;
    expect(action.day, DateTime(2026, 11, 18));
    expect(ReminderDoneAction.fromJson(action.toJson())!.ownerId, 'u1');
    expect(ReminderPayload.tryParse('task:x'), isNull);
  });

  test('taslak doğrulaması', () {
    const t = TimeOfDayValue(9, 0);
    expect(
      const ReminderDraft(title: ' ', time: t, repeat: ReminderRepeat.daily)
          .validationError,
      isNotNull,
    );
    expect(
      const ReminderDraft(title: 'x', time: t, repeat: ReminderRepeat.custom)
          .validationError,
      isNotNull,
    );
    expect(
      const ReminderDraft(title: 'x', time: t, repeat: ReminderRepeat.once)
          .validationError,
      isNotNull,
    );
    final row = ReminderDraft(
      title: ' Su iç ',
      time: const TimeOfDayValue(22, 0),
      repeat: ReminderRepeat.once,
      onDate: DateTime(2026, 11, 19),
    ).toRow();
    expect(row['title'], 'Su iç');
    expect(row['time_of_day'], '22:00:00');
    expect(row['on_date'], '2026-11-19');
  });

  group('AI hızlı ekleme: hatırlatıcı', () {
    test('"her gün 22:00 su iç" → günlük hatırlatıcı, RPC yüküne girmez', () {
      final entry = ParsedEntry.fromJson({
        'tasks': [],
        'notes': [],
        'routines': [],
        'reminders': [
          {'title': 'Su iç', 'time_of_day': '22:00', 'repeat': 'daily'},
          {'title': 'Saatsiz', 'repeat': 'daily'},
        ],
      }).restrictedTo(QuickAddMode.work);
      expect(entry.reminders, hasLength(1));
      final r = entry.reminders.single;
      expect(r.repeat, ReminderRepeat.daily);
      expect(r.time, const TimeOfDayValue(22, 0));
      expect(r.scheduleLabel, 'Her gün · 22:00');
      expect(entry.totalCount, 1);
      expect(entry.rpcCount, 0);
      expect(entry.toJson().containsKey('reminders'), isFalse);
      expect(entry.without(ParsedKind.reminder, 0).isEmpty, isTrue);
      expect(
        ParsedEntry(reminders: [r]).restrictedTo(QuickAddMode.health).isEmpty,
        isTrue,
      );
    });

    test('özel günler 1-5 hafta içine, tarihsiz bir kez bugüne/yarına düşer', () {
      final weekdays = ParsedReminder.fromJson({
        'title': 'Esneme',
        'time_of_day': '15:00',
        'repeat': 'custom',
        'days_of_week': [1, 2, 3, 4, 5],
      })!;
      expect(weekdays.repeat, ReminderRepeat.weekdays);
      final custom = ParsedReminder.fromJson({
        'title': 'İlaç',
        'time_of_day': '9:00',
        'repeat': 'custom',
        'days_of_week': [0, 3],
      })!;
      expect(ReminderDays.daysOf(custom.daysMask), [3, 7]);
      final once = ParsedReminder.fromJson(
        {'title': 'İlaç', 'time_of_day': '20:00', 'repeat': 'once'},
        now: wed,
      )!;
      expect(once.onDate, DateTime(2026, 11, 19));
      expect(once.toDraft().validationError, isNull);
    });
  });
}
