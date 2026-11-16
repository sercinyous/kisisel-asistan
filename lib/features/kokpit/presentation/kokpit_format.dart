import 'dart:ui';

import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../routines/domain/routine.dart';

/// Kokpit ekranlarının ortak metin biçimleri.
abstract final class KokpitFormat {
  static final NumberFormat thousands = NumberFormat.decimalPattern('tr_TR');
  static final NumberFormat _oneDecimal = NumberFormat('0.0', 'tr_TR');

  /// Veri yokken sayı yerine gösterilir.
  static const String none = '—';

  /// "Kasım 2026"
  static String monthTitle(DateTime month) =>
      DateFormat('MMMM y', AppDates.locale).format(month);

  /// "15 Kasım"
  static String dayMonth(DateTime day) =>
      DateFormat('d MMMM', AppDates.locale).format(day);

  /// "Çar"
  static String weekdayShort(DateTime day) =>
      DateFormat('EEE', AppDates.locale).format(day);

  /// "7 sa 30 dk"; veri yoksa "—".
  static String sleep(int? minutes) {
    if (minutes == null || minutes <= 0) return none;
    return '${minutes ~/ 60} sa ${minutes % 60} dk';
  }

  /// "84,5"
  static String kg(double value) => _oneDecimal.format(value);

  /// "−1,2 kg" / "+0,8 kg" / "0,0 kg". Eksi işareti tipografik (U+2212).
  static String weightChange(double change) {
    final rounded = (change * 10).round() / 10;
    final sign = rounded > 0
        ? '+'
        : rounded < 0
            ? '−'
            : '';
    return '$sign${_oneDecimal.format(rounded.abs())} kg';
  }

  /// "%82"
  static String percent(int value) => '%$value';

  /// Ay ekranındaki durum rozeti.
  static String statusLabel(OccurrenceStatus status) => switch (status) {
        OccurrenceStatus.done => 'Yapıldı',
        OccurrenceStatus.upcoming => 'Bekliyor',
        OccurrenceStatus.dueToday => 'Bugün',
        OccurrenceStatus.overdue => 'Gecikti',
        OccurrenceStatus.missed => 'Yapılmadı',
      };

  static Color statusColor(OccurrenceStatus status) => switch (status) {
        OccurrenceStatus.done => AppColors.accent,
        OccurrenceStatus.upcoming => AppColors.textSecondary,
        OccurrenceStatus.dueToday => AppColors.warning,
        OccurrenceStatus.overdue => AppColors.danger,
        OccurrenceStatus.missed => AppColors.textMuted,
      };

  /// Gün ekranındaki aylık iş satırı: "3 gün kaldı" / "Bugün" / "2 gün gecikti".
  static String countdown(RoutineOccurrence occurrence, DateTime today) {
    switch (occurrence.status) {
      case OccurrenceStatus.done:
      case OccurrenceStatus.missed:
        return statusLabel(occurrence.status);
      case OccurrenceStatus.dueToday:
      case OccurrenceStatus.upcoming:
      case OccurrenceStatus.overdue:
        final days = occurrence.daysUntilDue(today);
        if (days > 0) return '$days gün kaldı';
        if (days == 0) return 'Bugün';
        return '${-days} gün gecikti';
    }
  }
}
