/// Hatırlatıcı (Ayarlar > Hatırlatıcılar): kullanıcının kendi saatli
/// hatırlatmaları. Tablo: `public.reminders`; "Yaptım": `public.reminder_done`.
library;

import '../../settings/domain/user_settings.dart';

enum ReminderRepeat {
  once('once', 'Bir kez'),
  daily('daily', 'Her gün'),
  weekdays('weekdays', 'Hafta içi'),
  custom('custom', 'Özel günler');

  const ReminderRepeat(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ReminderRepeat fromDb(Object? value) => ReminderRepeat.values
      .firstWhere((r) => r.dbValue == value, orElse: () => ReminderRepeat.daily);
}

/// Tarih saatsiz (yerel gün).
DateTime reminderDay(DateTime d) => DateTime(d.year, d.month, d.day);

abstract final class ReminderDays {
  static const List<String> shortLabels = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  /// ISO günleri (1 = Pazartesi ... 7 = Pazar) → bit maskesi (bit 0 = Pzt).
  static int maskOf(Iterable<int> isoDays) {
    var mask = 0;
    for (final d in isoDays) {
      if (d >= 1 && d <= 7) mask |= 1 << (d - 1);
    }
    return mask;
  }

  /// Bit maskesi → sıralı ISO günleri.
  static List<int> daysOf(int mask) => [
        for (var d = 1; d <= 7; d++)
          if (mask & (1 << (d - 1)) != 0) d,
      ];
}

/// Kaydetmeden önceki (ve düzenlenen) hatırlatıcı alanları.
class ReminderDraft {
  const ReminderDraft({
    required this.title,
    required this.time,
    required this.repeat,
    this.onDate,
    this.daysMask = 0,
    this.enabled = true,
  });

  static const int maxTitleLength = 120;

  final String title;
  final TimeOfDayValue time;
  final ReminderRepeat repeat;

  /// Yalnızca [ReminderRepeat.once] için dolu.
  final DateTime? onDate;

  /// Yalnızca [ReminderRepeat.custom] için anlamlı (bit 0 = Pazartesi).
  final int daysMask;
  final bool enabled;

  /// Kaydedilemeyecek taslağın Türkçe nedeni; geçerliyse `null`.
  String? get validationError {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Başlık boş olamaz.';
    if (trimmed.runes.length > maxTitleLength) {
      return 'Başlık en fazla $maxTitleLength karakter olabilir.';
    }
    if (repeat == ReminderRepeat.once && onDate == null) {
      return 'Bir kez çalacak hatırlatıcı için tarih seçin.';
    }
    if (repeat == ReminderRepeat.custom && daysMask & 0x7F == 0) {
      return 'En az bir gün seçin.';
    }
    return null;
  }

  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'time_of_day': '${time.format()}:00',
        'repeat': repeat.dbValue,
        'on_date': repeat == ReminderRepeat.once && onDate != null
            ? _ymd(onDate!)
            : null,
        'days_mask': repeat == ReminderRepeat.custom ? daysMask & 0x7F : 0,
        'enabled': enabled,
      };
}

String _two(int n) => n.toString().padLeft(2, '0');

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

