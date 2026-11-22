import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/avatar/avatar_spec.dart';
import '../domain/user_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  // Oturum (kullanıcı) değişince ayarlar yeni kullanıcı için yeniden okunur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

class SettingsRepository {
  const SettingsRepository(this._client);

  final SupabaseClient _client;

  /// Veritabanı satırını ayarlara çevirir. Faz 4B öncesi şemada `onboarded_at`
  /// sütunu hiç yoktur (anahtar satırda bulunmaz; sütun var ama boşsa anahtar
  /// `null` ile gelir): mevcut hesap, SQL güncellemesi çalışana kadar kılavuza
  /// zorlanmasın diye kurulumu bitmiş sayılır.
  static UserSettings parseRow(Map<String, dynamic> row) {
    if (row.containsKey('onboarded_at')) return UserSettings.fromMap(row);
    return UserSettings.fromMap({
      ...row,
      'onboarded_at':
          row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
    });
  }

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
    if (existing != null) return parseRow(existing);

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
    return parseRow(created);
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
    return parseRow(row);
  }

  /// Yalnızca avatar sütunlarını yazar; diğer ayarlara dokunmaz.
  Future<UserSettings> saveAvatar(AvatarChoice avatar) async {
    final row = await _client
        .from('user_settings')
        .update(avatar.toMap())
        .eq('user_id', _userId)
        .select()
        .single();
    return parseRow(row);
  }
}
