/// Haftalık check-in: 1–5 ruh hali + kısa not.
class WeeklyCheckin {
  const WeeklyCheckin({
    required this.weekStart,
    required this.mood,
    this.note,
  });

  /// Haftanın pazartesisi (yerel gün başı).
  final DateTime weekStart;
  final int mood;
  final String? note;

  factory WeeklyCheckin.fromMap(Map<String, dynamic> map) {
    final d = DateTime.parse(map['week_start'] as String);
    final note = (map['note'] as String?)?.trim();
    return WeeklyCheckin(
      weekStart: DateTime(d.year, d.month, d.day),
      mood: (map['mood'] as num).toInt(),
      note: note == null || note.isEmpty ? null : note,
    );
  }
}

/// Notun en uzun hali (veritabanı kısıtıyla aynı).
const int weeklyCheckinNoteMax = 500;

/// Pazar bu saatten itibaren "akşam" sayılır.
const int weeklyCheckinSundayHour = 17;

/// 1–5 ruh hali etiketleri.
const List<String> weeklyCheckinMoodLabels = [
  'Çok kötü',
  'Kötü',
  'İdare eder',
  'İyi',
  'Harika',
];

/// Check-in kartı gösterilecekse ilgili haftanın pazartesisi, değilse `null`:
/// Pazar akşamı bu hafta, Pazartesi (gün boyu) geçen hafta sorulur.
DateTime? checkinWeekFor(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (now.weekday == DateTime.sunday && now.hour >= weeklyCheckinSundayHour) {
    return DateTime(today.year, today.month, today.day - 6);
  }
  if (now.weekday == DateTime.monday) {
    return DateTime(today.year, today.month, today.day - 7);
  }
  return null;
}

/// Mood geçerli mi (1–5).
bool isValidCheckinMood(int mood) => mood >= 1 && mood <= 5;
