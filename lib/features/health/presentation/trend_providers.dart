import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/goal_rules.dart';
import '../domain/trend_stats.dart';
import 'health_providers.dart';

export '../domain/goal_rules.dart' show TrendMetric;
export '../domain/trend_stats.dart';

/// Trend ekranının iki dönemi.
enum TrendPeriod { week, month }

/// Trend sorgusu: hangi metrik, hangi dönem ve dönemin hangi günü.
///
/// Dönem [anchor]'u içeren Pazartesi–Pazar haftası ya da takvim ayıdır.
/// Eşitlik değerle yapılır; [anchor]'un saat bileşeni yok sayılır.
@immutable
class TrendQuery {
  const TrendQuery({
    required this.metric,
    required this.period,
    required this.anchor,
  });

  final TrendMetric metric;
  final TrendPeriod period;
  final DateTime anchor;

  DateTime get _anchorDay => AppDates.startOfDay(anchor);

  /// Dönemin günleri, sırayla: hafta Pazartesi–Pazar (7), ay 1'inden son
  /// gününe (28/29/30/31).
  List<DateTime> get days {
    final day = _anchorDay;
    switch (period) {
      case TrendPeriod.week:
        final monday = AppDates.weekStart(day);
        return [for (var i = 0; i < 7; i++) AppDates.addDays(monday, i)];
      case TrendPeriod.month:
        // DateTime(y, m + 1, 0) önceki ayın son günüdür: ayın gün sayısı.
        final length = DateTime(day.year, day.month + 1, 0).day;
        return [
          for (var i = 1; i <= length; i++) DateTime(day.year, day.month, i),
        ];
    }
  }

  /// Dönemin ilk günü.
  DateTime get from => days.first;

  /// Dönemin son günü (dahil).
  DateTime get to => days.last;

