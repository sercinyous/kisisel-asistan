// Apple Health içe aktarma onayı uygulama kullanıcısına aittir: aynı
// iPhone'da A onay verdiyse ve cihazda HealthKit izni varsa bile B hesabıyla
// girilince B açıkça onaylayana kadar bugün ve geçmiş günler yazılmaz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/healthkit_card.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  late DateTime today;
  late DateTime yesterday;
  late FakeHealthRepository repo;
  late FakeHealthService healthKit;
  late MemoryAppleHealthConsentStore consentStore;

  setUpAll(() => initializeDateFormatting(AppDates.locale));

  setUp(() {
    today = AppDates.startOfDay(DateTime.now());
    yesterday = AppDates.addDays(today, -1);
    repo = FakeHealthRepository()..userId = 'user-a';
    // Cihazda HealthKit izni verilmiş: okuma başarılı döner.
    healthKit = FakeHealthService(
      HealthSnapshot(
        status: HealthStatus.ok,
        steps: 5000,
        readAt: DateTime.now(),
      ),
      pastDays: [
        (
          day: yesterday,
          snapshot: const HealthSnapshot(status: HealthStatus.ok, steps: 9000),
        ),
      ],
    );
    consentStore = MemoryAppleHealthConsentStore(granted: {'user-a'});
  });

  List<Override> overrides() => [
        healthRepositoryProvider.overrideWithValue(repo),
        healthServiceProvider.overrideWithValue(healthKit),
        appleHealthConsentStoreProvider.overrideWithValue(consentStore),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
      ];

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    return container;
  }

  test('A onaylıyken B\'ye geçilince bugün ve geçmiş günler yazılmaz', () async {
    repo.userId = 'user-b';
    final container = makeContainer();

    await backfillHealthKit(container);
    final snapshot = await container.read(healthTodayProvider.future);

    expect(snapshot.status, HealthStatus.notConnected);
    expect(snapshot.message, appleHealthConsentMessage);
    expect(repo.upsertedHealth, isEmpty);
    expect(repo.upsertedDays, isEmpty);
    // HealthKit hiç okunmaz.
    expect(healthKit.pastDayReads, 0);
  });

  test('B onay verince yazmalar B\'ye gider; A\'nın onayı değişmez', () async {
    repo.userId = 'user-b';
    final container = makeContainer();
    await backfillHealthKit(container);
    expect(repo.upsertedHealth, isEmpty);

    expect(await approveAppleHealth(container), isTrue);

    expect(repo.upsertedHealth.single.steps, 5000);
    expect(repo.upsertedDays, [yesterday]);
    expect(consentStore.granted, {'user-a', 'user-b'});
    expect(await consentStore.load('user-a'), isTrue);
  });

  test('onaylı A için bugün ve geçmiş günler yazılır', () async {
    final container = makeContainer();
    await backfillHealthKit(container);
    expect(repo.upsertedHealth.single.steps, 5000);
    expect(repo.upsertedDays, [yesterday]);
  });

  test('onay kullanıcıya göre ayrı anahtarda saklanır; kayıt yoksa onaysız',
      () async {
    SharedPreferences.setMockInitialValues({
      'apple_health_consent:user-a': true,
      // Eski cihaz geneli tercih kimseye onay vermez.
      'health_source': 'appleHealth',
    });
    const store = PrefsAppleHealthConsentStore();
    expect(await store.load('user-a'), isTrue);
    expect(await store.load('user-b'), isFalse);
    await store.save('user-b', granted: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('apple_health_consent:user-b'), isTrue);
    await store.save('user-b', granted: false);
    expect(prefs.containsKey('apple_health_consent:user-b'), isFalse);
    expect(await store.load('user-a'), isTrue);
  });

  test('kaynak tercihi kullanıcıya göre saklanır', () async {
    SharedPreferences.setMockInitialValues({
      'health_source:user-a': 'googleHealth',
    });
    const store = HealthSourceStore();
    expect(await store.load(userId: 'user-a'), HealthSourceKind.googleHealth);
    expect(await store.load(userId: 'user-b'), HealthSourceKind.appleHealth);
    await store.save(HealthSourceKind.appleHealth, userId: 'user-b');
    expect(await store.load(userId: 'user-a'), HealthSourceKind.googleHealth);
  });

  testWidgets('B için kart onay ister; dokununca B\'ye yazılır',
      (tester) async {
    repo.userId = 'user-b';
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: HealthSourceBanner()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(appleHealthConsentMessage), findsOneWidget);
    expect(repo.upsertedHealth, isEmpty);

    await tester.tap(find.text('Bu hesap için onayla'));
    await tester.pumpAndSettle();

    expect(find.text(appleHealthConsentMessage), findsNothing);
    expect(repo.upsertedHealth.single.steps, 5000);
    expect(repo.upsertedDays, [yesterday]);
  });
}
