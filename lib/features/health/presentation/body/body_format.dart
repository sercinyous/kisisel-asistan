import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/body_models.dart';
import '../../domain/health_models.dart';

/// Vücut bölümünün ortak metin biçimleri.
abstract final class BodyFormat {
  static final NumberFormat _cm = NumberFormat('0.#', 'tr_TR');

  /// "88" / "87,5"
  static String cm(double value) => _cm.format(value);

  /// "−4" / "+0,5" / "0" (tipografik eksi).
  static String delta(double value) {
    if (value == 0) return '0';
    return '${value < 0 ? '−' : '+'}${_cm.format(value.abs())}';
  }

  /// "3 Kas"
  static String shortDate(DateTime d) =>
      DateFormat('d MMM', AppDates.locale).format(d);

  /// "3 Kasım 2026"
  static String longDate(DateTime d) =>
      DateFormat('d MMMM y', AppDates.locale).format(d);

  /// "Bel 88 cm · −4 başlangıçtan · −0,5 geçen"
  static String summaryLine(BodyFieldSummary s) => [
        '${s.field.label} ${cm(s.last)} cm',
        if (s.fromStart != null) '${delta(s.fromStart!)} başlangıçtan',
        if (s.fromPrevious != null) '${delta(s.fromPrevious!)} geçen',
      ].join(' · ');
}

/// Farkın hedef yönüne göre rengi: bel/kalçada azalma başarı, artış uyarı;
/// diğer alanlarda nötr.
Color bodyDeltaColor(BodyField field, double? delta) {
  if (delta == null || delta == 0 || !field.lowerIsBetter) {
    return AppColors.textSecondary;
  }
  return delta < 0 ? AppColors.accent : AppColors.warning;
}

/// [day]'e en yakın kilo ölçümü (±[maxDays] gün); yoksa `null`.
WeightEntry? nearestWeight(
  List<WeightEntry> entries,
  DateTime day, {
  int maxDays = 3,
}) {
  WeightEntry? best;
  var bestDiff = Duration(days: maxDays + 1);
  final noon = DateTime(day.year, day.month, day.day, 12);
  for (final e in entries) {
    final diff = e.loggedAt.difference(noon).abs();
    if (diff <= Duration(days: maxDays, hours: 12) && diff < bestDiff) {
      best = e;
      bestDiff = diff;
    }
  }
  return best;
}

/// [day]'e en yakın, [field] alanı dolu ölçüm (±[maxDays] gün).
double? nearestMeasurement(
  List<BodyMeasurement> entries,
  DateTime day,
  BodyField field, {
  int maxDays = 3,
}) {
  double? best;
  var bestDiff = maxDays + 1;
  for (final m in entries) {
    final v = m[field];
    if (v == null) continue;
    final diff = m.measuredOn.difference(day).inDays.abs();
    if (diff <= maxDays && diff < bestDiff) {
      best = v;
      bestDiff = diff;
    }
  }
  return best;
}

/// [date]'ten önceki en son ölçüm (aynı günü saymaz).
BodyMeasurement? measurementBefore(
  List<BodyMeasurement> entries,
  DateTime date,
) {
  BodyMeasurement? last;
  for (final m in entries) {
    if (m.measuredOn.isBefore(date) &&
        (last == null || m.measuredOn.isAfter(last.measuredOn))) {
      last = m;
    }
  }
  return last;
}
