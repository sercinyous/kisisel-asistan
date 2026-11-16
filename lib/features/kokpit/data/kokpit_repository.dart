import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/kokpit_models.dart';

final kokpitRepositoryProvider = Provider<KokpitRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm Kokpit sağlayıcıları yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return KokpitRepository(ref.watch(supabaseClientProvider));
});

/// Kokpit'e özgü okumalar. Rutinler, görevler ve sağlık özeti kendi
/// özelliklerinin depolarındadır.
class KokpitRepository {
  const KokpitRepository(this._client);

  final SupabaseClient _client;

  Future<NutritionSummary> fetchNutritionFor(DateTime day) async {
    final start = AppDates.startOfDay(day).toUtc().toIso8601String();
    final end = AppDates.endOfDay(day).toUtc().toIso8601String();
    final rows = await _client
        .from('nutrition_logs')
        .select('calories, protein_g, carbs_g, fat_g')
        .gte('eaten_at', start)
        .lt('eaten_at', end);
    return NutritionSummary.fromRows(rows);
  }
}
