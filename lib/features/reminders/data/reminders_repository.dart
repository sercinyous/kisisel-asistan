import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/reminder.dart';

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return RemindersRepository(ref.watch(supabaseClientProvider));
});

class RemindersRepository {
  const RemindersRepository(this._client);

  final SupabaseClient _client;

  /// Oturumdaki kullanıcının kimliği ("Yaptım" eyleminin sahip denetimi).
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<Reminder>> fetchAll() async {
    final rows = await _client
        .from('reminders')
        .select()
        .order('created_at', ascending: true);
    return [for (final row in rows) Reminder.fromMap(row)];
  }

  Future<Reminder> create(ReminderDraft draft) async {
    final row =
        await _client.from('reminders').insert(draft.toRow()).select().single();
    return Reminder.fromMap(row);
  }

  Future<void> update(String id, ReminderDraft draft) async {
    await _client.from('reminders').update(draft.toRow()).eq('id', id);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _client.from('reminders').update({'enabled': enabled}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('reminders').delete().eq('id', id);
  }

  /// [from]'dan bu yana "Yaptım" günleri; anahtar hatırlatıcı kimliği.
  Future<Map<String, Set<DateTime>>> fetchDone(DateTime from) async {
    final rows = await _client
        .from('reminder_done')
        .select('reminder_id, done_on')
        .gte('done_on', AppDates.ymd(from));
    final result = <String, Set<DateTime>>{};
    for (final row in rows) {
      final day = DateTime.tryParse(row['done_on'] as String);
      if (day == null) continue;
      result.putIfAbsent(row['reminder_id'] as String, () => {}).add(day);
    }
    return result;
  }

  Future<void> setDone(String reminderId, DateTime day, bool done) async {
    final date = AppDates.ymd(day);
    if (done) {
      await _client.from('reminder_done').upsert(
        {'reminder_id': reminderId, 'done_on': date},
        onConflict: 'reminder_id,done_on',
        ignoreDuplicates: true,
      );
    } else {
      await _client
          .from('reminder_done')
          .delete()
          .eq('reminder_id', reminderId)
          .eq('done_on', date);
    }
  }
}