  /// [today] bu dönemin içinde mi (yani dönem geçerli dönem mi).
  bool isCurrent(DateTime today) {
    final d = AppDates.startOfDay(today);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  /// [delta] dönem önceki (negatif) ya da sonraki (pozitif) sorgu.
  TrendQuery shifted(int delta) {
    final day = _anchorDay;
    final moved = switch (period) {
      TrendPeriod.week => AppDates.addDays(day, 7 * delta),
      TrendPeriod.month => DateTime(day.year, day.month + delta, 1),
    };
    return TrendQuery(metric: metric, period: period, anchor: moved);
  }

  TrendQuery copyWith({
    TrendMetric? metric,
    TrendPeriod? period,
    DateTime? anchor,
  }) =>
      TrendQuery(
        metric: metric ?? this.metric,
        period: period ?? this.period,
        anchor: anchor ?? this.anchor,
      );

  @override
  bool operator ==(Object other) =>
      other is TrendQuery &&
      other.metric == metric &&
      other.period == period &&
      other._anchorDay == _anchorDay;

  @override
  int get hashCode => Object.hash(metric, period, _anchorDay);

  @override
  String toString() =>
      'TrendQuery(${metric.name}, ${period.name}, $_anchorDay)';
}

/// Trend ve haftalık kartların "bugün"ü. Testlerde sabitlenebilsin diye
/// sağlayıcıdır; üretimde cihaz saatidir.
final trendClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Metrik için günlük hedef: adım sayısı, uyku dakikası ya da kalori.
int trendTarget(TrendMetric metric, UserSettings settings) => switch (metric) {
      TrendMetric.steps => settings.dailySteps,
      TrendMetric.sleep => settings.sleepMinutes,
      TrendMetric.calories => settings.dailyCalories,
    };

/// Ayarlar yüklenemezse varsayılan hedeflerle devam edilir (ekran boş kalmaz).
Future<UserSettings> _targets(Ref ref) async {
  try {
    return await ref.watch(userSettingsProvider.future);
  } catch (_) {
    return const UserSettings.defaults();
  }
}

typedef _Window = ({DateTime from, DateTime to});

// Adım/uyku ve öğün okumaları pencereye göre ayrı sağlayıcıdadır: kalori
// ile protein özeti aynı sorguyu paylaşır, sunucuya tek istek gider.
final _metricsWindowProvider =
    FutureProvider.family<List<DailyHealthMetric>, _Window>(
  (ref, window) => ref
      .watch(healthRepositoryProvider)
      .fetchDailyMetrics(window.from, window.to),
);

final _nutritionWindowProvider =
    FutureProvider.family<List<DailyNutritionTotal>, _Window>(
  (ref, window) => ref
      .watch(healthRepositoryProvider)
      .fetchNutritionTotals(window.from, AppDates.endOfDay(window.to)),
);

/// Dönem sonuçlarının önbelleğini boşaltır. Trend ekranı açılırken, geri
/// plandan dönünce ve "Tekrar dene"de çağrılır; kapsayıcı alır, çünkü
/// `await` sonrası `WidgetRef` kullanılamaz.
void invalidateTrendData(ProviderContainer container) {
  container
    ..invalidate(trendStatsProvider)
    ..invalidate(trendProteinStatsProvider)
    ..invalidate(_metricsWindowProvider)
    ..invalidate(_nutritionWindowProvider);
}

/// Bir dönemin hedef tutturma özeti. Veri olmayan gün (adım/uyku değeri 0,
/// öğün kaydı yok) paydada yer almaz; bugün "devam ediyor" sayılır
/// ([TrendStats.build]).
final trendStatsProvider =
    FutureProvider.family<TrendStats, TrendQuery>((ref, query) async {
  final settings = await _targets(ref);
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  final window = (from: query.from, to: query.to);

  final values = <DateTime, double>{};
  switch (query.metric) {
    case TrendMetric.steps:
      final rows = await ref.watch(_metricsWindowProvider(window).future);
      for (final m in rows) {
        if (m.steps > 0) {
          values[AppDates.startOfDay(m.day)] = m.steps.toDouble();
        }
      }
    case TrendMetric.sleep:
      final rows = await ref.watch(_metricsWindowProvider(window).future);
      for (final m in rows) {
        if (m.sleepMinutes > 0) {
          values[AppDates.startOfDay(m.day)] = m.sleepMinutes.toDouble();
        }
      }
    case TrendMetric.calories:
      final rows = await ref.watch(_nutritionWindowProvider(window).future);
      for (final n in rows) {
        if (n.entryCount > 0) values[AppDates.startOfDay(n.day)] = n.calories;
      }
  }

  return TrendStats.build(
    days: query.days,
    values: values,
    hit: switch (query.metric) {
      TrendMetric.steps => (v) =>
          GoalRules.stepsHit(v.round(), settings.dailySteps),
      TrendMetric.sleep => (v) =>
          GoalRules.sleepHit(v.round(), settings.sleepMinutes),
      TrendMetric.calories => (v) =>
          GoalRules.caloriesHit(v, settings.dailyCalories),
    },
    today: today,
    isCurrentPeriod: query.isCurrent(today),
  );
});

/// Kalori sekmesinin ikincil satırı: aynı dönemde protein hedefini tutturan
/// gün sayısı (`hitDays` / `dataDays`). Yalnızca öğünü olan günler sayılır.
final trendProteinStatsProvider =
    FutureProvider.family<TrendStats, TrendQuery>((ref, query) async {
  final settings = await _targets(ref);
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  final window = (from: query.from, to: query.to);

  final values = <DateTime, double>{};
  for (final n in await ref.watch(_nutritionWindowProvider(window).future)) {
    if (n.entryCount > 0) values[AppDates.startOfDay(n.day)] = n.proteinG;
  }

  return TrendStats.build(
    days: query.days,
    values: values,
    hit: (v) => GoalRules.proteinHit(v, settings.dailyProteinG),
    today: today,
    isCurrentPeriod: query.isCurrent(today),
  );
});

/// Sağlık sekmesi Kalori kartı: bugünle biten 7 gün, eskiden yeniye tam 7
/// kalem. Öğünü olmayan günün `entryCount`'u 0'dır.
final weekCaloriesProvider =
    FutureProvider<List<DailyNutritionTotal>>((ref) async {
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  // Öğün eklenip silindiğinde `invalidateHealthData` bugünün öğün listesini
  // tazeler; kart da onunla birlikte yeniden okunsun diye izlenir.
  ref.watch(dayNutritionLogsProvider(today));
  final from = AppDates.addDays(today, -6);
  final rows = await ref
      .watch(healthRepositoryProvider)
      .fetchNutritionTotals(from, AppDates.endOfDay(today));
  final byDay = {for (final n in rows) AppDates.startOfDay(n.day): n};
  return [
    for (var i = 0; i < 7; i++)
      byDay[AppDates.addDays(from, i)] ??
          DailyNutritionTotal(day: AppDates.addDays(from, i)),
  ];
});

/// Verisi olan (öğünü girilmiş) günlerin kalori ortalaması; hiç veri yoksa
/// `null`.
double? averageCalories(Iterable<DailyNutritionTotal> days) {
  final logged = days.where((d) => d.entryCount > 0).toList();
  if (logged.isEmpty) return null;
  return logged.fold<double>(0, (sum, d) => sum + d.calories) / logged.length;
}

/// Verisi olan günlerin uyku ortalaması (dakika); hiç veri yoksa `null`.
int? averageSleepMinutes(Iterable<DailyHealthMetric> days) {
  final withData = days.where((d) => d.sleepMinutes > 0).toList();
  if (withData.isEmpty) return null;
  return (withData.fold<int>(0, (sum, d) => sum + d.sleepMinutes) /
          withData.length)
      .round();
}
