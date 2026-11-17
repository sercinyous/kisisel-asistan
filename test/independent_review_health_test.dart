import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/health_source_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _clientId = '123-abc.apps.googleusercontent.com';

Future<void> _login(SupabaseClient client, String id) async {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': id, 'exp': 4102444800})))
      .replaceAll('=', '');
  await client.auth.recoverSession(jsonEncode({
    'access_token': 'e30.$payload.signature',
    'refresh_token': 'fake',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': 4102444800,
    'user': {
      'id': id,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
}

/// Sunucuya giden istekleri tutan Supabase istemcisi.
(SupabaseClient, List<http.Request>) _recordingClient() {
  final requests = <http.Request>[];
  final client = SupabaseClient(
    'https://test.supabase.co',
    'anon',
    httpClient: MockClient((req) async {
      requests.add(req);
      return http.Response('[]', 200, request: req);
    }),
  );
  return (client, requests);
}

/// Bugünü [gate] tamamlanınca döndüren sağlık kaynağı.
class _GatedSource implements HealthDataSource {
  final Completer<HealthSnapshot> gate = Completer<HealthSnapshot>();

  @override
  Future<HealthSnapshot> readToday({DateTime? now}) => gate.future;

  @override
  Future<List<HealthDayReading>> readPastDays({
    int days = HealthService.backfillDays,
    DateTime? now,
  }) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('#2 sabit kullanıcı', () {
    test('late read after account switch does NOT write as B', () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      final repository = HealthRepository(client);
      final owner = repository.currentUserId;
      final read = Completer<HealthSnapshot>();
      final pending = () async {
        final snapshot = await read.future;
        await repository.upsertHealthMetrics(
          DateTime(2026, 11, 18),
          snapshot,
          ownerId: owner,
        );
      }();
      await _login(client, 'account-B');
      read.complete(
          const HealthSnapshot(status: HealthStatus.ok, steps: 1234));
      await pending;
      expect(owner, 'account-A');
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
    });

    test('pinned owner writes with its own user id while session matches',
        () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      final repository = HealthRepository(client);
      await repository.upsertHealthDays(
        [
          (
            day: DateTime(2026, 11, 17),
            snapshot: const HealthSnapshot(status: HealthStatus.ok, steps: 5),
          ),
        ],
        ownerId: 'account-A',
      );
      final body = jsonDecode(requests.single.body) as List<dynamic>;
      expect((body.single as Map)['user_id'], 'account-A');
      expect((body.single as Map)['source'], 'appleHealth');
    });

    test('external workout import is skipped after account switch', () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      final repository = HealthRepository(client);
      await _login(client, 'account-B');
      await repository.importExternalWorkouts(
        [
          ExternalWorkout(
            source: 'google_health',
            externalId: 'x1',
            workout: WorkoutLog(
              id: '',
              workoutType: 'run',
              title: 'Koşu',
              durationMin: 30,
              loggedAt: DateTime(2026, 11, 17, 8),
            ),
          ),
        ],
        ownerId: 'account-A',
      );
      expect(requests, isEmpty);
    });

    test('healthTodayProvider: read finishing after user change is not saved',
        () async {
      final health = FakeHealthRepository()..userId = 'account-A';
      final source = _GatedSource();
      final container = ProviderContainer(overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        healthDataSourceProvider.overrideWithValue(source),
        googleClientIdProvider.overrideWithValue(''),
      ]);
      addTearDown(container.dispose);
      final today = container.read(healthTodayProvider.future);
      health.userId = 'account-B';
      source.gate.complete(
          const HealthSnapshot(status: HealthStatus.ok, steps: 1234));
      await today;
      expect(health.upsertedHealth, isEmpty);
      expect(health.metrics, isEmpty);
    });
  });

  group('#6 kaynak', () {
    test('zero reading after nonzero from same source IS written', () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      final repository = HealthRepository(client);
      final day = DateTime(2026, 11, 18);
      await repository.upsertHealthMetrics(
        day,
        const HealthSnapshot(status: HealthStatus.ok, steps: 9999),
      );
      await repository.upsertHealthMetrics(
        day,
        const HealthSnapshot(status: HealthStatus.ok),
      );
      expect(requests, hasLength(2));
      final zero = requests.last;
      expect(zero.method, 'PATCH');
      expect((jsonDecode(zero.body) as Map)['steps'], 0);
      // Yalnızca aynı kaynağın (ya da kaynaksız eski HealthKit) satırı.
      expect(Uri.decodeFull(zero.url.query),
          contains('or=(source.eq.appleHealth,source.is.null)'));
      expect(zero.url.queryParameters['user_id'], 'eq.account-A');
    });

    test('zero reading never inserts a row nor targets another source',
        () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      await HealthRepository(client).upsertHealthMetrics(
        DateTime(2026, 11, 18),
        const HealthSnapshot(
          status: HealthStatus.ok,
          source: HealthSourceKind.googleHealth,
        ),
      );
      final only = requests.single;
      expect(only.method, 'PATCH');
      expect(Uri.decodeFull(only.url.query),
          contains('or=(source.eq.googleHealth)'));
    });

    test('charts read only the selected source', () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      await HealthRepository(client).fetchDailyMetrics(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 7),
        source: HealthSourceKind.googleHealth,
      );
      expect(Uri.decodeFull(requests.single.url.query),
          contains('or=(source.eq.googleHealth)'));
    });

    test('HealthKit past-day zero keeps permission-ambiguity guard', () async {
      final (client, requests) = _recordingClient();
      addTearDown(client.dispose);
      await _login(client, 'account-A');
      await HealthRepository(client).upsertHealthDays([
        (
          day: DateTime(2026, 11, 17),
          snapshot: const HealthSnapshot(status: HealthStatus.ok),
        ),
      ]);
      expect(requests, isEmpty);
    });

    test('switching source hides old source numbers (fake repository)',
        () async {
      final health = FakeHealthRepository();
      final day = DateTime(2026, 11, 18);
      await health.upsertHealthMetrics(
          day, const HealthSnapshot(status: HealthStatus.ok, steps: 9999));
      await health.upsertHealthMetrics(
        day,
        const HealthSnapshot(
          status: HealthStatus.ok,
          source: HealthSourceKind.googleHealth,
        ),
      );
      expect(
        await health.fetchDailyMetrics(day, day,
            source: HealthSourceKind.googleHealth),
        isEmpty,
      );
      expect(
        (await health.fetchDailyMetrics(day, day,
                source: HealthSourceKind.appleHealth))
            .single
            .steps,
        9999,
      );
    });
  });

  group('#3 Google bağlantısı kullanıcıya ait', () {
    late FakeGoogleAuthClient auth;
    late StateController<String?> owner;

    ProviderContainer make(GoogleLinkPrefs prefs, String? initialOwner) {
      final ownerState = StateProvider<String?>((ref) => initialOwner);
      final container = ProviderContainer(overrides: [
        googleClientIdProvider.overrideWithValue(_clientId),
        googleAuthClientProvider.overrideWithValue(auth),
        initialGoogleLinkProvider.overrideWithValue(prefs),
        healthOwnerIdProvider.overrideWith((ref) => ref.watch(ownerState)),
      ]);
      addTearDown(container.dispose);
      owner = container.read(ownerState.notifier);
      return container;
    }

    setUp(() => auth = FakeGoogleAuthClient(email: 'a@gmail.com')
      ..signedIn = true);

    test('account switch blocks reads of A\'s Google link', () async {
      final container = make(
        GoogleLinkPrefs(
          ownerId: 'account-A',
          email: 'a@gmail.com',
          exerciseWatermark: DateTime.utc(2026, 11, 16),
        ),
        'account-A',
      );
      final controller = container.read(googleConnectionProvider.notifier);
      expect(await controller.accessToken(), 'fake-google-token');

      owner.state = 'account-B';
      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.disconnected);
      expect(state.email, isNull);
      final callsBefore = auth.silentCalls;
      await expectLater(
        container.read(googleConnectionProvider.notifier).accessToken(),
        throwsA(isA<GoogleHealthException>()),
      );
      expect(auth.silentCalls, callsBefore);
      expect(
          container.read(googleConnectionProvider.notifier).exerciseWatermark,
          isNull);
    });

    test('B must reconnect explicitly; then B\'s link is stored under B',
        () async {
      final container = make(
        const GoogleLinkPrefs(ownerId: 'account-A', email: 'a@gmail.com'),
        'account-B',
      );
      auth.email = 'b@gmail.com';
      await container.read(googleConnectionProvider.notifier).connect();
      expect(
        await container.read(googleConnectionProvider.notifier).accessToken(),
        'fake-google-token',
      );
      const store = GoogleLinkStore();
      expect((await store.load(userId: 'account-B')).email, 'b@gmail.com');
      expect((await store.load(userId: 'account-A')).email, isNull);
    });

    test('B\'s own stored link still requires reconnect after switch',
        () async {
      await const GoogleLinkStore()
          .saveEmail('b@gmail.com', userId: 'account-B');
      final container = make(
        const GoogleLinkPrefs(ownerId: 'account-A', email: 'a@gmail.com'),
        'account-B',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(googleConnectionProvider);
      expect(state.status, GoogleLinkStatus.reconnect);
      expect(state.email, 'b@gmail.com');
      await expectLater(
        container.read(googleConnectionProvider.notifier).accessToken(),
        throwsA(isA<GoogleHealthException>().having(
            (e) => e.kind, 'kind', GoogleHealthErrorKind.reconnect)),
      );
    });

    test('token for a different Google account than the stored link is refused',
        () async {
      final container = make(
        const GoogleLinkPrefs(ownerId: 'account-A', email: 'a@gmail.com'),
        'account-A',
      );
      auth.email = 'someone-else@gmail.com';
      await expectLater(
        container.read(googleConnectionProvider.notifier).accessToken(),
        throwsA(isA<GoogleHealthException>().having(
            (e) => e.kind, 'kind', GoogleHealthErrorKind.reconnect)),
      );
    });

    test('link prefs are stored per Supabase user', () async {
      const store = GoogleLinkStore();
      await store.saveEmail('a@gmail.com', userId: 'account-A');
      await store.saveExerciseWatermark(DateTime.utc(2026, 11, 16),
          userId: 'account-A');
      final b = await store.load(userId: 'account-B');
      expect(b.email, isNull);
      expect(b.exerciseWatermark, isNull);
      expect(b.ownerId, 'account-B');
      expect((await store.load(userId: 'account-A')).email, 'a@gmail.com');
    });
  });
}
