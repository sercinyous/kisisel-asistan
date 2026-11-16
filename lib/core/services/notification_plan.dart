import '../../features/operations/domain/task_item.dart';
import '../../features/routines/domain/routine.dart';
import '../../features/settings/domain/user_settings.dart';

/// iOS aynı anda en fazla 64 bekleyen yerel bildirim tutar.
const int maxPendingNotifications = 64;

enum PlannedKind {
  /// Her gün tekrar eden rutin.
  routineDaily,

  /// Haftanın belirli bir günü tekrar eden rutin.
  routineWeekly,

  /// Aylık işin gününden önceki ön hatırlatma (tek seferlik).
  monthlyLead,

  /// Aylık işin günündeki hatırlatma (tek seferlik).
  monthlyDue,

  /// Tek seferlik görev/randevu hatırlatması.
  task,
}

enum PlannedRepeat { none, daily, weekly }

/// Planlanan tek bir yerel bildirim.
class PlannedNotification {
  const PlannedNotification({
    required this.key,
    required this.kind,
    required this.sourceId,
    required this.title,
    required this.body,
    required this.fireAt,
    this.repeat = PlannedRepeat.none,
  });

  /// Çalıştırmalar arasında değişmeyen anahtar; [id] bundan türetilir.
  final String key;
  final PlannedKind kind;

  /// Rutin ya da görev kimliği.
  final String sourceId;
  final String title;
  final String body;

  /// Tek seferlikte tetiklenme anı; tekrar edende bir sonraki tetiklenme
  /// (saat ve — haftalıkta — hafta günü buradan okunur).
  final DateTime fireAt;
  final PlannedRepeat repeat;

  int get id => stableNotificationId(key);

  bool get isRepeating => repeat != PlannedRepeat.none;

  @override
  String toString() => 'PlannedNotification($key, $fireAt, ${repeat.name})';
}

/// Çalıştırmalar arasında değişmeyen 31 bit'lik kimlik (FNV-1a).
int stableNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}

/// Bekleyen bildirimlerin tamamını hesaplar (saf fonksiyon; eklentiye dokunmaz).
///
/// [completions] bu ayın ve gelecek ayın dönem kayıtlarını içermelidir;
/// [tasks] açık (tamamlanmamış) görevlerdir. Sonuç tetiklenme zamanına göre
/// sıralıdır ve en fazla [maxPending] öğe içerir (uzaktakiler atılır).
List<PlannedNotification> buildNotificationPlan({
  required DateTime now,
  required UserSettings settings,
  required List<Routine> routines,
  required Set<RoutineCompletionKey> completions,
  required List<TaskItem> tasks,
  int maxPending = maxPendingNotifications,
}) {
  if (!settings.notificationsEnabled) return const [];

  final quiet = _QuietHours.from(settings);
  final plan = <PlannedNotification>[];

  for (final r in routines) {
    if (!r.isActive || !r.notify) continue;
    if (r.isMonthly) {
      plan.addAll(_monthly(r, now, settings, completions, quiet));
    } else if (settings.routineNotifications && r.hasTime) {
      plan.addAll(_weekly(r, now, quiet));
    }
  }

  for (final t in tasks) {
    // "Hatırlat" kapalı görev, termini olsa da bildirim almaz.
    if (t.isDone || !t.notify) continue;
    final due = t.dueAt;
    var when = t.remindAt ??
        due?.subtract(Duration(minutes: settings.eventRemindMinutes));
    // Hatırlatma anı çoktan geçmiş ama randevu hâlâ ileride ("20 dk sonra
    // toplantı", ayar 30 dk): hiç haber vermemek yerine randevu anında haber ver.
    if (when != null && !when.isAfter(now) && due != null && due.isAfter(now)) {
      when = due;
    }
    if (when == null || !when.isAfter(now)) continue;
    plan.add(
      PlannedNotification(
        key: 'task:${t.id}',
        kind: PlannedKind.task,
        sourceId: t.id,
        title: t.title,
        body: t.assignee == null ? t.category : '${t.category} · ${t.assignee}',
        fireAt: quiet.shift(when),
      ),
    );
  }

  plan.sort((a, b) {
    final byTime = a.fireAt.compareTo(b.fireAt);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  });
  return plan.length <= maxPending ? plan : plan.sublist(0, maxPending);
}

