import '../../settings/domain/user_settings.dart';

/// "Ölçü ve fotoğraf günü" takvimi. Saf fonksiyonlar; tek sıklık hem mezura
/// hem fotoğraf için geçerlidir.

/// [date] ölçü günü mü? Haftalık: ISO hafta günü (1 = Pazartesi) eşit.
/// Aylık: ayın günü eşit (1..28).
bool isCheckinDay(UserSettings settings, DateTime date) =>
    switch (settings.checkinCadence) {
      CheckinCadence.weekly => date.weekday == settings.checkinWeekday,
      CheckinCadence.monthly => date.day == settings.checkinMonthday,
    };

/// [from] dahil, sonraki ölçü günü (yerel gün).
DateTime nextCheckinDay(UserSettings settings, DateTime from) {
  var d = DateTime(from.year, from.month, from.day);
  for (var i = 0; i < 62; i++) {
    if (isCheckinDay(settings, d)) return d;
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

/// [today]'den sonraki ölçü gününe kalan gün (bugün ölçü günüyse 0).
int daysUntilCheckin(UserSettings settings, DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final next = nextCheckinDay(settings, t);
  return DateTime.utc(next.year, next.month, next.day)
      .difference(DateTime.utc(t.year, t.month, t.day))
      .inDays;
}

/// Kontrol o tarihte yapıldı: ölçü ya da fotoğraf satırı var.
bool isCheckinDone({required bool hasMeasurement, required bool hasPhoto}) =>
    hasMeasurement || hasPhoto;

const List<String> trWeekdayNames = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// "Sonraki ölçü günü: Pazartesi · 3 gün kaldı" / bugünse
/// "Bugün ölçü ve fotoğraf günü".
String checkinScheduleLine(UserSettings settings, DateTime today) {
  final days = daysUntilCheckin(settings, today);
  if (days == 0) return 'Bugün ölçü ve fotoğraf günü';
  final next = nextCheckinDay(settings, today);
  final name = trWeekdayNames[next.weekday - 1];
  final when = days == 1 ? 'yarın' : '$days gün kaldı';
  return 'Sonraki ölçü günü: $name · $when';
}

/// Bildirim metni (ölçü günü 09:00).
const String checkinNotificationBody =
    'Bugün ölçü ve fotoğraf günü. Tartı, mezura, fotoğraf: ~3 dk.';
