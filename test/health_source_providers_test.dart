import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/google_health_source.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

const String testClientId = '123-abc.apps.googleusercontent.com';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime today;
  late DateTime yesterday;
  late FakeHealthRepository store;
  late FakeHealthService healthKit;
  late FakeGoogleAuthClient auth;
  late FakeGoogleHealthSource? google;

  HealthDayReading reading(DateTime day, int steps, int kcal, int sleep) => (
        day: day,
        snapshot: HealthSnapshot(
          status: HealthStatus.ok,
          steps: steps,
          activeKcal: kcal,
          sleepMinutes: sleep,
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    today = AppDates.startOfDay(DateTime.now());
    yesterday = AppDates.addDays(today, -1);
    store = FakeHealthRepository();
    healthKit = FakeHealthService(
      HealthSnapshot(
        status: HealthStatus.ok,
        steps: 3000,
        activeKcal: 200,
        sleepMinutes: 400,
        readAt: DateTime.now(),
      ),
      pastDays: [reading(yesterday, 9000, 450, 420)],
    );
    auth = FakeGoogleAuthClient(email: 'ben@gmail.com', signedIn: true);
    google = null;
  });

  ProviderContainer make({
    HealthSourceKind source = HealthSourceKind.googleHealth,
    GoogleLinkPrefs prefs = const GoogleLinkPrefs(email: 'ben@gmail.com'),
    String clientId = testClientId,
  }) {
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(store),
        healthServiceProvider.overrideWithValue(healthKit),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        initialHealthSourceProvider.overrideWithValue(source),
        initialGoogleLinkProvider.overrideWithValue(prefs),
        googleClientIdProvider.overrideWithValue(clientId),
        googleAuthClientProvider.overrideWithValue(auth),
        googleHealthSourceProvider.overrideWith(
          (ref) => google = FakeGoogleHealthSource(
            link: ref.watch(googleConnectionProvider.notifier),
            today: const HealthSnapshot(
              status: HealthStatus.ok,
              steps: 5200,
              activeKcal: 310,
              sleepMinutes: 455,
            ),
            pastDays: [reading(yesterday, 12000, 610, 470)],
            workouts: [
              ExternalWorkout(
                source: GoogleHealthSource.workoutSource,
                externalId: 'run-1',
                workout: WorkoutLog(
                  id: '',
                  workoutType: 'running',
                  loggedAt: yesterday.add(const Duration(hours: 7)),
                  durationMin: 40,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  DailyHealthMetric rowOf(DateTime day) =>
      store.metrics.firstWhere((m) => m.day == day);

  test('Apple Health seçiliyken Google hiç okunmaz (HealthKit aynen)', () async {
    final container = make(source: HealthSourceKind.appleHealth);

    final snapshot = await container.read(healthTodayProvider.future);
    await backfillHealthKit(container);

    expect(snapshot.source, HealthSourceKind.appleHealth);
    expect(snapshot.steps, 3000);
    expect(google, isNull, reason: 'Google kaynağı kurulmadı bile');
    expect(rowOf(today).steps, 3000);
    expect(rowOf(yesterday).steps, 9000);
    expect(healthKit.pastDayReads, 1);
    expect(store.importCalls, 0);
  });

  test('Google seçiliyken tek kaynak Google: bugün, geçmiş günler ve antrenman',
      () async {
    final container = make();
    container.listen(recentWorkoutsProvider, (_, __) {});
    expect(await container.read(recentWorkoutsProvider.future), isEmpty);

    final snapshot = await container.read(healthTodayProvider.future);
    expect(snapshot.source, HealthSourceKind.googleHealth);
    expect(snapshot.steps, 5200);

    await backfillHealthKit(container);

    expect(healthKit.pastDayReads, 0, reason: 'HealthKit okunmaz');
    expect(store.upsertedHealth.single.source, HealthSourceKind.googleHealth);
    expect(rowOf(today).steps, 5200);
    expect(rowOf(yesterday).steps, 12000);
    expect(rowOf(yesterday).activeKcal, 610);
    expect(rowOf(yesterday).sleepMinutes, 470);
    expect(google!.importCalls, 1);
    final workouts = await container.read(recentWorkoutsProvider.future);
    expect(workouts.single.source, 'google', reason: 'antrenman listesi tazelendi');

    // Yeniden eşitleme kopya üretmez.
    await resyncHealthKit(container);
    expect(store.workouts, hasLength(1));
    expect(container.read(googleConnectionProvider).lastSyncAt, isNotNull);
  });

  test('kaynak değişince değerler toplanmaz, yeni kaynağınkiyle değişir', () async {
    final container = make(source: HealthSourceKind.appleHealth);
    await backfillHealthKit(container);
    expect(rowOf(yesterday).steps, 9000);
    expect(rowOf(today).steps, 3000);

    await selectHealthSource(container, HealthSourceKind.googleHealth);

    expect(container.read(healthSourceProvider), HealthSourceKind.googleHealth);
    expect(rowOf(yesterday).steps, 12000, reason: '9000 + 12000 değil');
    expect(rowOf(today).steps, 5200);
    expect(store.metrics.where((m) => m.day == today), hasLength(1));
    expect(
      await const HealthSourceStore().load(),
      HealthSourceKind.googleHealth,
      reason: 'seçim cihazda saklanır',
    );

    // Geri dönüş: HealthKit değerleri yeniden yazılır.
    await selectHealthSource(container, HealthSourceKind.appleHealth);
    expect(rowOf(yesterday).steps, 9000);
    expect(rowOf(today).steps, 3000);
  });

  test('Google oturumu dolmuşsa "yeniden bağlan", hiçbir şey yazılmaz', () async {
    auth.silentError = const GoogleAuthException(GoogleAuthErrorKind.expired);
    final container = make();

    final snapshot = await container.read(healthTodayProvider.future);
    await backfillHealthKit(container);

    expect(snapshot.status, HealthStatus.reconnect);
    expect(snapshot.message, contains('Google\'a yeniden bağlan'));
    expect(store.metrics, isEmpty);
    expect(store.importCalls, 0);
    final link = container.read(googleConnectionProvider);
    expect(link.status, GoogleLinkStatus.reconnect);
    expect(link.email, 'ben@gmail.com');
  });

  test('bağlı değilken bağlan: oturum açılır ve Google hemen eşitlenir', () async {
    auth.signedIn = false;
    final container = make(prefs: const GoogleLinkPrefs());

    final before = await container.read(healthTodayProvider.future);
    expect(before.status, HealthStatus.notConnected);
    expect(container.read(googleConnectionProvider).status,
        GoogleLinkStatus.disconnected);

    final error = await connectGoogleHealth(container);

    expect(error, isNull);
    expect(auth.connectCalls, 1);
    expect(container.read(googleConnectionProvider).status,
        GoogleLinkStatus.connected);
    expect((await container.read(healthTodayProvider.future)).steps, 5200);
    expect(rowOf(yesterday).steps, 12000);
  });

  test('bağlanırken vazgeçilirse hata metni yok, başka hata metni döner', () async {
    auth.signedIn = false;
    final container = make(prefs: const GoogleLinkPrefs());
    auth.connectError = const GoogleAuthException(GoogleAuthErrorKind.canceled);
    expect(await connectGoogleHealth(container), isNull);
    auth.connectError =
        const GoogleAuthException(GoogleAuthErrorKind.configuration);
    expect(await connectGoogleHealth(container), contains('yapılandırması'));
  });

  test('bağlantıyı kesince Google seçili kartlar "bağlı değil" gösterir', () async {
    final container = make();
    await backfillHealthKit(container);
    expect(rowOf(today).steps, 5200);

    await disconnectGoogleHealth(container);

    final snapshot = await container.read(healthTodayProvider.future);
    expect(snapshot.status, HealthStatus.notConnected);
    expect(rowOf(today).steps, 5200, reason: 'kayıtlı değerler silinmez');
  });
}