Iterable<PlannedNotification> _weekly(
  Routine r,
  DateTime now,
  _QuietHours quiet,
) sync* {
  final (minutes, dayOffset) = quiet.shiftMinutes(r.hour! * 60 + r.minute!);
  final hour = minutes ~/ 60;
  final minute = minutes % 60;

  var next = DateTime(now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  if (r.isDaily) {
    yield PlannedNotification(
      key: 'routine:${r.id}',
      kind: PlannedKind.routineDaily,
      sourceId: r.id,
      title: r.title,
      body: 'Günlük rutin zamanı',
      fireAt: next,
      repeat: PlannedRepeat.daily,
    );
    return;
  }

  final days = r.daysOfWeek.where((d) => d >= 1 && d <= 7).toSet().toList()
    ..sort();
  for (final day in days) {
    // Sessiz saat gece yarısını aşıyorsa bildirim ertesi güne kayar.
    final weekday = (day - 1 + dayOffset) % 7 + 1;
    var at = next;
    while (at.weekday != weekday) {
      at = DateTime(at.year, at.month, at.day + 1, hour, minute);
    }
    yield PlannedNotification(
      key: 'routine:${r.id}:$day',
      kind: PlannedKind.routineWeekly,
      sourceId: r.id,
      title: r.title,
      body: 'Bugünün rutini',
      fireAt: at,
      repeat: PlannedRepeat.weekly,
    );
  }
}

Iterable<PlannedNotification> _monthly(
  Routine r,
  DateTime now,
  UserSettings settings,
  Set<RoutineCompletionKey> completions,
  _QuietHours quiet,
) sync* {
  final remind = settings.monthlyRemindTime;
  for (var offset = 0; offset <= 1; offset++) {
    final period = DateTime(now.year, now.month + offset);
    if (completions.contains(RoutineCompletionKey(r.id, period))) continue;

    final due = monthlyDueDate(r, period.year, period.month);
    final periodKey =
        '${period.year}-${period.month.toString().padLeft(2, '0')}';
    final dueLabel =
        '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}';

    // Ön hatırlatma 0 günse günündeki bildirimle aynı olur; tekrarlanmaz.
    if (settings.monthlyLeadDays > 0) {
      final leadAt = DateTime(
        due.year,
        due.month,
        due.day - settings.monthlyLeadDays,
        remind.hour,
        remind.minute,
      );
      if (leadAt.isAfter(now)) {
        yield PlannedNotification(
          key: 'monthly:${r.id}:$periodKey:lead',
          kind: PlannedKind.monthlyLead,
          sourceId: r.id,
          title: r.title,
          body: '${settings.monthlyLeadDays} gün kaldı · son gün $dueLabel',
          fireAt: quiet.shift(leadAt),
        );
      }
    }

    final dueAt = DateTime(
      due.year,
      due.month,
      due.day,
      r.hasTime ? r.hour! : remind.hour,
      r.hasTime ? r.minute! : remind.minute,
    );
    if (dueAt.isAfter(now)) {
      yield PlannedNotification(
        key: 'monthly:${r.id}:$periodKey:due',
        kind: PlannedKind.monthlyDue,
        sourceId: r.id,
        title: r.title,
        body: 'Bugün son gün',
        fireAt: quiet.shift(dueAt),
      );
    }
  }
}

/// Sessiz saat aralığı `[start, end)`; gece yarısını aşabilir.
class _QuietHours {
  const _QuietHours(this.enabled, this.start, this.end);

  factory _QuietHours.from(UserSettings s) {
    final start = s.quietStart.minutesSinceMidnight;
    final end = s.quietEnd.minutesSinceMidnight;
    // Başlangıç = bitiş boş aralıktır (tüm gün değil).
    return _QuietHours(s.quietHoursEnabled && start != end, start, end);
  }

  final bool enabled;
  final int start;
  final int end;

  /// Gün içi dakikayı aralık dışına taşır: (yeni dakika, gün kayması 0|1).
  (int, int) shiftMinutes(int minutes) {
    if (!enabled) return (minutes, 0);
    if (start < end) {
      return minutes >= start && minutes < end ? (end, 0) : (minutes, 0);
    }
    if (minutes >= start) return (end, 1);
    if (minutes < end) return (end, 0);
    return (minutes, 0);
  }

  DateTime shift(DateTime at) {
    final minutes = at.hour * 60 + at.minute;
    final (shifted, dayOffset) = shiftMinutes(minutes);
    if (shifted == minutes && dayOffset == 0) return at;
    return DateTime(
      at.year,
      at.month,
      at.day + dayOffset,
      shifted ~/ 60,
      shifted % 60,
    );
  }
}
