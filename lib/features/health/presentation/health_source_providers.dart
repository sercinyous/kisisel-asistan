import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/google_auth.dart';
import '../../../core/services/google_health_api.dart';
import '../../../core/services/health_service.dart';
import '../../../core/services/health_source.dart';
import '../data/google_health_source.dart';
import '../data/health_repository.dart';

export '../../../core/services/google_auth.dart'
    show GoogleAuthException, GoogleAuthErrorKind, googleHealthScopes;
export '../../../core/services/health_source.dart';

/// Google bağlantısının cihazda saklanan izleri (Supabase'e yazılmaz). Her
/// uygulama kullanıcısı için ayrı saklanır ([ownerId]); başka kullanıcının
/// bağlantısı okunmaz.
class GoogleLinkPrefs {
  const GoogleLinkPrefs({
    this.ownerId,
    this.email,
    this.lastSyncAt,
    this.exerciseWatermark,
  });

  /// Bağlantının sahibi olan Supabase kullanıcısı.
  final String? ownerId;

  /// Son bağlanan hesap; doluysa oturum yenilenemediğinde "yeniden bağlan"
  /// gösterilir, boşsa "bağlan".
  final String? email;

  /// Son başarılı okuma anı.
  final DateTime? lastSyncAt;

  /// İçe aktarılan son antrenmanın Google'daki oluşturulma anı.
  final DateTime? exerciseWatermark;
}

/// [GoogleLinkPrefs]'i `shared_preferences` ile, Supabase kullanıcı kimliğine
/// göre ayrı anahtarlarda (`<anahtar>:<kullanıcı>`) saklar. Her okuma/yazma
/// zaman aşımlı ve hata yutulur (bozuk depo uygulamayı durdurmaz). Kullanıcısız
/// (`userId == null`) anahtar yalnızca testlerin ve oturumsuz durumun yeridir.
class GoogleLinkStore {
  const GoogleLinkStore({this.open = SharedPreferences.getInstance});

  static const String emailKey = 'google_health_email';
  static const String lastSyncKey = 'google_health_last_sync';
  static const String watermarkKey = 'google_health_exercise_watermark';
  static const Duration timeout = Duration(seconds: 2);

  final Future<SharedPreferences> Function() open;

  /// [userId] kullanıcısına ait anahtar.
  static String keyFor(String key, String? userId) =>
      userId == null ? key : '$key:$userId';

  Future<GoogleLinkPrefs> load({String? userId}) async {
    try {
      final prefs = await open().timeout(timeout);
      final email = prefs.getString(keyFor(emailKey, userId));
      return GoogleLinkPrefs(
        ownerId: userId,
        email: email == null || email.isEmpty ? null : email,
        lastSyncAt: _time(prefs.getString(keyFor(lastSyncKey, userId))),
        exerciseWatermark: _time(prefs.getString(keyFor(watermarkKey, userId))),
      );
    } catch (_) {
      return GoogleLinkPrefs(ownerId: userId);
    }
  }

  Future<void> saveEmail(String? email, {String? userId}) =>
      _write(keyFor(emailKey, userId), email);

  Future<void> saveLastSync(DateTime? at, {String? userId}) =>
      _write(keyFor(lastSyncKey, userId), at?.toUtc().toIso8601String());

  Future<void> saveExerciseWatermark(DateTime? at, {String? userId}) =>
      _write(keyFor(watermarkKey, userId), at?.toUtc().toIso8601String());

  Future<void> clear({String? userId}) async {
    await saveEmail(null, userId: userId);
    await saveLastSync(null, userId: userId);
    await saveExerciseWatermark(null, userId: userId);
  }

  Future<void> _write(String key, String? value) async {
    try {
      final prefs = await open().timeout(timeout);
      if (value == null) {
        await prefs.remove(key).timeout(timeout);
      } else {
        await prefs.setString(key, value).timeout(timeout);
      }
    } catch (_) {
      // Yazılamazsa değer yalnızca bu oturumda geçerli kalır.
    }
  }

