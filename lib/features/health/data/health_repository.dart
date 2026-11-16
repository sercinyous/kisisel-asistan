import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/health_service.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/health_models.dart';

export '../domain/health_models.dart';

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return HealthRepository(ref.watch(supabaseClientProvider));
});

class HealthRepository {
  const HealthRepository(this._client);

  final SupabaseClient _client;

  /// [from]..[to] (iki uç dahil, yerel gün) aralığının HealthKit özetleri,
  /// eskiden yeniye.
  Future<List<DailyHealthMetric>> fetchDailyMetrics(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _client
        .from('daily_health_metrics')
        .select('metric_date, steps, active_kcal, sleep_minutes')
        .gte('metric_date', AppDates.ymd(from))
        .lte('metric_date', AppDates.ymd(to))
        .order('metric_date', ascending: true);
    return [for (final row in rows) DailyHealthMetric.fromMap(row)];
  }

  /// `[from, to)` aralığındaki kilo ölçümleri, eskiden yeniye.
  Future<List<WeightEntry>> fetchWeights(DateTime from, DateTime to) async {
    final rows = await _client
        .from('fitness_logs')
        .select('id, weight_kg, logged_at')
        .eq('log_type', 'weight')
        .gte('logged_at', from.toUtc().toIso8601String())
        .lt('logged_at', to.toUtc().toIso8601String())
        .order('logged_at', ascending: true);
    return [for (final row in rows) WeightEntry.fromMap(row)];
  }

  /// `[from, to)` aralığındaki öğünlerin yerel güne göre toplamı. Sunucudaki
  /// görünüm İstanbul gününü kullandığı için toplama cihazda yapılır.
  Future<List<DailyNutritionTotal>> fetchNutritionTotals(
    DateTime from,
    DateTime to,
  ) async {
    // Sunucu tek yanıtta en çok 1000 satır döndürür; yoğun bir ay bunu
    // aşabileceği için sayfa sayfa okunur.
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final page = await _client
          .from('nutrition_logs')
          .select('eaten_at, calories, protein_g, carbs_g, fat_g')
          .gte('eaten_at', from.toUtc().toIso8601String())
          .lt('eaten_at', to.toUtc().toIso8601String())
          .order('eaten_at', ascending: true)
          .order('id', ascending: true)
          .range(rows.length, rows.length + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
    }
    return DailyNutritionTotal.fromLogRows(rows);
  }

  /// HealthKit'ten okunan günlük özeti raporlar için saklar.
  Future<void> upsertHealthMetrics(DateTime day, HealthSnapshot snapshot) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null ||
        snapshot.status != HealthStatus.ok ||
        !snapshot.hasData) {
      return;
    }
    await _client.from('daily_health_metrics').upsert(
      {
        'user_id': userId,
        'metric_date': AppDates.ymd(day),
        'steps': snapshot.steps,
        'active_kcal': snapshot.activeKcal,
        'sleep_minutes': snapshot.sleepMinutes,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,metric_date',
    );
  }
}
