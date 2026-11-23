import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/water.dart';

export '../domain/water.dart';

final waterRepositoryProvider = Provider<WaterRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return WaterRepository(ref.watch(supabaseClientProvider));
});

/// `water_logs` ve `user_settings.daily_water_ml` (RLS: yalnızca sahibi).
class WaterRepository {
  const WaterRepository(this._client);

  final SupabaseClient _client;

  /// [day] gününün kayıtları, eklenme sırasıyla.
  Future<List<WaterLog>> fetchDay(DateTime day) async {
    final rows = await _client
        .from('water_logs')
        .select('id, logged_on, ml, created_at')
        .eq('logged_on', AppDates.ymd(day))
        .order('created_at', ascending: true);
    return [for (final row in rows) WaterLog.fromMap(row)];
  }

  Future<WaterLog> add(DateTime day, int ml) async {
    final row = await _client
        .from('water_logs')
        .insert({'logged_on': AppDates.ymd(day), 'ml': ml})
        .select('id, logged_on, ml, created_at')
        .single();
    return WaterLog.fromMap(row);
  }

  Future<void> delete(String id) async {
    await _client.from('water_logs').delete().eq('id', id);
  }

  /// Günlük hedef; ayar satırı ya da sütun yoksa [defaultDailyWaterMl].
  Future<int> fetchDailyTarget() async {
    final row = await _client
        .from('user_settings')
        .select('daily_water_ml')
        .maybeSingle();
    final value = row?['daily_water_ml'];
    return value is num && value > 0 ? value.toInt() : defaultDailyWaterMl;
  }

  /// Günlük su hedefini yazar (250–8.000 ml; RLS: yalnızca sahibi).
  Future<void> setDailyTarget(int ml) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Oturum yok');
    await _client
        .from('user_settings')
        .update({'daily_water_ml': ml}).eq('user_id', userId);
  }
}
