import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
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
  ///
  /// Sağlık v2 sütunları (`weekly_rate` …) yoksa şema henüz yükseltilmemiştir:
  /// ayarlar bu sütunları yazmaz ([UserSettings.healthPlanColumns]). Aynı
  /// kural `goal_mode` için de geçerlidir ([UserSettings.goalModeColumns]).
  static UserSettings parseRow(Map<String, dynamic> row) {
    final parsed = row.containsKey('onboarded_at')
        ? UserSettings.fromMap(row)
        : UserSettings.fromMap({
            ...row,
            'onboarded_at':
                row['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
          });
    return parsed.copyWith(
      healthPlanColumns: row.containsKey('weekly_rate'),
      // Hedef türü sütunları (`goal_mode`, `gain_rate`) yoksa yazılmaz.
      goalModeColumns: row.containsKey('goal_mode'),
      // Story paylaşım sütunu yoksa yazılmaz ve paylaşım kapalı sayılır.
      shareStoriesColumn: row.containsKey('share_stories'),
    );
  }

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  /// Ağ hatası mı (bağlantı, istemci, zaman aşımı)? Yalnızca bunlar yinelenir.
  static bool isNetworkError(Object error) =>
      error is SocketException ||
      error is ClientException ||
      error is TimeoutException;

  /// [op]'u çalıştırır; ağ hatasında [delay] sonra bir kez daha dener.
  static Future<T> withNetworkRetry<T>(
    Future<T> Function() op, {
    Duration delay = const Duration(milliseconds: 600),
  }) async {
    try {
      return await op();
    } catch (error) {
      if (!isNetworkError(error)) rethrow;
      await Future<void>.delayed(delay);
      return op();
    }
  }

  /// Kullanıcının ayar satırı; yoksa varsayılanlarla oluşturulur
  /// (`ensure_user_settings`, idempotent). Ağ hatasında bir kez yinelenir.
  Future<UserSettings> fetch() => withNetworkRetry(_fetchOnce);

  Future<UserSettings> _fetchOnce() async {
    final userId = _userId;
    final existing = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) return parseRow(existing);

    // Satırı sunucu açar (yalnızca kimlik; diğer sütunlar varsayılan, boş
    // `onboarded_at` → yeni hesap kılavuza düşer). Varsa dokunmaz.
    final created = await _client.rpc('ensure_user_settings');
    final row = created is List ? created.first : created;
    return parseRow(Map<String, dynamic>.from(row as Map));
  }

  /// AI özelliklerine (Gemini) açık onay verilmiş mi (`ai_consent_at` dolu).
  /// Sütun henüz yoksa (eski şema) onay yok sayılır.
  Future<bool> fetchAiConsent() async {
    final row = await _client
        .from('user_settings')
        .select('ai_consent_at')
        .eq('user_id', _userId)
        .maybeSingle();
    return row?['ai_consent_at'] != null;
  }

  /// AI onayını verir (şimdiki zaman) ya da geri alır (boş). Sunucudaki rapor
  /// üreticisi onay yoksa Gemini'yi çağırmaz.
  Future<void> setAiConsent(bool granted) async {
    await _client.from('user_settings').update({
      'ai_consent_at':
          granted ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('user_id', _userId);
  }

  /// Sunucudaki saat dilimini cihazınkine eşitler (raporlar ve arkadaş
  /// sıralamasındaki "bugün" bu dilime göre hesaplanır). Değiştiyse `true`.
  Future<bool> syncTimezone(String timezone) async {
    final rows = await _client
        .from('user_settings')
        .update({'timezone': timezone})
        .eq('user_id', _userId)
        .neq('timezone', timezone)
        .select('user_id');
    return rows.isNotEmpty;
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
