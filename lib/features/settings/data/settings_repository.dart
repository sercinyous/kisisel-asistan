import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/user_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  // Oturum (kullanıcı) değişince ayarlar yeni kullanıcı için yeniden okunur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

class SettingsRepository {
  const SettingsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  /// Kullanıcının ayar satırı; yoksa varsayılanlarla oluşturulur.
  Future<UserSettings> fetch() async {
    final userId = _userId;
    final existing = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) return UserSettings.fromMap(existing);

    // Yalnızca kullanıcı kimliği yazılır: sütun varsayılanlarını (nötr
    // hedefler, boş `onboarded_at`) veritabanı verir; yeni hesap kılavuza düşer.
    // ignoreDuplicates: aynı anda başka bir okuma satırı açtıysa onunki kalır.
    await _client.from('user_settings').upsert(
      {'user_id': userId},
      onConflict: 'user_id',
      ignoreDuplicates: true,
    );
    final created = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .single();
    return UserSettings.fromMap(created);
  }

  Future<UserSettings> save(UserSettings settings) async {
    final row = await _client
        .from('user_settings')
        .upsert(
          {'user_id': _userId, ...settings.toMap()},
          onConflict: 'user_id',
        )
        .select()
        .single();
    return UserSettings.fromMap(row);
  }
}
