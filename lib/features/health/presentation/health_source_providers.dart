import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/google_auth.dart';
import '../../../core/services/google_health_api.dart';
import '../../../core/services/health_service.dart';
import '../../../core/services/health_source.dart';
import '../data/google_health_source.dart';

export '../../../core/services/google_auth.dart'
    show GoogleAuthException, GoogleAuthErrorKind, googleHealthScopes;
export '../../../core/services/health_source.dart';

/// Google bağlantısının cihazda saklanan izleri (Supabase'e yazılmaz).
class GoogleLinkPrefs {
  const GoogleLinkPrefs({
    this.email,
    this.lastSyncAt,
    this.exerciseWatermark,
  });

  /// Son bağlanan hesap; doluysa oturum yenilenemediğinde "yeniden bağlan"
  /// gösterilir, boşsa "bağlan".
  final String? email;

  /// Son başarılı okuma anı.
  final DateTime? lastSyncAt;

  /// İçe aktarılan son antrenmanın Google'daki oluşturulma anı.
  final DateTime? exerciseWatermark;
}

/// [GoogleLinkPrefs]'i `shared_preferences` ile saklar. Her okuma/yazma
/// zaman aşımlı ve hata yutulur (bozuk depo uygulamayı durdurmaz).
class GoogleLinkStore {
  const GoogleLinkStore({this.open = SharedPreferences.getInstance});

  static const String emailKey = 'google_health_email';
  static const String lastSyncKey = 'google_health_last_sync';
  static const String watermarkKey = 'google_health_exercise_watermark';
  static const Duration timeout = Duration(seconds: 2);

  final Future<SharedPreferences> Function() open;

  Future<GoogleLinkPrefs> load() async {
    try {
      final prefs = await open().timeout(timeout);
      final email = prefs.getString(emailKey);
      return GoogleLinkPrefs(
        email: email == null || email.isEmpty ? null : email,
        lastSyncAt: _time(prefs.getString(lastSyncKey)),
        exerciseWatermark: _time(prefs.getString(watermarkKey)),
      );
    } catch (_) {
      return const GoogleLinkPrefs();
    }
  }

  Future<void> saveEmail(String? email) => _write(emailKey, email);

  Future<void> saveLastSync(DateTime? at) =>
      _write(lastSyncKey, at?.toUtc().toIso8601String());

  Future<void> saveExerciseWatermark(DateTime? at) =>
      _write(watermarkKey, at?.toUtc().toIso8601String());