  static DateTime? _time(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

final googleLinkStoreProvider =
    Provider<GoogleLinkStore>((ref) => const GoogleLinkStore());

/// Açılıştaki kayıt; `main()` içinde [GoogleLinkStore.load] sonucuyla ezilir.
final initialGoogleLinkProvider =
    Provider<GoogleLinkPrefs>((ref) => const GoogleLinkPrefs());

enum GoogleLinkStatus {
  /// Derlemede istemci kimliği yok.
  notConfigured,

  /// Hesap bağlı değil.
  disconnected,

  /// Giriş penceresi açık.
  connecting,

  /// Bağlı (son okuma başarılı ya da henüz denenmedi).
  connected,

  /// Oturum yenilenemedi ya da izin eksik: kullanıcı yeniden bağlanmalı.
  reconnect,
}

class GoogleLinkState {
  const GoogleLinkState({
    required this.status,
    this.email,
    this.lastSyncAt,
    this.message,
  });

  final GoogleLinkStatus status;
  final String? email;
  final DateTime? lastSyncAt;

  /// [GoogleLinkStatus.reconnect] durumunun Türkçe nedeni.
  final String? message;

  bool get isLinked =>
      status == GoogleLinkStatus.connected ||
      status == GoogleLinkStatus.reconnect;
}

/// Uygulama kullanıcısı değişince bağlantının yeniden kurulması gerektiğini
/// anlatan metin.
const String googleOwnerChangedMessage =
    'Google Health bağlantısı başka bir kullanıcıya ait. Bu hesap için '
    'Google\'a yeniden bağlan.';

/// Google hesabı bağlantısı: giriş, sessiz yeniden yetkilendirme, durum ve
/// cihazdaki izler. Google Health kaynağı erişim anahtarını buradan alır ve
/// okuma sonucunu buraya bildirir ([GoogleHealthLink]).
///
/// Bağlantı Supabase kullanıcısına aittir: izler kullanıcıya göre saklanır,
/// kullanıcı değişince okuma durur ve yeni kullanıcı açıkça bağlanana kadar
/// erişim anahtarı verilmez (Google eklentisinin oturumu önceki kullanıcının
/// hesabı olabilir). Alınan anahtarın hesabı kayıtlı bağlantının hesabıyla
/// aynı değilse de anahtar verilmez.
class GoogleConnectionController extends Notifier<GoogleLinkState>
    implements GoogleHealthLink {
  DateTime? _watermark;
  String? _ownerId;
  bool _ownerChanged = false;
  int _generation = 0;

  GoogleAuthClient get _auth => ref.read(googleAuthClientProvider);
  GoogleLinkStore get _store => ref.read(googleLinkStoreProvider);

  /// Bağlantının her değişiminde (kullanıcı, bağlan, kes) artar; süren bir
  /// eşitleme kendi başladığı nesille yazmaya devam edip etmeyeceğini buna
  /// bakarak anlar.
  int get generation => _generation;

  /// Bağlantının sahibi olan Supabase kullanıcısı.
  String? get ownerId => _ownerId;

  @override
  GoogleLinkState build() {
    _generation++;
    final owner = ref.watch(healthOwnerIdProvider);
    final prefs = ref.watch(initialGoogleLinkProvider);
    _ownerId = owner;
    _ownerChanged = false;
    _watermark = null;
    if (!ref.watch(googleConfiguredProvider)) {
      return const GoogleLinkState(status: GoogleLinkStatus.notConfigured);
    }
    if (prefs.ownerId != owner) {
      // Açılıştaki izler başka kullanıcıya ait: okunmaz. Bu kullanıcının
      // kendi kaydı varsa da eklentideki Google oturumu ona ait olmayabilir;
      // açıkça yeniden bağlanması istenir.
      _ownerChanged = true;
      _loadOwnerLink(owner, _generation);
      return const GoogleLinkState(status: GoogleLinkStatus.disconnected);
    }
    _watermark = prefs.exerciseWatermark;
    // İlk okuma oturumu doğrulayana kadar kayıtlı hesap bağlı sayılır.
    return GoogleLinkState(
      status: prefs.email == null
          ? GoogleLinkStatus.disconnected
          : GoogleLinkStatus.connected,
      email: prefs.email,
      lastSyncAt: prefs.lastSyncAt,
    );
  }

  Future<void> _loadOwnerLink(String? owner, int generation) async {
    if (owner == null) return;
    final prefs = await _store.load(userId: owner);
    if (generation != _generation || prefs.email == null) return;
    state = GoogleLinkState(
      status: GoogleLinkStatus.reconnect,
      email: prefs.email,
      message: googleOwnerChangedMessage,
    );
  }

  @override
  bool get isConfigured => state.status != GoogleLinkStatus.notConfigured;

  /// Etkin durum (sağlayıcı dışından okunur).
  GoogleLinkState get current => state;

  @override
  Future<String> accessToken() async {
    if (!isConfigured) {
      throw const GoogleHealthException(GoogleHealthErrorKind.notConfigured);
    }
    if (_ownerChanged) {
      throw state.email == null
          ? const GoogleHealthException(GoogleHealthErrorKind.notConnected)
          : const GoogleHealthException(
              GoogleHealthErrorKind.reconnect,
              message: googleOwnerChangedMessage,
            );
    }
    final generation = _generation;
    final GoogleToken token;
    try {
      token = await _auth.silentToken(googleHealthScopes);
    } on GoogleAuthException catch (error) {
      throw switch (error.kind) {
        GoogleAuthErrorKind.noSession => state.email == null
            ? const GoogleHealthException(GoogleHealthErrorKind.notConnected)
            : const GoogleHealthException(
                GoogleHealthErrorKind.reconnect,
                message: 'Google oturumu bulunamadı. Google\'a yeniden bağlan.',
              ),
        // Google ile giriş yapılmışsa eklenti o hesabı sessizce bulur ama Health
        // kapsamları onaylı değildir. Health bağlantısı hiç kurulmadıysa (kayıtlı
        // hesap yok) bu "izin eksik" değil "bağlı değil" demektir; Health yalnızca
        // kullanıcı Ayarlar'dan bağlanınca bağlı sayılır.
        GoogleAuthErrorKind.scopesMissing => state.email == null
            ? const GoogleHealthException(GoogleHealthErrorKind.notConnected)
            : const GoogleHealthException(GoogleHealthErrorKind.missingScope),
        GoogleAuthErrorKind.network =>
          const GoogleHealthException(GoogleHealthErrorKind.network),
        GoogleAuthErrorKind.configuration => GoogleHealthException(
            GoogleHealthErrorKind.configuration,
            message: error.message,
          ),
        _ => GoogleHealthException(
            GoogleHealthErrorKind.reconnect,
            message: GoogleAuthErrorKind.expired.defaultMessage,
          ),
      };
    }
    // Anahtar beklenirken kullanıcı ya da bağlantı değiştiyse kullanılmaz.
    if (generation != _generation || _ownerChanged) {
      throw const GoogleHealthException(
        GoogleHealthErrorKind.reconnect,
        message: googleOwnerChangedMessage,
      );
    }
    final linked = state.email;
    // Health yalnızca bu kullanıcı Ayarlar'dan bağlandıysa okunur; eklentinin
    // sessizce bulduğu hesap (ör. Google ile giriş) bağlantı sayılmaz.
    if (linked == null) {
      throw const GoogleHealthException(GoogleHealthErrorKind.notConnected);
    }
    if (!_sameEmail(token.account.email, linked)) {
      throw const GoogleHealthException(
        GoogleHealthErrorKind.reconnect,
        message: 'Google oturumu bağlı hesaptan farklı. Google\'a yeniden '
            'bağlan.',
      );
    }
    return token.accessToken;
  }

  static bool _sameEmail(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Google giriş penceresini açar ve okuma izinlerini ister. Yalnızca
  /// kullanıcı dokunuşuyla çağrılır. Başarısızlıkta durum eski haline döner
  /// ve [GoogleAuthException] iletilir.
  Future<void> connect() async {
    final before = state;
    if (before.status == GoogleLinkStatus.notConfigured) {
      throw const GoogleAuthException(GoogleAuthErrorKind.configuration);
    }
    if (before.status == GoogleLinkStatus.connecting) return;
    final owner = _ownerId;
    final generation = ++_generation;
    state = GoogleLinkState(
      status: GoogleLinkStatus.connecting,
      email: before.email,
      lastSyncAt: before.lastSyncAt,
    );
    try {
      final account = await _auth.connect(googleHealthScopes);
      // Pencere açıkken uygulama kullanıcısı değiştiyse bağlantı kurulmaz.
      if (generation != _generation || owner != _ownerId) {
        throw const GoogleAuthException(GoogleAuthErrorKind.canceled);
      }
      final sameAccount = before.email != null &&
          _sameEmail(account.email, before.email!) &&
          !_ownerChanged;
      _ownerChanged = false;
      state = GoogleLinkState(
        status: GoogleLinkStatus.connected,
        email: account.email,
        lastSyncAt: sameAccount ? before.lastSyncAt : null,
      );
      await _store.saveEmail(account.email, userId: owner);
      if (!sameAccount) {
        // Başka hesap: önceki hesabın eşitleme izleri geçersizdir.
        _watermark = null;
        await _store.saveLastSync(null, userId: owner);
        await _store.saveExerciseWatermark(null, userId: owner);
      }
    } on GoogleAuthException catch (error) {
      if (generation == _generation) {
        state = error.kind == GoogleAuthErrorKind.scopesMissing
            ? GoogleLinkState(
                status: GoogleLinkStatus.reconnect,
                email: before.email,
                lastSyncAt: before.lastSyncAt,
                message: error.message,
              )
            : before;
      }
      rethrow;
    } catch (_) {
      if (generation == _generation) state = before;
      throw const GoogleAuthException(GoogleAuthErrorKind.unknown);
    }
  }

  /// Bağlanan hesapta Google Health profili yok: bağlantı kurulmuş sayılmaz.
  /// Google oturumu kapatılır ve bu kullanıcının izleri silinir; durum
  /// "bağlı değil" olur ve [error] mesajı gösterilir.
  Future<void> rejectUnlinkedAccount(GoogleHealthException error) async {
    final owner = _ownerId;
    _generation++;
    _watermark = null;
    _ownerChanged = false;
    state = GoogleLinkState(
      status: GoogleLinkStatus.disconnected,
      message: error.message,
    );
    try {
      await _auth.disconnect();
    } catch (_) {
      // Oturum kapatılamasa da bağlantı kayıtlı değildir.
    }
    await _store.clear(userId: owner);
  }

  /// İzni geri alır, oturumu kapatır ve bu kullanıcının cihazdaki izlerini
  /// siler. Daha önce yazılan günlük değerler ve içe aktarılan antrenmanlar
  /// silinmez.
  Future<void> disconnect() async {
    if (!isConfigured) return;
    final owner = _ownerId;
    await _auth.disconnect();
    _generation++;
    _watermark = null;
    _ownerChanged = false;
    state = const GoogleLinkState(status: GoogleLinkStatus.disconnected);
    await _store.clear(userId: owner);
  }

  @override
  void reportFailure(GoogleHealthException error) {
    final status = state.status;
    // Giriş sürerken gelen eski bir okumanın hatası durumu bozmasın.
    if (status == GoogleLinkStatus.notConfigured ||
        status == GoogleLinkStatus.connecting) {
      return;
    }
    switch (error.kind) {
      case GoogleHealthErrorKind.notConnected:
        state = const GoogleLinkState(status: GoogleLinkStatus.disconnected);
      case GoogleHealthErrorKind.reconnect:
      case GoogleHealthErrorKind.missingScope:
      case GoogleHealthErrorKind.accountNotLinked:
        state = GoogleLinkState(
          status: GoogleLinkStatus.reconnect,
          email: state.email,
          lastSyncAt: state.lastSyncAt,
          message: error.message,
        );
      default:
        // Geçici hata: bağlantı durumu değişmez, kart hatayı gösterir.
        break;
    }
  }

  @override
  void reportSynced(DateTime at) {
    if (!state.isLinked || _ownerChanged) return;
    state = GoogleLinkState(
      status: GoogleLinkStatus.connected,
      email: state.email,
      lastSyncAt: at,
    );
    _store.saveLastSync(at, userId: _ownerId).ignore();
  }

  @override
  DateTime? get exerciseWatermark => _ownerChanged ? null : _watermark;

  @override
  Future<void> saveExerciseWatermark(DateTime value) async {
    if (_ownerChanged) return;
    _watermark = value;
    await _store.saveExerciseWatermark(value, userId: _ownerId);
  }
}

/// Bir sağlık eşitlemesinin başladığı an: sahibi olan kullanıcı, kaynak ve
/// Google bağlantı nesli. Her `await` sonrasında [isValid] denetlenir;
/// kullanıcı, kaynak ya da Google bağlantısı değiştiyse (ya da kapsayıcı
/// kapandıysa) okunan değer yazılmaz. Yazmalar [ownerId] ile yapılır.
class HealthWriteGuard {
  HealthWriteGuard._(
    this._read,
    this.repository,
    this.ownerId,
    this.source,
    this._googleGeneration,
  );

  /// Sahip yoksa (oturum kapalı) `null`.
  static HealthWriteGuard? capture(
    T Function<T>(ProviderListenable<T> provider) read,
  ) {
    final repository = read(healthRepositoryProvider);
    final owner = repository.currentUserId;
    if (owner == null) return null;
    return HealthWriteGuard._(
      read,
      repository,
      owner,
      read(healthSourceProvider),
      read(googleConnectionProvider.notifier).generation,
    );
  }

  final T Function<T>(ProviderListenable<T> provider) _read;
  final HealthRepository repository;
  final String ownerId;
  final HealthSourceKind source;
  final int _googleGeneration;

  bool get isValid {
    try {
      return repository.currentUserId == ownerId &&
          identical(_read(healthRepositoryProvider), repository) &&
          _read(healthSourceProvider) == source &&
          (source != HealthSourceKind.appleHealth ||
              _read(appleHealthConsentProvider.notifier).isGranted(ownerId)) &&
          _read(googleConnectionProvider.notifier).generation ==
              _googleGeneration;
    } catch (_) {
      // Kapsayıcı ya da sağlayıcı kapanmış (çıkış, test sonu).
      return false;
    }
  }
}

final googleConnectionProvider =
    NotifierProvider<GoogleConnectionController, GoogleLinkState>(
  GoogleConnectionController.new,
);

/// Google Health isteklerinin HTTP istemcisi; testler `MockClient` verir.
final googleHealthHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Google Health REST istemcisi; erişim anahtarını bağlantıdan alır.
final googleHealthApiProvider = Provider<GoogleHealthApi>((ref) {
  final link = ref.watch(googleConnectionProvider.notifier);
  return GoogleHealthApi(
    accessToken: link.accessToken,
    client: ref.watch(googleHealthHttpClientProvider),
  );
});

final googleHealthSourceProvider = Provider<GoogleHealthReader>((ref) {
  return GoogleHealthSource(
    link: ref.watch(googleConnectionProvider.notifier),
    api: ref.watch(googleHealthApiProvider),
  );
});

/// Seçili sağlık verisi kaynağı. Apple Health seçiliyken [healthServiceProvider]
/// oturumdaki kullanıcının uygulama içi onayına bağlanır
/// ([ConsentGatedHealthSource]); aynı anda
/// yalnızca biri okunur ve yedeklenir.
final healthDataSourceProvider = Provider<HealthDataSource>(
  (ref) => switch (ref.watch(healthSourceProvider)) {
    HealthSourceKind.appleHealth => ConsentGatedHealthSource(
        inner: ref.watch(healthServiceProvider),
        ownerId: () => ref.read(healthRepositoryProvider).currentUserId,
        consent: ref.watch(appleHealthConsentProvider.notifier),
      ),
    HealthSourceKind.googleHealth => ref.watch(googleHealthSourceProvider),
  },
);
