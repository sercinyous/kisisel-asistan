import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/supabase_providers.dart';

final onboardingOpKeyStoreProvider = Provider<OnboardingOpKeyStore>((ref) {
  final userId =
      ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return OnboardingOpKeyStore(scope: userId ?? 'anon');
});

/// İlk kurulumun işlem anahtarını başarıya dek cihazda saklar: uygulama
/// kapanıp açılınca yeniden deneme aynı anahtarı kullanır, sunucu ikinci kez
/// yazmaz. Depo açılamazsa anahtar bu nesnenin belleğinde kalır.
class OnboardingOpKeyStore {
  OnboardingOpKeyStore({
    required this.scope,
    this.open = SharedPreferences.getInstance,
    String Function()? newKey,
  }) : _newKey = newKey ?? randomUuidV4;

  /// Kullanıcı kimliği: hesap değişince başka kullanıcının anahtarı kullanılmaz.
  final String scope;
  final Future<SharedPreferences> Function() open;
  final String Function() _newKey;
  String? _memory;

  static const Duration timeout = Duration(seconds: 2);

  String get _prefKey => 'onboarding_op_key:$scope';

  /// Saklı anahtarı döndürür; yoksa yenisini üretip ÖNCE saklar.
  Future<String> obtain() async {
    final cached = _memory;
    if (cached != null) return cached;
    SharedPreferences? prefs;
    try {
      prefs = await open().timeout(timeout);
      final stored = prefs.getString(_prefKey);
      if (stored != null && stored.isNotEmpty) return _memory = stored;
    } catch (_) {
      prefs = null;
    }
    final key = _memory = _newKey();
    if (prefs != null) {
      try {
        await prefs.setString(_prefKey, key).timeout(timeout);
      } catch (_) {
        // Yazılamazsa anahtar bu oturumda bellekte geçerli kalır.
      }
    }
    return key;
  }

  /// Kurulum sunucuda tamamlandı: anahtar silinir.
  Future<void> clear() async {
    _memory = null;
    try {
      final prefs = await open().timeout(timeout);
      await prefs.remove(_prefKey).timeout(timeout);
    } catch (_) {
      // Kalan anahtar zararsızdır: aynı anahtarla tekrar çağrı yazmaz.
    }
  }
}

/// RFC 4122 sürüm 4 UUID (güvenli rastgele).
String randomUuidV4() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
