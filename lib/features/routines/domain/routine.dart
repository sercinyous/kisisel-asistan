import '../../../core/utils/date_utils.dart';

/// Tekrarlama türü. Günlük iş, haftanın 7 gününe yayılmış haftalık iştir.
enum RoutineFrequency {
  weekly,
  monthly;

  static RoutineFrequency fromDb(Object? value) =>
      value == 'monthly' ? RoutineFrequency.monthly : RoutineFrequency.weekly;

  String get dbValue => name;
}

/// `routines` tablosundaki bir satır (tekrarlayan iş tanımı).
class Routine {
  const Routine({
    required this.id,
    required this.title,
    this.scope = scopePersonal,
    this.category = 'kisisel',
    this.frequency = RoutineFrequency.weekly,
    this.daysOfWeek = everyDay,
    this.dayOfMonth,
    this.hour,
    this.minute,
    this.notify = true,
    this.isActive = true,
    this.sortOrder = 0,
    this.createdAt,
  });

  static const String scopeWork = 'Pusholder';
  static const String scopePersonal = 'Kişisel';
  static const List<String> scopes = [scopeWork, scopePersonal];
  static const List<String> categories = [
    'operasyon',
    'spor',
    'beslenme',
    'kisisel',
    'finans',
  ];
  static const List<int> everyDay = [1, 2, 3, 4, 5, 6, 7];

  /// Henüz kaydedilmemiş taslaklarda boş metindir.
  final String id;
  final String title;
  final String scope;
  final String category;
  final RoutineFrequency frequency;

  /// ISO gün numaraları (1 = Pazartesi ... 7 = Pazar). Yalnızca haftalıkta anlamlı.
  final List<int> daysOfWeek;

  /// 1..31. Yalnızca aylıkta anlamlı; ay kısaysa ayın son günü geçerlidir.
  final int? dayOfMonth;
  final int? hour;
  final int? minute;
  final bool notify;
  final bool isActive;
  final int sortOrder;

  /// Rutin oluşturulmadan önceki dönemler "yapılmadı" sayılmasın diye tutulur.
  final DateTime? createdAt;

  bool get isMonthly => frequency == RoutineFrequency.monthly;

  bool get isDaily =>
      frequency == RoutineFrequency.weekly && daysOfWeek.toSet().length == 7;

  bool get hasTime => hour != null && minute != null;

  String? get timeLabel => hasTime
      ? '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
      : null;

  factory Routine.fromMap(Map<String, dynamic> map) {
    int? hour;
    int? minute;
    final time = map['time_of_day'];
    if (time is String) {
      final parts = time.split(':');
      if (parts.length >= 2) {
        hour = int.tryParse(parts[0]);
        minute = int.tryParse(parts[1]);
      }
    }
    // Yarım okunan saat (yalnızca biri sayı) saat yok sayılır.
    if (hour == null || minute == null) {
      hour = null;
      minute = null;
    }
    final days = map['days_of_week'];
    final created = map['created_at'];
    return Routine(
      id: map['id'] as String,
      title: map['title'] as String,
      scope: map['scope'] as String? ?? scopePersonal,
      category: map['category'] as String? ?? 'kisisel',
      frequency: RoutineFrequency.fromDb(map['frequency']),
      daysOfWeek: days is List
          ? days.whereType<num>().map((e) => e.toInt()).toList()
          : everyDay,
      dayOfMonth: (map['day_of_month'] as num?)?.toInt(),
      hour: hour,
      minute: minute,
      notify: map['notify'] as bool? ?? true,
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: created is String ? DateTime.tryParse(created)?.toLocal() : null,
    );
  }

