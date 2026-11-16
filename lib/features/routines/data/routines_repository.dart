import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/routine.dart';

final routinesRepositoryProvider = Provider<RoutinesRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return RoutinesRepository(ref.watch(supabaseClientProvider));
});

class RoutinesRepository {
  const RoutinesRepository(this._client);

  final SupabaseClient _client;

  /// Aktif rutinler (günlük, haftalık ve aylık birlikte).
  Future<List<Routine>> fetchActive() async {
    final rows = await _client
        .from('routines')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return [for (final row in rows) Routine.fromMap(row)];
  }

  /// Pasifler dahil tüm rutinler (Sabitler yönetim ekranı için).
  Future<List<Routine>> fetchAll() async {
    final rows = await _client
        .from('routines')
        .select()
        .order('sort_order', ascending: true);
    return [for (final row in rows) Routine.fromMap(row)];
  }

  /// Dönem anahtarı [from]..[to] (iki uç dahil, yerel gün) aralığındaki
  /// tamamlanma kayıtları.
  Future<Set<RoutineCompletionKey>> fetchCompletions(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _client
        .from('routine_completions')
        .select('routine_id, completed_on, completed_at')
        .gte('completed_on', AppDates.ymd(from))
        .lte('completed_on', AppDates.ymd(to));
    return {for (final row in rows) RoutineCompletionKey.fromMap(row)};
  }

  /// [periodKey]: haftalık/günlükte o gün, aylıkta ayın 1'i
  /// (bkz. `periodKeyFor`).
  Future<void> setCompleted({
    required String routineId,
    required DateTime periodKey,
    required bool completed,
  }) async {
    final date = AppDates.ymd(periodKey);
    if (completed) {
      await _client.from('routine_completions').upsert(
        {'routine_id': routineId, 'completed_on': date},
        onConflict: 'routine_id,completed_on',
        ignoreDuplicates: true,
      );
    } else {
      await _client
          .from('routine_completions')
          .delete()
          .eq('routine_id', routineId)
          .eq('completed_on', date);
    }
  }

  Future<Routine> create(Routine routine) async {
    final row = await _client
        .from('routines')
        .insert(routine.toInsertMap())
        .select()
        .single();
    return Routine.fromMap(row);
  }

  Future<Routine> update(Routine routine) async {
    final row = await _client
        .from('routines')
        .update(routine.toInsertMap())
        .eq('id', routine.id)
        .select()
        .single();
    return Routine.fromMap(row);
  }

  /// Tamamlanma kayıtları da veritabanında birlikte silinir (cascade).
  Future<void> delete(String id) async {
    await _client.from('routines').delete().eq('id', id);
  }
}
