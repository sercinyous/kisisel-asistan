import 'package:intl/intl.dart';

import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_format.dart';

/// Yapay zekâ yorumunun ekranda gösterilen iki parçası.
typedef SummaryParts = ({String body, List<String> suggestions});

/// Raporlar sekmesinin metin biçimleri.
abstract final class ReportsFormat {
  static const String none = KokpitFormat.none;

  /// Öneri sayılacak satırın en fazla uzunluğu; daha uzunu paragraftır.
  static const int _suggestionMaxLength = 120;
  static const int _maxSuggestions = 3;

  static final RegExp _bullet = RegExp(r'^(?:[-•*–]|\d+[.)])\s+');

  /// "9 – 15 Kasım"; ay değişiyorsa "26 Eki – 1 Kas".
  static String weekRange(DateTime weekStart) {
    final end = AppDates.addDays(weekStart, 6);
    if (weekStart.month == end.month) {
      return '${weekStart.day} – ${KokpitFormat.dayMonth(end)}';
    }
    final short = DateFormat('d MMM', AppDates.locale);
    return '${short.format(weekStart)} – ${short.format(end)}';
  }

  /// "17 Kasım Sal"
  static String dayShort(DateTime day) =>
      DateFormat('d MMMM EEE', AppDates.locale).format(day);

  /// "%78"; değer yoksa "—".
  static String rate(int? value) =>
      value == null ? none : KokpitFormat.percent(value);

  /// "1.960"
  static String count(num value) =>
      KokpitFormat.thousands.format(value.round());

  /// "7 sa 05"; veri yoksa "—".
  static String sleepShort(int minutes) {
    if (minutes <= 0) return none;
    return '${minutes ~/ 60} sa ${(minutes % 60).toString().padLeft(2, '0')}';
  }

  /// Yorumu değerlendirme ve önerilere ayırır. Sunucu düz metin ister:
  /// önce değerlendirme, ardından her biri ayrı satırda en fazla 3 kısa öneri.
  /// Sondaki kısa satırlar öneri sayılır; ilk satır hep değerlendirmedir.
  static SummaryParts splitSummary(
    String text, {
    bool withSuggestions = true,
  }) {
    final lines = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim().replaceFirst(_bullet, ''),
    ];
    var split = lines.length;
    if (withSuggestions) {
      while (split > 1 &&
          lines.length - split < _maxSuggestions &&
          lines[split - 1].length <= _suggestionMaxLength) {
        split--;
      }
    }
    return (
      body: lines.take(split).join('\n\n'),
      suggestions: lines.skip(split).toList(),
    );
  }
}