  /// Ekleme ve güncelleme için yazılabilir sütunlar (id, user_id ve zaman
  /// damgalarını veritabanı yönetir).
  Map<String, dynamic> toInsertMap() {
    final days = daysOfWeek.toSet().toList()..sort();
    return {
      'title': title.trim(),
      'scope': scope,
      'category': category,
      'frequency': frequency.dbValue,
      // Tablo boş gün listesini kabul etmez; aylıkta günler zaten yok sayılır.
      'days_of_week': isMonthly || days.isEmpty ? everyDay : days,
      'day_of_month': isMonthly ? dayOfMonth : null,
      'time_of_day': timeLabel,
      'notify': notify,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  Routine copyWith({
    String? id,
    String? title,
    String? scope,
    String? category,
    RoutineFrequency? frequency,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? hour,
    int? minute,
    bool clearTime = false,
    bool? notify,
    bool? isActive,
    int? sortOrder,
  }) =>
      Routine(
        id: id ?? this.id,
        title: title ?? this.title,
        scope: scope ?? this.scope,
        category: category ?? this.category,
        frequency: frequency ?? this.frequency,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        hour: clearTime ? null : (hour ?? this.hour),
        minute: clearTime ? null : (minute ?? this.minute),
        notify: notify ?? this.notify,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}

/// Bir rutinin bir dönemdeki tamamlanma kaydı. Eşitlik yalnızca
/// (rutin, dönem) üzerindendir; [completedAt] kimliğe dahil değildir.
class RoutineCompletionKey {
  RoutineCompletionKey(this.routineId, DateTime periodKey, {this.completedAt})
      : periodKey = AppDates.startOfDay(periodKey);

  final String routineId;

  /// Haftalık/günlükte o gün, aylıkta ayın 1'i (yerel gün).
  final DateTime periodKey;

  /// İşaretlendiği an (yerel). Aylık işin "bugün tamamlandı" olarak Gün
  /// ekranında kalması için kullanılır.
  final DateTime? completedAt;

  factory RoutineCompletionKey.fromMap(Map<String, dynamic> map) {
    final at = map['completed_at'];
    return RoutineCompletionKey(
      map['routine_id'] as String,
      DateTime.parse(map['completed_on'] as String),
      completedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoutineCompletionKey &&
      other.routineId == routineId &&
      other.periodKey == periodKey;

  @override
  int get hashCode => Object.hash(routineId, periodKey);

  @override
  String toString() =>
      'RoutineCompletionKey($routineId, ${AppDates.ymd(periodKey)})';
}

enum OccurrenceStatus {
  /// Bu dönem için işaretlendi.
  done,

  /// Günü bugün.
  dueToday,

  /// Günü henüz gelmedi.
  upcoming,

  /// Günü geçti, dönemi (ay) henüz bitmedi.
  overdue,

  /// Dönemi işaretlenmeden kapandı.
  missed,
}

/// Bir rutinin tek bir döneme (gün ya da ay) düşen örneği.
class RoutineOccurrence {
  const RoutineOccurrence({
    required this.routine,
    required this.periodKey,
    required this.dueDate,
    required this.completed,
    required this.status,
  });

  final Routine routine;
  final DateTime periodKey;
  final DateTime dueDate;
  final bool completed;
  final OccurrenceStatus status;

  RoutineCompletionKey get completionKey =>
      RoutineCompletionKey(routine.id, periodKey);

  /// Güne kalan takvim günü: 0 = bugün, eksi = gecikme.
  int daysUntilDue(DateTime today) => _calendarDays(today, dueDate);
}

// Yaz saati geçişlerinde 23/25 saatlik günler farkı kaydırmasın diye UTC.
int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Aylık işin verilen aydaki günü: `min(day_of_month, ayın son günü)`.
/// Hafta sonuna denk gelse de tarih kaymaz.
DateTime monthlyDueDate(Routine r, int year, int month) {
  final first = DateTime(year, month);
  final last = _daysInMonth(first.year, first.month);
  final day = (r.dayOfMonth ?? 1).clamp(1, last);
  return DateTime(first.year, first.month, day);
}

/// [day] gününün ait olduğu dönemin anahtarı: haftalıkta günün kendisi,
/// aylıkta o ayın 1'i.
DateTime periodKeyFor(Routine r, DateTime day) =>
    r.isMonthly ? DateTime(day.year, day.month) : AppDates.startOfDay(day);

bool _existsOn(Routine r, DateTime day) {
  final created = r.createdAt;
  return created == null || !day.isBefore(AppDates.startOfDay(created));
}

bool _existsInMonth(Routine r, int year, int month) {
  final created = r.createdAt;
  return created == null ||
      !DateTime(year, month).isBefore(DateTime(created.year, created.month));
}

int _compareByTime(Routine a, Routine b) {
  final ta = a.hasTime ? a.hour! * 60 + a.minute! : 24 * 60;
  final tb = b.hasTime ? b.hour! * 60 + b.minute! : 24 * 60;
  if (ta != tb) return ta.compareTo(tb);
  if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
  return a.title.compareTo(b.title);
}

int _compareByDue(RoutineOccurrence a, RoutineOccurrence b) {
  final byDue = a.dueDate.compareTo(b.dueDate);
  return byDue != 0 ? byDue : _compareByTime(a.routine, b.routine);
}

/// [day] gününe düşen günlük/haftalık rutinler (saat, sonra sıra numarası).
/// Aylık işler burada yer almaz.
List<RoutineOccurrence> occurrencesForDay(
  Iterable<Routine> routines,
  Set<RoutineCompletionKey> completions,
  DateTime day,
) {
  final key = AppDates.startOfDay(day);
  final due = routines
      .where((r) =>
          r.isActive && !r.isMonthly && r.daysOfWeek.contains(key.weekday))
      .toList()
    ..sort(_compareByTime);
  return due.map((r) {
    final done = completions.contains(RoutineCompletionKey(r.id, key));
    return RoutineOccurrence(
      routine: r,
      periodKey: key,
      dueDate: key,
      completed: done,
      status: done ? OccurrenceStatus.done : OccurrenceStatus.dueToday,
    );
  }).toList();
}

OccurrenceStatus _openStatus(DateTime due, DateTime today) {
  final days = _calendarDays(today, due);
  if (days > 0) return OccurrenceStatus.upcoming;
  return days == 0 ? OccurrenceStatus.dueToday : OccurrenceStatus.overdue;
}

/// Gün ekranındaki aylık işler ([today] itibarıyla, güne göre sıralı).
///
/// Bir iş, gününden [leadDays] gün önce listeye girer ve işaretlenene kadar
/// kalır; günü geçince `overdue` olur ve ay bitince düşer (eski ay birikmez).
/// Pencere ay sınırını aşabilir: ayın 1'indeki iş önceki ayın son günlerinde
/// GELECEK ayın dönemiyle görünür. İşaretlenen iş, günü gelene kadar ve
/// işaretlendiği gün boyunca `done` olarak görünmeye devam eder.
List<RoutineOccurrence> monthlyForDay(
  Iterable<Routine> routines,
  Set<RoutineCompletionKey> completions,
  DateTime today,
  int leadDays,
) {
  final day = AppDates.startOfDay(today);
  final result = <RoutineOccurrence>[];

  for (final r in routines) {
    if (!r.isActive || !r.isMonthly) continue;
    // Bu ayın dönemi ve (pencere ay sınırını aşıyorsa) gelecek ayınki.
    for (final offset in const [0, 1]) {
      final key = DateTime(day.year, day.month + offset);
      final due = monthlyDueDate(r, key.year, key.month);
      if (_calendarDays(day, due) > leadDays) continue;

      final record = completions.lookup(RoutineCompletionKey(r.id, key));
      if (record != null) {
        final at = record.completedAt;
        final doneToday = at != null && AppDates.startOfDay(at) == day;
        if (day.isAfter(due) && !doneToday) continue;
      }
      result.add(
        RoutineOccurrence(
          routine: r,
          periodKey: key,
          dueDate: due,
          completed: record != null,
          status:
              record != null ? OccurrenceStatus.done : _openStatus(due, day),
        ),
      );
    }
  }
  return result..sort(_compareByDue);
}

/// Ay ekranındaki "Aylık sabitler": verilen ayın tüm aylık işleri.
/// Geçmiş ayda işaretlenmemiş iş `missed` (yapılmadı) olarak kapanır.
/// Rutinin oluşturulduğu aydan önceki aylar listelenmez.
List<RoutineOccurrence> monthlyForMonth(
  Iterable<Routine> routines,
  Set<RoutineCompletionKey> completions,
  int year,
  int month,
  DateTime today,
) {
  final key = DateTime(year, month);
  final day = AppDates.startOfDay(today);
  final isPast = key.isBefore(DateTime(day.year, day.month));
  final result = <RoutineOccurrence>[];

  for (final r in routines) {
    if (!r.isActive || !r.isMonthly) continue;
    if (!_existsInMonth(r, key.year, key.month)) continue;
    final due = monthlyDueDate(r, key.year, key.month);
    final done = completions.contains(RoutineCompletionKey(r.id, key));
    result.add(
      RoutineOccurrence(
        routine: r,
        periodKey: key,
        dueDate: due,
        completed: done,
        status: done
            ? OccurrenceStatus.done
            : isPast
                ? OccurrenceStatus.missed
                : _openStatus(due, day),
      ),
    );
  }
  return result..sort(_compareByDue);
}

/// [from]..[to] (iki uç dahil) aralığında günlük/haftalık rutinlerin planlanan
/// ve tamamlanan sayısı. Rutinin oluşturulmasından önceki günler sayılmaz.
({int planned, int done}) weeklyStatsForRange(
  Iterable<Routine> routines,
  Set<RoutineCompletionKey> completions,
  DateTime from,
  DateTime to,
) {
  final weekly = routines.where((r) => r.isActive && !r.isMonthly).toList();
  final last = AppDates.startOfDay(to);
  var planned = 0;
  var done = 0;
  for (var day = AppDates.startOfDay(from);
      !day.isAfter(last);
      day = DateTime(day.year, day.month, day.day + 1)) {
    for (final r in weekly) {
      if (!r.daysOfWeek.contains(day.weekday) || !_existsOn(r, day)) continue;
      planned++;
      if (completions.contains(RoutineCompletionKey(r.id, day))) done++;
    }
  }
  return (planned: planned, done: done);
}
