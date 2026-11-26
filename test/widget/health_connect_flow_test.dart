import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/onboarding/presentation/onboarding_health_step.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/presentation/connections_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

const String testClientId = '123-abc.apps.googleusercontent.com';

/// HealthKit izin penceresinin kaç kez istendiğini sayar.
class CountingHealthService extends FakeHealthService {
  CountingHealthService(super.snapshot);

  int requests = 0;

  @override
  Future<bool> requestAccess({bool body = false}) async {
    requests++;
    return super.requestAccess(body: body);
  }
}

void main() {
  late CountingHealthService healthKit;
  late MemoryAppleHealthConsentStore consent;
  late FakeGoogleAuthClient auth;
  late http.Response Function(http.Request) googleServer;

  setUpAll(() => initializeDateFormatting(AppDates.locale));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    healthKit = CountingHealthService(
      HealthSnapshot(
        status: HealthStatus.ok,
        steps: 3000,
        readAt: DateTime.now(),
      ),
    );
    consent = MemoryAppleHealthConsentStore();
    auth = FakeGoogleAuthClient(email: 'yeni@gmail.com');
    googleServer =
        (_) => http.Response(jsonEncode({'healthUserId': 'u-1'}), 200);
  });

  ProviderContainer make({
    HealthSourceKind source = HealthSourceKind.appleHealth,
    HealthSnapshot googleToday = const HealthSnapshot(status: HealthStatus.ok),
    GoogleHealthException? googleError,
  }) {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
        healthServiceProvider.overrideWithValue(healthKit),
        appleHealthConsentStoreProvider.overrideWithValue(consent),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        googleClientIdProvider.overrideWithValue(testClientId),
        googleAuthClientProvider.overrideWithValue(auth),
        initialHealthSourceProvider.overrideWithValue(source),
        googleHealthHttpClientProvider.overrideWithValue(
          MockClient((request) async => googleServer(request)),
        ),
        googleHealthSourceProvider.overrideWith(
          (ref) => FakeGoogleHealthSource(
            link: ref.watch(googleConnectionProvider.notifier),
            today: googleToday,
          )..readError = googleError,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container,
    Widget page,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Bağlantılar › Apple Sağlık', () {
    testWidgets('onay yokken "Bağla" izin ister, onay verir ve okur',
        (tester) async {
      final container = make();
      await pumpPage(tester, container, const ConnectionsPage());
      expect(find.text('Bu hesap için onay gerekli'), findsOneWidget);

      await tester.tap(find.text('Bağla'));
      await tester.pumpAndSettle();

      expect(healthKit.requests, greaterThanOrEqualTo(1));
      expect(consent.granted, contains('demo-user'));
      expect(find.text('Bağlı'), findsOneWidget);
      expect(container.read(healthSourceProvider), HealthSourceKind.appleHealth);
    });

    testWidgets('izinli ama boş HealthKit: bağlı, veri yok (hata değil)',
        (tester) async {
      healthKit.snapshot = HealthSnapshot(
        status: HealthStatus.ok,
        readAt: DateTime.now(),
      );
      consent.granted.add('demo-user');
      final container = make();
      await pumpPage(tester, container, const ConnectionsPage());
      expect(find.text('Bağlı, bugün için veri yok'), findsOneWidget);
      expect(find.text('Okunamadı'), findsNothing);
    });

    testWidgets('Google seçiliyken "Bağlan ve seç" Apple\'a geçer ve onaylar',
        (tester) async {
      final container = make(source: HealthSourceKind.googleHealth);
      await pumpPage(tester, container, const ConnectionsPage());

      await tester.tap(find.text('Bağlan ve seç'));
      await tester.pumpAndSettle();

      expect(healthKit.requests, greaterThanOrEqualTo(1));
      expect(container.read(healthSourceProvider), HealthSourceKind.appleHealth);
      expect(consent.granted, contains('demo-user'));
      expect(find.text('Bağlı'), findsOneWidget);
    });
  });

  group('Karşılama › sağlık adımı', () {
    Widget step() => Scaffold(
          body: SingleChildScrollView(
            child: OnboardingHealthStep(
              access: OnboardingHealthAccess.idle,
              onRequest: () {},
              onSkip: () {},
            ),
          ),
        );

    testWidgets('yeni Google hesabı (veri yok): bağlandı, henüz veri yok',
        (tester) async {
      final container = make();
      await pumpPage(tester, container, step());
      await tester.tap(find.byKey(const Key('onboarding-health-google')));
      await tester.pumpAndSettle();

      expect(container.read(healthSourceProvider), HealthSourceKind.googleHealth);
      expect(find.textContaining('Google Health bağlandı. Henüz veri yok'),
          findsOneWidget);
    });

    testWidgets('profil yok: mesaj gösterilir, kaynak Apple\'da kalır',
        (tester) async {
      googleServer = (_) => http.Response(
            jsonEncode({
              'error': {
                'code': 400,
                'status': 'FAILED_PRECONDITION',
                'details': [
                  {'reason': 'ACCOUNT_NOT_LINKED'},
                ],
              },
            }),
            400,
          );
      final container = make();
      await pumpPage(tester, container, step());
      await tester.tap(find.byKey(const Key('onboarding-health-google')));
      await tester.pumpAndSettle();

      expect(container.read(healthSourceProvider), HealthSourceKind.appleHealth);
      expect(find.textContaining('Fitbit'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-health-confirmation')),
          findsNothing);
      // Yeniden deneme düğmesi açık kalır.
      expect(find.byKey(const Key('onboarding-health-google')), findsOneWidget);
    });

    testWidgets('ilk okuma 400 verirse "bağlandı" yazılmaz, kaynak geri alınır',
        (tester) async {
      final container = make(
        googleError: const GoogleHealthException(
          GoogleHealthErrorKind.requestRejected,
          status: 400,
          detail: 'INVALID_ARGUMENT: bad range',
        ),
      );
      await pumpPage(tester, container, step());
      await tester.tap(find.byKey(const Key('onboarding-health-google')));
      await tester.pumpAndSettle();

      expect(container.read(healthSourceProvider), HealthSourceKind.appleHealth);
      expect(find.textContaining('INVALID_ARGUMENT: bad range'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-health-confirmation')),
          findsNothing);
    });
  });
}
