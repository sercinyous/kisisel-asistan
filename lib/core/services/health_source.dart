import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth.dart';
import 'health_service.dart';
import 'supabase_providers.dart';

/// Sağlık okuma/yazmalarının sahibi olan Supabase kullanıcısı. Oturum akışı
/// henüz ilk değerini vermediyse istemcideki mevcut kullanıcı; Supabase
/// başlatılmamışsa (testler) `null`.
final healthOwnerIdProvider = Provider<String?>((ref) {
  try {
    final session = ref.watch(authSessionProvider);
    if (session.hasValue) return session.value?.user.id;
    return ref.watch(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

/// Sağlık verisi kaynağı tercihini cihazda, Supabase kullanıcısına göre ayrı
/// anahtarda (`health_source:<kullanıcı>`) saklar; bir hesabın seçimi aynı
/// cihazdaki başka hesaba geçmez. Kullanıcısız anahtar (`health_source`)
/// yalnızca oturumsuz durumun ve testlerin yeridir. Depo hata verir ya da
/// yanıt vermezse okuma [HealthSourceKind.fallback] (Apple Health) döner,
/// yazma sessizce atlanır.
class HealthSourceStore {
  const HealthSourceStore({this.open = SharedPreferences.getInstance});

  static const String key = 'health_source';

  /// Açılışı kilitlememesi için depoya en fazla bu kadar beklenir.
  static const Duration timeout = Duration(seconds: 2);

  /// Depoyu açar; testlerde hatalı depo denemek için değiştirilebilir.
  final Future<SharedPreferences> Function() open;

  /// [userId] kullanıcısına ait anahtar.
  static String keyFor(String? userId) => userId == null ? key : '$key:$userId';

  Future<HealthSourceKind> load({String? userId}) async {
    try {
      final prefs = await open().timeout(timeout);
      return HealthSourceKind.parse(prefs.getString(keyFor(userId)));
    } catch (_) {
      return HealthSourceKind.fallback;
    }
  }

  Future<void> save(HealthSourceKind kind, {String? userId}) async {
    try {
      final prefs = await open().timeout(timeout);
      await prefs.setString(keyFor(userId), kind.name).timeout(timeout);
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

/// [initialHealthSourceProvider] değerinin ait olduğu kullanıcı (açılıştaki
/// oturum). Oturumdaki kullanıcı bundan farklıysa onun kendi tercihi okunur.
final initialHealthSourceOwnerProvider = Provider<String?>((ref) => null);

/// Google ile giriş bu derlemede kullanılabilir mi (istemci kimliği var mı)?
final googleConfiguredProvider =
    Provider<bool>((ref) => ref.watch(googleClientIdProvider).isNotEmpty);

class HealthSourceController extends Notifier<HealthSourceKind> {
  String? _ownerId;
  int _generation = 0;

  @override
  HealthSourceKind build() {
    final generation = ++_generation;
    final owner = ref.watch(healthOwnerIdProvider);
    _ownerId = owner;
    if (owner != ref.watch(initialHealthSourceOwnerProvider)) {
      // Açılış tercihi başka kullanıcıya ait: bu kullanıcının kendi tercihi
      // okunana dek Apple Health varsayılır (Apple Health de bu kullanıcının
      // onayı olmadan okunmaz/yazılmaz).
      _loadOwner(owner, generation);
      return HealthSourceKind.fallback;
    }
    return _usable(ref.watch(initialHealthSourceProvider));
  }

  Future<void> _loadOwner(String? owner, int generation) async {
    final kind = await ref.read(healthSourceStoreProvider).load(userId: owner);
    if (generation != _generation) return;
    state = _usable(kind);
  }

  HealthSourceKind _usable(HealthSourceKind initial) {
    // İstemci kimliği olmayan derlemede Google seçilemez; kayıtlı tercih
    // Google olsa da Apple Health'ten okunur.
    if (initial == HealthSourceKind.googleHealth &&
        !ref.read(googleConfiguredProvider)) {
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
    _generation++;
    state = kind;
    await ref.read(healthSourceStoreProvider).save(kind, userId: _ownerId);
  }
}

final healthSourceProvider =
    NotifierProvider<HealthSourceController, HealthSourceKind>(
  HealthSourceController.new,
);

/// `runApp` öncesinde çağrılır: saklanan kaynak tercihini okur.
Future<HealthSourceKind> loadInitialHealthSource({
  HealthSourceStore store = const HealthSourceStore(),
  String? userId,
}) =>
    store.load(userId: userId);

/// Apple Health verisinin bir uygulama kullanıcısının hesabına aktarılması
/// için o kullanıcının uygulama içi onayı. Cihazdaki HealthKit izni cihaza
/// aittir; aynı iPhone'da başka hesapla girilince o hesap kendi onayını
/// vermeden Apple Health okunmaz ve yazılmaz.
abstract interface class AppleHealthConsentStore {
  Future<bool> load(String userId);
  Future<void> save(String userId, {required bool granted});
}

/// Onayı `shared_preferences` içinde `apple_health_consent:<kullanıcı>`
/// anahtarında saklar. Kayıt yoksa ya da depo hata verirse onay yok sayılır
/// (eski kurulumlarda kimse kendiliğinden onaylı sayılmaz; bir dokunuş ister).
class PrefsAppleHealthConsentStore implements AppleHealthConsentStore {
  const PrefsAppleHealthConsentStore({
    this.open = SharedPreferences.getInstance,
  });

  static const String key = 'apple_health_consent';
  static const Duration timeout = Duration(seconds: 2);

  final Future<SharedPreferences> Function() open;

  static String keyFor(String userId) => '$key:$userId';

  @override
  Future<bool> load(String userId) async {
    try {
      final prefs = await open().timeout(timeout);
      return prefs.getBool(keyFor(userId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> save(String userId, {required bool granted}) async {
    try {
      final prefs = await open().timeout(timeout);
      if (granted) {
        await prefs.setBool(keyFor(userId), true).timeout(timeout);
      } else {
        await prefs.remove(keyFor(userId)).timeout(timeout);
      }
    } catch (_) {
      // Yazılamazsa onay yalnızca bu oturumda geçerli kalır.
    }
  }
}

/// Bellekte tutulan onay deposu (demo). [grantAll] doğruysa her kullanıcı
/// onaylı sayılır.
class MemoryAppleHealthConsentStore implements AppleHealthConsentStore {
  MemoryAppleHealthConsentStore({this.grantAll = false, Set<String>? granted})
      : granted = granted ?? <String>{};

  final bool grantAll;
  final Set<String> granted;

  @override
  Future<bool> load(String userId) async =>
      grantAll || granted.contains(userId);

  @override
  Future<void> save(String userId, {required bool granted}) async {
    if (granted) {
      this.granted.add(userId);
    } else {
      this.granted.remove(userId);
    }
  }
}

final appleHealthConsentStoreProvider = Provider<AppleHealthConsentStore>(
  (ref) => const PrefsAppleHealthConsentStore(),
);

/// Kullanıcı başına Apple Health onayı (okunan kullanıcıların önbelleği).
/// Yazma denetimleri eşzamanlı [isGranted] ile yapılır; okunmamış kullanıcı
/// onaysız sayılır.
class AppleHealthConsentController extends Notifier<Map<String, bool>> {
  final Map<String, Future<bool>> _pending = {};

  @override
  Map<String, bool> build() {
    ref.watch(appleHealthConsentStoreProvider);
    _pending.clear();
    return const {};
  }

  AppleHealthConsentStore get _store =>
      ref.read(appleHealthConsentStoreProvider);

  /// [userId] onay verdi mi (önbellekten; okunmadıysa `false`).
  bool isGranted(String? userId) => userId != null && state[userId] == true;

  /// [userId] onayını depodan okur (bir kez) ve döndürür.
  Future<bool> check(String? userId) async {
    if (userId == null) return false;
    final known = state[userId];
    if (known != null) return known;
    final granted = await (_pending[userId] ??= _store.load(userId));
    if (!state.containsKey(userId)) state = {...state, userId: granted};
    return state[userId] ?? false;
  }

  /// Yalnızca kullanıcı dokunuşuyla çağrılır.
  /// Önce depoya yazılır (yazılamazsa onay bu oturumda yine geçerlidir).
  Future<void> grant(String userId) async {
    await _store.save(userId, granted: true);
    state = {...state, userId: true};
  }

  Future<void> revoke(String userId) async {
    await _store.save(userId, granted: false);
    state = {...state, userId: false};
  }
}

final appleHealthConsentProvider =
    NotifierProvider<AppleHealthConsentController, Map<String, bool>>(
  AppleHealthConsentController.new,
);

/// Apple Health onayı istenirken gösterilen metin.
const String appleHealthConsentMessage =
    'Bu iPhone\'daki Apple Sağlık verileri bu hesaba henüz aktarılmıyor. '
    'Adım, uyku ve aktif kalorinin bu hesaba yazılması için onay ver.';

/// HealthKit okumasını uygulama kullanıcısının onayına bağlar: onay yoksa
/// HealthKit'e hiç gidilmez, bugün [HealthStatus.notConnected] döner ve geçmiş
/// günler boştur.
class ConsentGatedHealthSource implements HealthDataSource {
  ConsentGatedHealthSource({
    required this.inner,
    required this.ownerId,
    required this.consent,
  });

  final HealthDataSource inner;
  final String? Function() ownerId;
  final AppleHealthConsentController consent;

  Future<bool> _allowed() async {
    final owner = ownerId();
    return owner != null && await consent.check(owner) && owner == ownerId();
  }

  @override
  Future<HealthSnapshot> readToday({DateTime? now}) async {
    if (!await _allowed()) {
      return const HealthSnapshot(
        status: HealthStatus.notConnected,
        message: appleHealthConsentMessage,
      );
    }
    return inner.readToday(now: now);
  }

  @override
  Future<List<HealthDayReading>> readPastDays({
    int days = HealthService.backfillDays,
    DateTime? now,
  }) async {
    if (!await _allowed()) return const [];
    return inner.readPastDays(days: days, now: now);
  }

  /// Onay varsa ve iç kaynak HealthKit ise son günlerin antrenmanları.
  Future<List<AppleWorkout>> readWorkouts({DateTime? now}) async {
    final source = inner;
    if (source is! HealthService || !await _allowed()) return const [];
    return source.readWorkouts(now: now);
  }
}