  Future<void> clear() async {
    await saveEmail(null);
    await saveLastSync(null);
    await saveExerciseWatermark(null);
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

/// Google hesabı bağlantısı: giriş, sessiz yeniden yetkilendirme, durum ve
/// cihazdaki izler. Google Health kaynağı erişim anahtarını buradan alır ve
/// okuma sonucunu buraya bildirir ([GoogleHealthLink]).
class GoogleConnectionController extends Notifier<GoogleLinkState>
    implements GoogleHealthLink {
  DateTime? _watermark;

  GoogleAuthClient get _auth => ref.read(googleAuthClientProvider);
  GoogleLinkStore get _store => ref.read(googleLinkStoreProvider);

  @override
  GoogleLinkState build() {
    final prefs = ref.watch(initialGoogleLinkProvider);
    _watermark = prefs.exerciseWatermark;
    if (!ref.watch(googleConfiguredProvider)) {
      return const GoogleLinkState(status: GoogleLinkStatus.notConfigured);
    }
    // İlk okuma oturumu doğrulayana kadar kayıtlı hesap bağlı sayılır.
    return GoogleLinkState(
      status: prefs.email == null
          ? GoogleLinkStatus.disconnected
          : GoogleLinkStatus.connected,
      email: prefs.email,
      lastSyncAt: prefs.lastSyncAt,
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
    try {
      final token = await _auth.silentToken(googleHealthScopes);
      return token.accessToken;
    } on GoogleAuthException catch (error) {
      throw switch (error.kind) {
        GoogleAuthErrorKind.noSession => state.email == null
            ? const GoogleHealthException(GoogleHealthErrorKind.notConnected)
            : const GoogleHealthException(
                GoogleHealthErrorKind.reconnect,
                message: 'Google oturumu bulunamadı. Google\'a yeniden bağlan.',
              ),
        GoogleAuthErrorKind.scopesMissing =>
          const GoogleHealthException(GoogleHealthErrorKind.missingScope),
        GoogleAuthErrorKind.network =>
          const GoogleHealthException(GoogleHealthErrorKind.network),
        GoogleAuthErrorKind.configuration =>
          GoogleHealthException(
            GoogleHealthErrorKind.configuration,
            message: error.message,
          ),
        _ => GoogleHealthException(
            GoogleHealthErrorKind.reconnect,
            message: GoogleAuthErrorKind.expired.defaultMessage,
          ),
      };
    }
  }

  /// Google giriş penceresini açar ve okuma izinlerini ister. Yalnızca
  /// kullanıcı dokunuşuyla çağrılır. Başarısızlıkta durum eski haline döner
  /// ve [GoogleAuthException] iletilir.
  Future<void> connect() async {
    final before = state;
    if (before.status == GoogleLinkStatus.notConfigured) {
      throw const GoogleAuthException(GoogleAuthErrorKind.configuration);
    }
    if (before.status == GoogleLinkStatus.connecting) return;
    state = GoogleLinkState(
      status: GoogleLinkStatus.connecting,
      email: before.email,
      lastSyncAt: before.lastSyncAt,
    );
    try {
      final account = await _auth.connect(googleHealthScopes);
      final sameAccount = account.email == before.email;
      state = GoogleLinkState(
        status: GoogleLinkStatus.connected,
        email: account.email,
        lastSyncAt: sameAccount ? before.lastSyncAt : null,
      );
      await _store.saveEmail(account.email);
      if (!sameAccount) {
        // Başka hesap: önceki hesabın eşitleme izleri geçersizdir.
        _watermark = null;
        await _store.saveLastSync(null);
        await _store.saveExerciseWatermark(null);
      }
    } on GoogleAuthException catch (error) {
      state = error.kind == GoogleAuthErrorKind.scopesMissing
          ? GoogleLinkState(
              status: GoogleLinkStatus.reconnect,
              email: before.email,
              lastSyncAt: before.lastSyncAt,
              message: error.message,
            )
          : before;
      rethrow;
    } catch (_) {
      state = before;
      throw const GoogleAuthException(GoogleAuthErrorKind.unknown);
    }
  }

  /// İzni geri alır, oturumu kapatır ve cihazdaki izleri siler. Daha önce
  /// yazılan günlük değerler ve içe aktarılan antrenmanlar silinmez.
  Future<void> disconnect() async {
    if (!isConfigured) return;
    await _auth.disconnect();
    _watermark = null;
    state = const GoogleLinkState(status: GoogleLinkStatus.disconnected);
    await _store.clear();
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
    if (!state.isLinked) return;
    state = GoogleLinkState(
      status: GoogleLinkStatus.connected,
      email: state.email,
      lastSyncAt: at,
    );
    _store.saveLastSync(at).ignore();
  }

  @override
  DateTime? get exerciseWatermark => _watermark;

  @override
  Future<void> saveExerciseWatermark(DateTime value) async {
    _watermark = value;
    await _store.saveExerciseWatermark(value);
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

final googleHealthSourceProvider = Provider<GoogleHealthReader>((ref) {
  final link = ref.watch(googleConnectionProvider.notifier);
  return GoogleHealthSource(
    link: link,
    api: GoogleHealthApi(
      accessToken: link.accessToken,
      client: ref.watch(googleHealthHttpClientProvider),
    ),
  );
});

/// Seçili sağlık verisi kaynağı. Apple Health seçiliyken doğrudan
/// [healthServiceProvider] döner (HealthKit davranışı değişmez); aynı anda
/// yalnızca biri okunur ve yedeklenir.
final healthDataSourceProvider = Provider<HealthDataSource>(
  (ref) => switch (ref.watch(healthSourceProvider)) {
    HealthSourceKind.appleHealth => ref.watch(healthServiceProvider),
    HealthSourceKind.googleHealth => ref.watch(googleHealthSourceProvider),
  },
);
