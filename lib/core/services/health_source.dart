import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth.dart';
import 'health_service.dart';

/// Sağlık verisi kaynağı tercihini cihazda saklar (Supabase'e yazılmaz).
/// Depo hata verir ya da yanıt vermezse okuma [HealthSourceKind.fallback]
/// (Apple Health) döner, yazma sessizce atlanır.
class HealthSourceStore {
  const HealthSourceStore({this.open = SharedPreferences.getInstance});

  static const String key = 'health_source';

  /// Açılışı kilitlememesi için depoya en fazla bu kadar beklenir.
  static const Duration timeout = Duration(seconds: 2);

  /// Depoyu açar; testlerde hatalı depo denemek için değiştirilebilir.
  final Future<SharedPreferences> Function() open;

  Future<HealthSourceKind> load() async {
    try {
      final prefs = await open().timeout(timeout);
      return HealthSourceKind.parse(prefs.getString(key));
    } catch (_) {
      return HealthSourceKind.fallback;
    }
  }

  Future<void> save(HealthSourceKind kind) async {
    try {
      final prefs = await open().timeout(timeout);
      await prefs.setString(key, kind.name).timeout(timeout);
    } catch (_) {
      // Yazılamazsa tercih yalnızca bu oturumda geçerli kalır.
    }
  }
}

final healthSourceStoreProvider =
    Provider<HealthSourceStore>((ref) => const HealthSourceStore());

/// Açılış tercihi. `main()` içinde [loadInitialHealthSource] sonucuyla ezilir;
/// böylece ilk okuma doğru kaynaktan yapılır (Google seçiliyken HealthKit
/// izin penceresi açılmaz).
final initialHealthSourceProvider =
    Provider<HealthSourceKind>((ref) => HealthSourceKind.fallback);

/// Google ile giriş bu derlemede kullanılabilir mi (istemci kimliği var mı)?
final googleConfiguredProvider =
    Provider<bool>((ref) => ref.watch(googleClientIdProvider).isNotEmpty);

class HealthSourceController extends Notifier<HealthSourceKind> {
  @override
  HealthSourceKind build() {
    final initial = ref.watch(initialHealthSourceProvider);
    // İstemci kimliği olmayan derlemede Google seçilemez; kayıtlı tercih
    // Google olsa da Apple Health'ten okunur.
    if (initial == HealthSourceKind.googleHealth &&
        !ref.watch(googleConfiguredProvider)) {
      return HealthSourceKind.appleHealth;
    }
    return initial;
  }

  /// Etkin kaynak (sağlayıcı dışından, ör. eşitleme sırasında okunur).
  HealthSourceKind get current => state;

  /// Hemen uygulanır, ardından cihaza yazılır. Yapılandırılmamış Google
  /// seçimi yok sayılır. Eşitleme çağıranın işidir (`selectHealthSource`).
  Future<void> select(HealthSourceKind kind) async {
    if (kind == state) return;
    if (kind == HealthSourceKind.googleHealth &&
        !ref.read(googleConfiguredProvider)) {
      return;
    }
    state = kind;
    await ref.read(healthSourceStoreProvider).save(kind);
  }
}

final healthSourceProvider =
    NotifierProvider<HealthSourceController, HealthSourceKind>(
  HealthSourceController.new,
);

/// `runApp` öncesinde çağrılır: saklanan kaynak tercihini okur.
Future<HealthSourceKind> loadInitialHealthSource({
  HealthSourceStore store = const HealthSourceStore(),
}) =>
    store.load();
