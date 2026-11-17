import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/features/health/presentation/health_source_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

Future<SharedPreferences> _brokenStore() async =>
    throw StateError('depo kullanılamıyor');

const String testClientId = '123-abc.apps.googleusercontent.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HealthSourceKind', () {
    test('parse: bilinen adlar, yoksa Apple Health', () {
      expect(
          HealthSourceKind.parse('appleHealth'), HealthSourceKind.appleHealth);
      expect(HealthSourceKind.parse('googleHealth'),
          HealthSourceKind.googleHealth);
      expect(HealthSourceKind.parse(null), HealthSourceKind.appleHealth);
      expect(HealthSourceKind.parse('fitbit'), HealthSourceKind.appleHealth);
    });

    test('etiketler ve kısa adlar', () {
      expect(HealthSourceKind.appleHealth.label, 'Apple Health');
      expect(HealthSourceKind.googleHealth.label, 'Google Health');
      expect(HealthSourceKind.appleHealth.shortLabel, 'HealthKit');
      expect(HealthSourceKind.googleHealth.shortLabel, 'Google Health');
    });
  });

  group('HealthSourceStore', () {
    test('kayıt yokken Apple Health; kaydedilen tercih geri okunur', () async {
      const store = HealthSourceStore();
      expect(await store.load(), HealthSourceKind.appleHealth);

      await store.save(HealthSourceKind.googleHealth);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HealthSourceStore.key), 'googleHealth');
      expect(await store.load(), HealthSourceKind.googleHealth);
    });

    test('bozuk kayıt ya da depo hatası Apple Health\'e düşer', () async {
      SharedPreferences.setMockInitialValues({HealthSourceStore.key: 7});
      expect(
          await const HealthSourceStore().load(), HealthSourceKind.appleHealth);

      const broken = HealthSourceStore(open: _brokenStore);
      expect(await broken.load(), HealthSourceKind.appleHealth);
      await expectLater(broken.save(HealthSourceKind.googleHealth), completes);
    });
  });

  group('HealthSourceController', () {
    ProviderContainer make({
      HealthSourceKind initial = HealthSourceKind.appleHealth,
      String clientId = testClientId,
    }) {
      final container = ProviderContainer(
        overrides: [
          initialHealthSourceProvider.overrideWithValue(initial),
          googleClientIdProvider.overrideWithValue(clientId),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('seçim hemen uygulanır ve cihaza yazılır', () async {
      final container = make();
      expect(
          container.read(healthSourceProvider), HealthSourceKind.appleHealth);

      await container
          .read(healthSourceProvider.notifier)
          .select(HealthSourceKind.googleHealth);

      expect(
          container.read(healthSourceProvider), HealthSourceKind.googleHealth);
      expect(
        await const HealthSourceStore().load(),
        HealthSourceKind.googleHealth,
      );
    });

    test('istemci kimliği yoksa Google seçilemez, kayıtlı Google Apple olur',
        () async {
      final container =
          make(initial: HealthSourceKind.googleHealth, clientId: '');
      expect(container.read(googleConfiguredProvider), isFalse);
      expect(
          container.read(healthSourceProvider), HealthSourceKind.appleHealth);

      await container
          .read(healthSourceProvider.notifier)
          .select(HealthSourceKind.googleHealth);
      expect(
          container.read(healthSourceProvider), HealthSourceKind.appleHealth);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HealthSourceStore.key), isNull);
    });
  });

  group('GoogleLinkStore', () {
    test('hesap, son eşitleme ve işaret saklanır ve silinir', () async {
      const store = GoogleLinkStore();
      expect((await store.load()).email, isNull);

      final at = DateTime(2026, 11, 17, 14, 5);
      final mark = DateTime.utc(2026, 11, 16, 8);
      await store.saveEmail('ben@gmail.com');
      await store.saveLastSync(at);
      await store.saveExerciseWatermark(mark);
      final loaded = await store.load();
      expect(loaded.email, 'ben@gmail.com');
      expect(loaded.lastSyncAt, at);
      expect(loaded.exerciseWatermark!.isAtSameMomentAs(mark), isTrue);

      await store.clear();
      final cleared = await store.load();
      expect(cleared.email, isNull);
      expect(cleared.lastSyncAt, isNull);
      expect(cleared.exerciseWatermark, isNull);
    });

    test('depo hatası boş kayıt döner', () async {
      const broken = GoogleLinkStore(open: _brokenStore);
      expect((await broken.load()).email, isNull);
      await expectLater(broken.saveEmail('x@y.z'), completes);
    });
  });

  group('GoogleConnectionController', () {
    late FakeGoogleAuthClient auth;

    ProviderContainer make({
      String clientId = testClientId,
      GoogleLinkPrefs prefs = const GoogleLinkPrefs(),
    }) {
      final container = ProviderContainer(
        overrides: [
          googleClientIdProvider.overrideWithValue(clientId),
          googleAuthClientProvider.overrideWithValue(auth),
          initialGoogleLinkProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => auth = FakeGoogleAuthClient(email: 'ben@gmail.com'));

    test('istemci kimliği yoksa yapılandırılmamış; anahtar istenmez', () async {
      final container = make(clientId: '');
      final controller = container.read(googleConnectionProvider.notifier);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.notConfigured);
      expect(controller.isConfigured, isFalse);
      await expectLater(
        controller.accessToken(),
        throwsA(isA<GoogleHealthException>().having(
          (e) => e.kind,
          'kind',
          GoogleHealthErrorKind.notConfigured,
        )),
      );
      await expectLater(
        controller.connect(),
        throwsA(isA<GoogleAuthException>()),
      );
      expect(auth.silentCalls + auth.connectCalls, 0);
    });

    test('bağlan: salt okuma kapsamları istenir, hesap saklanır', () async {
      final container = make();
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.disconnected);

      await container.read(googleConnectionProvider.notifier).connect();

      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.connected);
      expect(state.email, 'ben@gmail.com');
      expect(auth.lastScopes, googleHealthScopes);
      expect((await const GoogleLinkStore().load()).email, 'ben@gmail.com');
      expect(
        await container.read(googleConnectionProvider.notifier).accessToken(),
        'fake-google-token',
      );
    });

    test('vazgeçilirse durum değişmez; izin eksikse yeniden bağlan', () async {
      final container = make();
      final controller = container.read(googleConnectionProvider.notifier);
      auth.connectError =
          const GoogleAuthException(GoogleAuthErrorKind.canceled);
      await expectLater(
          controller.connect(), throwsA(isA<GoogleAuthException>()));
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.disconnected);

      auth.connectError =
          const GoogleAuthException(GoogleAuthErrorKind.scopesMissing);
      await expectLater(
          controller.connect(), throwsA(isA<GoogleAuthException>()));
      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.reconnect);
      expect(state.message, contains('izin'));
    });

    test('kayıtlı hesabın oturumu yoksa ya da süresi dolduysa yeniden bağlan',
        () async {
      final container =
          make(prefs: const GoogleLinkPrefs(email: 'ben@gmail.com'));
      final controller = container.read(googleConnectionProvider.notifier);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.connected);

      // Kayıtlı oturum yok (signedIn = false).
      await expectLater(
        controller.accessToken(),
        throwsA(isA<GoogleHealthException>().having(
          (e) => e.kind,
          'kind',
          GoogleHealthErrorKind.reconnect,
        )),
      );

      auth
        ..signedIn = true
        ..silentError = const GoogleAuthException(GoogleAuthErrorKind.expired);
      try {
        await controller.accessToken();
        fail('hata bekleniyordu');
      } on GoogleHealthException catch (error) {
        expect(error.kind, GoogleHealthErrorKind.reconnect);
        controller.reportFailure(error);
      }
      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.reconnect);
      expect(state.email, 'ben@gmail.com');
      expect(state.message, contains('Google\'a yeniden bağlan'));

      // Ağ hatası geçicidir, durumu değiştirmez.
      auth.silentError = const GoogleAuthException(GoogleAuthErrorKind.network);
      await expectLater(
        controller.accessToken(),
        throwsA(isA<GoogleHealthException>().having(
          (e) => e.kind,
          'kind',
          GoogleHealthErrorKind.network,
        )),
      );
    });

    test('başarılı okuma bağlıya döndürür ve son eşitlemeyi saklar', () async {
      final container =
          make(prefs: const GoogleLinkPrefs(email: 'ben@gmail.com'));
      final controller = container.read(googleConnectionProvider.notifier);
      controller.reportFailure(
        const GoogleHealthException(GoogleHealthErrorKind.missingScope),
      );
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.reconnect);

      final at = DateTime(2026, 11, 17, 14, 5);
      controller.reportSynced(at);
      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.connected);
      expect(state.lastSyncAt, at);
      await pumpEventQueue();
      expect((await const GoogleLinkStore().load()).lastSyncAt, at);

      // Geçici hata durumu bozmaz.
      controller.reportFailure(
        const GoogleHealthException(GoogleHealthErrorKind.rateLimited),
      );
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.connected);
    });

    test('bağlantıyı kes: izin geri alınır, izler silinir', () async {
      final container = make(
        prefs: GoogleLinkPrefs(
          email: 'ben@gmail.com',
          lastSyncAt: DateTime(2026, 11, 17),
          exerciseWatermark: DateTime.utc(2026, 11, 16),
        ),
      );
      final controller = container.read(googleConnectionProvider.notifier);
      expect(controller.exerciseWatermark, DateTime.utc(2026, 11, 16));
      await const GoogleLinkStore().saveEmail('ben@gmail.com');

      await controller.disconnect();

      expect(auth.disconnectCalls, 1);
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.disconnected);
      expect(controller.exerciseWatermark, isNull);
      expect((await const GoogleLinkStore().load()).email, isNull);
      // Kesildikten sonra gelen eski başarı bağlıya döndürmez.
      controller.reportSynced(DateTime(2026, 11, 17, 15));
      expect(container.read(googleConnectionProvider).status,
          GoogleLinkStatus.disconnected);
    });

    test('başka hesapla bağlanınca önceki hesabın izleri sıfırlanır', () async {
      final container = make(
        prefs: GoogleLinkPrefs(
          email: 'eski@gmail.com',
          lastSyncAt: DateTime(2026, 11, 17),
          exerciseWatermark: DateTime.utc(2026, 11, 16),
        ),
      );
      final controller = container.read(googleConnectionProvider.notifier);
      await controller.connect();
      final state = container.read(googleConnectionProvider);
      expect(state.email, 'ben@gmail.com');
      expect(state.lastSyncAt, isNull);
      expect(controller.exerciseWatermark, isNull);
    });
  });
}
