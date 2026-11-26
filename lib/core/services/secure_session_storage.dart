import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Oturumun (yenileme jetonu dahil) saklandığı basit anahtar-değer deposu.
/// Gerçeği iOS Anahtar Zinciri; testler bellekte sahtesini verir.
abstract interface class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainKeyValue implements SecureKeyValue {
  const KeychainKeyValue();

  // Yalnızca bu cihazda, ilk kilit açılışından sonra okunur; yedeğe girmez.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Supabase oturumunu NSUserDefaults (SharedPreferences) yerine Anahtar
/// Zinciri'nde saklar. İlk açılışta eski konumdaki oturum taşınır ve
/// eski kayıt silinir; kullanıcı yeniden giriş yapmak zorunda kalmaz.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.persistSessionKey,
    SecureKeyValue? store,
    Future<SharedPreferences> Function()? preferences,
  })  : _store = store ?? const KeychainKeyValue(),
        _preferences = preferences ?? SharedPreferences.getInstance;

  /// supabase_flutter'ın varsayılan anahtarı: `sb-<proje>-auth-token`.
  static String keyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  final String persistSessionKey;
  final SecureKeyValue _store;
  final Future<SharedPreferences> Function() _preferences;
  String? _cached;

  @override
  Future<void> initialize() async {
    _cached = await _store.read(persistSessionKey);
    final prefs = await _preferences();
    final legacy = prefs.getString(persistSessionKey);
    if (legacy == null) return;
    if (_cached == null) {
      await _store.write(persistSessionKey, legacy);
      _cached = legacy;
    }
    await prefs.remove(persistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async => _cached != null;

  @override
  Future<String?> accessToken() async => _cached;

  @override
  Future<void> removePersistedSession() async {
    _cached = null;
    await _store.delete(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _cached = persistSessionString;
    await _store.write(persistSessionKey, persistSessionString);
  }
}
