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

  static const _nutritionColumns =
      'id, meal_type, food_name, quantity_text, calories, protein_g, carbs_g, '
      'fat_g, eaten_at, source';
  static const _workoutColumns =
      'id, workout_type, title, duration_min, distance_km, calories_burned, '
      'notes, logged_at, source';

  /// [from]..[to] (iki uç dahil, yerel gün) aralığının sağlık özetleri,
  /// eskiden yeniye.
  /// [source] verildiyse yalnızca o kaynağın satırları döner: kaynak
  /// değişince eski kaynağın sayıları yeni kaynağınmış gibi gösterilmez.
  Future<List<DailyHealthMetric>> fetchDailyMetrics(
    DateTime from,
    DateTime to, {
    HealthSourceKind? source,
  }) async {
    var query = _client
        .from('daily_health_metrics')
        .select('metric_date, steps, active_kcal, sleep_minutes')
        .gte('metric_date', AppDates.ymd(from))
        .lte('metric_date', AppDates.ymd(to));
    if (source != null) query = query.or(sourceFilter(source));
    final rows = await query.order('metric_date', ascending: true);
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

  /// [day] yerel gününün öğün kayıtları, saat sırasıyla.
  Future<List<NutritionLog>> fetchNutritionLogs(DateTime day) async {
    final rows = await _client
        .from('nutrition_logs')
        .select(_nutritionColumns)
        .gte('eaten_at', AppDates.startOfDay(day).toUtc().toIso8601String())
        .lt('eaten_at', AppDates.endOfDay(day).toUtc().toIso8601String())
        .order('eaten_at', ascending: true)
        .order('id', ascending: true);
    return [for (final row in rows) NutritionLog.fromMap(row)];
  }

  /// Yeni öğün kaydı; [log]'un `id`'si yok sayılır.
  Future<NutritionLog> createNutritionLog(NutritionLog log) async {
    final row = await _client
        .from('nutrition_logs')
        .insert({...log.toWriteMap(), 'source': 'manual'})
        .select(_nutritionColumns)
        .single();
    return NutritionLog.fromMap(row);
  }

  Future<NutritionLog> updateNutritionLog(NutritionLog log) async {
    final row = await _client
        .from('nutrition_logs')
        .update(log.toWriteMap())
        .eq('id', log.id)
        .select(_nutritionColumns)
        .single();
    return NutritionLog.fromMap(row);
  }

  Future<void> deleteNutritionLog(String id) async {
    await _client.from('nutrition_logs').delete().eq('id', id);
  }

  /// `[from, to)` aralığındaki antrenmanlar, yeniden eskiye.
  Future<List<WorkoutLog>> fetchWorkouts(DateTime from, DateTime to) async {
    final rows = await _client
        .from('fitness_logs')
        .select(_workoutColumns)
        .eq('log_type', 'workout')
        .gte('logged_at', from.toUtc().toIso8601String())
        .lt('logged_at', to.toUtc().toIso8601String())
        .order('logged_at', ascending: false)
        .order('id', ascending: true);
    return [for (final row in rows) WorkoutLog.fromMap(row)];
  }

  /// Yeni antrenman kaydı; [workout]'un `id`'si yok sayılır. Aynı oturum
  /// Google'dan daha önce aktarılmışsa o kopya silinir: kullanıcının kendi
  /// kaydı kalır, rapor ve haftalık plan oturumu iki kez saymaz.
  Future<WorkoutLog> createWorkout(WorkoutLog workout) async {
    final row = await _client
        .from('fitness_logs')
        .insert({...workout.toWriteMap(), 'source': 'manual'})
        .select(_workoutColumns)
        .single();
    final created = WorkoutLog.fromMap(row);
    await _removeGoogleDuplicatesOf(created);
    return created;
  }

  /// [workout] ile aynı oturum olan Google satırlarını siler. Kayıt zaten
  /// yazılmıştır; temizlik başarısız olursa kullanıcıya hata gösterilmez
  /// (yeniden deneyince ikinci kayıt oluşurdu), bir sonraki Google eşitlemesi
  /// aynı ayıklamayı yapar.
  Future<void> _removeGoogleDuplicatesOf(WorkoutLog workout) async {
    try {
      // Google oturumu en çok 600 dk sürer; başlangıcı kaydın başından o kadar
      // (artı boşluk payı) önce olabilir.
      final from = workout.loggedAt.subtract(
        const Duration(minutes: WorkoutLog.durationMinMax) +
            WorkoutLog.sameSessionTolerance,
      );
      final to = workout.endsAt.add(
        WorkoutLog.sameSessionTolerance + const Duration(minutes: 1),
      );
      for (final candidate in await fetchWorkouts(from, to)) {
        if (candidate.isFromGoogle && candidate.isSameSessionAs(workout)) {
          await deleteWorkout(candidate.id);
        }
      }
    } catch (_) {
      // Bir sonraki eşitlemede yeniden denenir.
    }
  }

  Future<WorkoutLog> updateWorkout(WorkoutLog workout) async {
    final row = await _client
        .from('fitness_logs')
        .update(workout.toWriteMap())
        .eq('id', workout.id)
        // Aynı tabloda kilo satırları da var; yanlış id onları bozmasın.
        .eq('log_type', 'workout')
        .select(_workoutColumns)
        .single();
    return WorkoutLog.fromMap(row);
  }

  Future<void> deleteWorkout(String id) async {
    await _client
        .from('fitness_logs')
        .delete()
        .eq('id', id)
        .eq('log_type', 'workout');
  }

  /// Yeni kilo ölçümü; [at] verilmezse şimdi.
  Future<WeightEntry> addWeight(double weightKg, {DateTime? at}) async {
    final row = await _client
        .from('fitness_logs')
        .insert({
          'log_type': 'weight',
          'weight_kg': weightKg,
          'logged_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
          'source': 'manual',
        })
        .select('id, weight_kg, logged_at')
        .single();
    return WeightEntry.fromMap(row);
  }

  Future<void> deleteWeight(String id) async {
    await _client
        .from('fitness_logs')
        .delete()
        .eq('id', id)
        .eq('log_type', 'weight');
  }

  /// Şu an oturum açmış kullanıcı. Sağlık yazmaları işlem başında bunu
  /// sabitler ([HealthWriteGuard]) ve yazarken `ownerId` olarak verir.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Yazmanın sahibi: [ownerId] verildiyse oturum hâlâ o kullanıcıya ait
  /// olmalıdır (aksi halde `null`, yazma yapılmaz); verilmediyse o anki
  /// kullanıcı.
  String? _owner(String? ownerId) {
    final current = currentUserId;
    if (current == null) return null;
    if (ownerId != null && ownerId != current) return null;
    return current;
  }

  /// Dış kaynaktan (Google Health) gelen antrenmanları yazar. Aynı kaynak
  /// kimliği daha önce yazıldıysa satıra dokunulmaz (ON CONFLICT DO NOTHING):
  /// yeniden eşitleme kopya üretmez, kullanıcının sonradan yaptığı düzenleme
  /// de ezilmez. [ownerId] verildiyse oturum başka kullanıcıya geçmişse
  /// hiçbir şey yazılmaz.
  Future<void> importExternalWorkouts(
    List<ExternalWorkout> workouts, {
    String? ownerId,
  }) async {
    final userId = _owner(ownerId);
    if (userId == null || workouts.isEmpty) return;
    await _client.from('fitness_logs').upsert(
      [for (final w in workouts) w.toInsertMap(userId)],
      onConflict: 'user_id,source,external_id',
      ignoreDuplicates: true,
    );
  }

  /// Bugünün okumasını raporlar için saklar ([snapshot.source] ile).
  ///
  /// - Verisi olan okuma o günün satırının yerine geçer (kaynak da güncellenir).
  /// - Tamamı sıfır olan başarılı okuma yalnızca aynı kaynağın o güne ait
  ///   satırını sıfırlar (gerçek düzeltme). Satır yoksa ya da başka kaynağa
  ///   aitse yazılmaz: HealthKit okuma izninin reddini bildirmez, sıfır
  ///   "izin yok" da olabilir; yeni satır açılmaz, başka kaynağın değeri de
  ///   bu kaynağın sıfırıyla ezilmez.
  /// [ownerId] verildiyse oturum başka kullanıcıya geçmişse yazılmaz.
  Future<void> upsertHealthMetrics(
    DateTime day,
    HealthSnapshot snapshot, {
    String? ownerId,
  }) async {
    final userId = _owner(ownerId);
    if (userId == null || snapshot.status != HealthStatus.ok) return;
    final syncedAt = DateTime.now().toUtc().toIso8601String();
    if (snapshot.hasData) {
      await _client.from('daily_health_metrics').upsert(
            _metricRow(userId, day, snapshot, syncedAt),
            onConflict: 'user_id,metric_date',
          );
      return;
    }
    await _zeroSameSource(userId, day, snapshot.source, syncedAt);
  }

  /// Tamamlanmış günlerin gün sonu değerlerini yazar
  /// ([HealthService.readPastDays]). Verisi olan günler tek istekte yazılır.
  /// Sıfır gün: Google Health'te (izin belirsizliği yok) aynı kaynağın kayıtlı
  /// satırı sıfırlanır; HealthKit'te atlanır (izin geri alınmışsa kayıtlı
  /// geçmişin üstüne sıfır yazılmaz).
  Future<void> upsertHealthDays(
    List<HealthDayReading> days, {
    String? ownerId,
  }) async {
    final userId = _owner(ownerId);
    if (userId == null) return;
    final syncedAt = DateTime.now().toUtc().toIso8601String();
    final rows = [
      for (final (:day, :snapshot) in days)
        if (snapshot.status == HealthStatus.ok && snapshot.hasData)
          _metricRow(userId, day, snapshot, syncedAt),
    ];
    if (rows.isNotEmpty) {
      await _client
          .from('daily_health_metrics')
          .upsert(rows, onConflict: 'user_id,metric_date');
    }
    for (final (:day, :snapshot) in days) {
      if (snapshot.status == HealthStatus.ok &&
          !snapshot.hasData &&
          snapshot.source == HealthSourceKind.googleHealth) {
        if (_owner(userId) == null) return;
        await _zeroSameSource(userId, day, snapshot.source, syncedAt);
      }
    }
  }

  Map<String, dynamic> _metricRow(
    String userId,
    DateTime day,
    HealthSnapshot snapshot,
    String syncedAt,
  ) =>
      {
        'user_id': userId,
        'metric_date': AppDates.ymd(day),
        'steps': snapshot.steps,
        'active_kcal': snapshot.activeKcal,
        'sleep_minutes': snapshot.sleepMinutes,
        'source': snapshot.source.name,
        'synced_at': syncedAt,
      };

  /// Yalnızca [source]'a ait (Apple Health için kaynağı bilinmeyen eski
  /// satırlar da) mevcut satırı sıfırlar; satır yoksa bir şey eklemez.
  Future<void> _zeroSameSource(
    String userId,
    DateTime day,
    HealthSourceKind source,
    String syncedAt,
  ) async {
    await _client
        .from('daily_health_metrics')
        .update({
          'steps': 0,
          'active_kcal': 0,
          'sleep_minutes': 0,
          'source': source.name,
          'synced_at': syncedAt,
        })
        .eq('user_id', userId)
        .eq('metric_date', AppDates.ymd(day))
        .or(sourceFilter(source));
  }

  /// [source]'a ait satırların PostgREST `or` filtresi. Kaynak sütunu
  /// eklenmeden önce yazılan satırlar (`source` boş) yalnızca HealthKit
  /// döneminden kalmıştır; Apple Health'e sayılır.
  static String sourceFilter(HealthSourceKind source) =>
      source == HealthSourceKind.appleHealth
          ? 'source.eq.${source.name},source.is.null'
          : 'source.eq.${source.name}';
}
