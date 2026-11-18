import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/weekly_checkin.dart';

export '../domain/weekly_checkin.dart';

final weeklyCheckinRepositoryProvider =
    Provider<WeeklyCheckinRepository>((ref) {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return WeeklyCheckinRepository(ref.watch(supabaseClientProvider));
});

/// `weekly_checkins` (RLS: yalnızca sahibi; kullanıcı + hafta tekil).
class WeeklyCheckinRepository {
  const WeeklyCheckinRepository(this._client);

  final SupabaseClient _client;

  Future<WeeklyCheckin?> fetch(DateTime weekStart) async {
    final row = await _client
        .from('weekly_checkins')
        .select('week_start, mood, note')
        .eq('week_start', AppDates.ymd(weekStart))
        .maybeSingle();
    return row == null ? null : WeeklyCheckin.fromMap(row);
  }

  Future<WeeklyCheckin> save(WeeklyCheckin checkin) async {
    final note = checkin.note?.trim();
    final row = await _client
        .from('weekly_checkins')
        .upsert(
          {
            'week_start': AppDates.ymd(checkin.weekStart),
            'mood': checkin.mood,
            'note': note == null || note.isEmpty ? null : note,
          },
          onConflict: 'user_id,week_start',
        )
        .select('week_start, mood, note')
        .single();
    return WeeklyCheckin.fromMap(row);
  }
}
