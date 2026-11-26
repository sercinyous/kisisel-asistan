import 'package:intl/intl.dart';

/// Uygulama genelinde kullanılan tarih yardımcıları (cihazın yerel saati).
abstract final class AppDates {
  static const String locale = 'tr_TR';

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  /// [d]'nin haftasının Pazartesi'si (yerel gece yarısı).
  static DateTime weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  /// [d]'den [days] takvim günü sonrası (yaz saati geçişinden etkilenmez).
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// Postgres `date` sütunları için `yyyy-MM-dd`.
  static String ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String longDay(DateTime d) =>
      DateFormat('d MMMM EEEE', locale).format(d);

  /// Türkçe kurallarıyla büyük harf (i → İ, ı → I).
  static String upperTr(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static String hourMinute(DateTime d) => DateFormat('HH:mm', locale).format(d);

  /// "Bugün 15:00", "Yarın 09:30", "18 Kas Çar 14:00"
  static String relativeDayTime(DateTime target, {DateTime? now}) {
    final local = target.toLocal();
    final today = startOfDay(now ?? DateTime.now());
    final diff = startOfDay(local).difference(today).inDays;
    final time = hourMinute(local);
    if (diff == 0) return 'Bugün $time';
    if (diff == 1) return 'Yarın $time';
    if (diff == -1) return 'Dün $time';
    return '${DateFormat('d MMM EEE', locale).format(local)} $time';
  }

  /// Sınırlar Kokpit'in gün evresiyle (Sabah/Öğle/Akşam/Gece) aynıdır;
  /// başlık ile evre çipi çelişmez.
  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5 || h >= 22) return 'İyi geceler';
    if (h < 12) return 'Günaydın';
    if (h < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }
}