class Reminder {
  const Reminder({
    required this.id,
    required this.userId,
    required this.title,
    required this.time,
    required this.repeat,
    this.onDate,
    this.daysMask = 0,
    this.enabled = true,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final TimeOfDayValue time;
  final ReminderRepeat repeat;
  final DateTime? onDate;
  final int daysMask;
  final bool enabled;
  final DateTime? createdAt;

  factory Reminder.fromMap(Map<String, dynamic> map) {
    final onDate = map['on_date'];
    final created = map['created_at'];
    return Reminder(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: (map['title'] as String?) ?? '',
      time: TimeOfDayValue.tryParse(map['time_of_day']) ??
          const TimeOfDayValue(9, 0),
      repeat: ReminderRepeat.fromDb(map['repeat']),
      onDate: onDate is String ? DateTime.tryParse(onDate) : null,
      daysMask: (map['days_mask'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }

  ReminderDraft toDraft() => ReminderDraft(
        title: title,
        time: time,
        repeat: repeat,
        onDate: onDate,
        daysMask: daysMask,
        enabled: enabled,
      );

  Reminder copyWithDraft(ReminderDraft d) => Reminder(
        id: id,
        userId: userId,
        title: d.title.trim(),
        time: d.time,
        repeat: d.repeat,
        onDate: d.repeat == ReminderRepeat.once ? d.onDate : null,
        daysMask: d.repeat == ReminderRepeat.custom ? d.daysMask & 0x7F : 0,
        enabled: d.enabled,
        createdAt: createdAt,
      );

  bool get isRepeating => repeat != ReminderRepeat.once;

  /// Tekrar eden hatırlatıcının çaldığı ISO günleri; bir kezlikte boş.
  List<int> get isoDays => switch (repeat) {
        ReminderRepeat.once => const [],
        ReminderRepeat.daily => const [1, 2, 3, 4, 5, 6, 7],
        ReminderRepeat.weekdays => const [1, 2, 3, 4, 5],
        ReminderRepeat.custom => ReminderDays.daysOf(daysMask),
      };

  /// [day] (yerel gün) bu hatırlatıcının çaldığı günlerden biri mi?
  bool isScheduledOn(DateTime day) {
    if (repeat == ReminderRepeat.once) {
      final d = onDate;
      return d != null && reminderDay(d) == reminderDay(day);
    }
    return isoDays.contains(day.weekday);
  }

  /// [now]'dan SONRAKİ ilk çalma anı (yerel); kapalıysa ya da bir kezlik
  /// hatırlatıcının anı geçtiyse `null`.
  DateTime? nextFire(DateTime now) {
    if (!enabled) return null;
    if (repeat == ReminderRepeat.once) {
      final d = onDate;
      if (d == null) return null;
      final at = DateTime(d.year, d.month, d.day, time.hour, time.minute);
      return at.isAfter(now) ? at : null;
    }
    final days = isoDays;
    if (days.isEmpty) return null;
    for (var i = 0; i <= 7; i++) {
      final at = DateTime(now.year, now.month, now.day + i, time.hour, time.minute);
      if (days.contains(at.weekday) && at.isAfter(now)) return at;
    }
    return null;
  }

  /// Arka arkaya "Yaptım" denen planlı gün sayısı. Planlı olmayan günler
  /// atlanır; bugün henüz yapılmadıysa seri bozulmaz (dünden sayılır).
  /// Bir kezlik hatırlatıcıda seri yoktur (0).
  int streak(Set<DateTime> doneDays, DateTime today) {
    if (repeat == ReminderRepeat.once || isoDays.isEmpty) return 0;
    final done = {for (final d in doneDays) reminderDay(d)};
    final start = reminderDay(today);
    var day = start;
    var count = 0;
    for (var i = 0; i < 730; i++) {
      if (isScheduledOn(day)) {
        if (done.contains(day)) {
          count++;
        } else if (day != start) {
          break;
        }
      }
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  /// "Her gün · 22:00", "Pzt, Çar · 09:00", "18 Kas 2026 · 10:00".
  String get scheduleLabel {
    final clock = time.format();
    final String when = switch (repeat) {
      ReminderRepeat.once => onDate == null
          ? 'Bir kez'
          : '${_two(onDate!.day)}.${_two(onDate!.month)}.${onDate!.year}',
      ReminderRepeat.daily => 'Her gün',
      ReminderRepeat.weekdays => 'Hafta içi',
      ReminderRepeat.custom =>
        isoDays.map((d) => ReminderDays.shortLabels[d - 1]).join(', '),
    };
    return '$when · $clock';
  }
}

/// Bildirim planına giden tek hatırlatıcı.
class HabitReminderSchedule {
  const HabitReminderSchedule({
    required this.reminderId,
    required this.ownerId,
    required this.title,
    required this.hour,
    required this.minute,
    required this.isoDays,
    this.onceAt,
  });

  final String reminderId;

  /// Bildirimdeki "Yaptım" eylemi yalnızca bu kullanıcı oturumdayken yazılır.
  final String ownerId;
  final String title;
  final int hour;
  final int minute;

  /// Tekrar eden günler (ISO); bir kezlikte boş ve [onceAt] dolu.
  final List<int> isoDays;
  final DateTime? onceAt;

  /// Bekleyen bildirim sayısı (iOS sınırı için).
  int get slots => onceAt != null
      ? 1
      : isoDays.toSet().length == 7
          ? 1
          : isoDays.toSet().length;

  /// Bildirim yükü: `reminder:<id>:<owner>`.
  String get payload => '${ReminderPayload.prefix}$reminderId:$ownerId';
}

/// Bildirim yükünün çözümlenmesi.
class ReminderPayload {
  const ReminderPayload(this.reminderId, this.ownerId);

  static const String prefix = 'reminder:';

  final String reminderId;
  final String ownerId;

  static ReminderPayload? tryParse(String? payload) {
    if (payload == null || !payload.startsWith(prefix)) return null;
    final parts = payload.substring(prefix.length).split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return ReminderPayload(parts[0], parts[1]);
  }
}

/// Planlanacak hatırlatıcılar: açık olanlar; bir kezlikler yalnızca ileri
/// tarihliyse. Sıra: tekrar edenler önce, sonra en yakın bir kezlik.
List<HabitReminderSchedule> habitSchedulesOf(
  List<Reminder> reminders,
  DateTime now,
) {
  final repeating = <HabitReminderSchedule>[];
  final once = <HabitReminderSchedule>[];
  for (final r in reminders) {
    if (!r.enabled) continue;
    if (r.repeat == ReminderRepeat.once) {
      final at = r.nextFire(now);
      if (at == null) continue;
      once.add(HabitReminderSchedule(
        reminderId: r.id,
        ownerId: r.userId,
        title: r.title,
        hour: r.time.hour,
        minute: r.time.minute,
        isoDays: const [],
        onceAt: at,
      ));
    } else {
      if (r.isoDays.isEmpty) continue;
      repeating.add(HabitReminderSchedule(
        reminderId: r.id,
        ownerId: r.userId,
        title: r.title,
        hour: r.time.hour,
        minute: r.time.minute,
        isoDays: r.isoDays,
      ));
    }
  }
  once.sort((a, b) => a.onceAt!.compareTo(b.onceAt!));
  return [...repeating, ...once];
}

/// Hazır şablonlar: tek dokunuşla taslağı doldurur.
class ReminderTemplate {
  const ReminderTemplate({
    required this.label,
    required this.title,
    required this.time,
    required this.repeat,
    this.daysMask = 0,
  });

  final String label;
  final String title;
  final TimeOfDayValue time;
  final ReminderRepeat repeat;
  final int daysMask;

  static const List<ReminderTemplate> all = [
    ReminderTemplate(
      label: 'Su iç',
      title: 'Su iç',
      time: TimeOfDayValue(11, 0),
      repeat: ReminderRepeat.daily,
    ),
    ReminderTemplate(
      label: 'İlaç',
      title: 'İlacını al',
      time: TimeOfDayValue(9, 0),
      repeat: ReminderRepeat.daily,
    ),
    ReminderTemplate(
      label: 'Yürüyüş',
      title: 'Yürüyüşe çık',
      time: TimeOfDayValue(18, 30),
      repeat: ReminderRepeat.daily,
    ),
    ReminderTemplate(
      label: 'Uyku saati',
      title: 'Uyku saati',
      time: TimeOfDayValue(23, 0),
      repeat: ReminderRepeat.daily,
    ),
    ReminderTemplate(
      label: 'Esneme molası',
      title: 'Esneme molası',
      time: TimeOfDayValue(15, 0),
      repeat: ReminderRepeat.weekdays,
    ),
  ];

  ReminderDraft toDraft() => ReminderDraft(
        title: title,
        time: time,
        repeat: repeat,
        daysMask: daysMask,
      );
}
