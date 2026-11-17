import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

const String testClientId = '123-abc.apps.googleusercontent.com';

void main() {
  late FakeGoogleAuthClient auth;
  late FakeHealthRepository store;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = FakeGoogleAuthClient(email: 'sercan.ornek@gmail.com');
    store = FakeHealthRepository();
  });

  /// Ayarlar'ı 375x667 ve 1.3 metin ölçeğinde açar, Bağlantılar'a kaydırır.
  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    String clientId = testClientId,
    HealthSourceKind source = HealthSourceKind.appleHealth,
    GoogleLinkPrefs prefs = const GoogleLinkPrefs(),
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        healthRepositoryProvider.overrideWithValue(store),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(
            HealthSnapshot(
              status: HealthStatus.ok,
              steps: 3000,
              readAt: DateTime.now(),
            ),
          ),
        ),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        googleClientIdProvider.overrideWithValue(clientId),
        googleAuthClientProvider.overrideWithValue(auth),
        initialHealthSourceProvider.overrideWithValue(source),
        initialGoogleLinkProvider.overrideWithValue(prefs),
        googleHealthSourceProvider.overrideWith(
          (ref) => FakeGoogleHealthSource(
            link: ref.watch(googleConnectionProvider.notifier),
            today: const HealthSnapshot(
              status: HealthStatus.ok,
              steps: 6400,
              activeKcal: 380,
              sleepMinutes: 440,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-google-row')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return container;
  }

  SegmentedButton<HealthSourceKind> picker(WidgetTester tester) =>
      tester.widget<SegmentedButton<HealthSourceKind>>(
        find.byKey(const Key('settings-health-source')),
      );

  Finder inGoogleRow(String text) => find.descendant(
        of: find.byKey(const Key('settings-google-row')),
        matching: find.textContaining(text),
      );

  testWidgets('istemci kimliği yok: Google seçeneği kapalı ve açıklamalı',
      (tester) async {
    await pumpSettings(tester, clientId: '');

    final segments = picker(tester).segments;
    expect(segments.first.enabled, isTrue);
    expect(segments.last.value, HealthSourceKind.googleHealth);
    expect(segments.last.enabled, isFalse);
    expect(find.textContaining('GOOGLE_IOS_CLIENT_ID'), findsWidgets);
    expect(inGoogleRow('Bu derlemede yapılandırılmamış'), findsOneWidget);
    expect(find.byKey(const Key('settings-google-connect')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bağlı değil: "Google ile bağlan" hesabı bağlar', (tester) async {
    final container = await pumpSettings(tester);

    expect(inGoogleRow('Bağlı değil'), findsOneWidget);
    final connect = find.byKey(const Key('settings-google-connect'));
    expect(find.descendant(of: connect, matching: find.text('Google ile bağlan')),
        findsOneWidget);

    await tester.ensureVisible(connect);
    await tester.pumpAndSettle();
    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(auth.connectCalls, 1);
    expect(container.read(googleConnectionProvider).status,
        GoogleLinkStatus.connected);
    expect(inGoogleRow('sercan.ornek@gmail.com'), findsOneWidget);
    expect(
      inGoogleRow('Kaynak olarak seçilince'),
      findsOneWidget,
      reason: 'Apple seçiliyken Google verisi kullanılmaz',
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('settings-google-sync')))
          .onPressed,
      isNull,
      reason: 'Apple seçiliyken "Şimdi eşitle" kapalı',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bağlı ve Google seçili: hesap, son eşitleme, Şimdi eşitle ve '
      'onaylı bağlantı kesme', (tester) async {
    auth.signedIn = true;
    final container = await pumpSettings(
      tester,
      source: HealthSourceKind.googleHealth,
      prefs: GoogleLinkPrefs(
        email: 'sercan.ornek@gmail.com',
        lastSyncAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    );

    expect(inGoogleRow('sercan.ornek@gmail.com'), findsOneWidget);
    expect(inGoogleRow('Son eşitleme: Bugün'), findsOneWidget);
    expect(picker(tester).selected, {HealthSourceKind.googleHealth});
    expect(find.text('Kaynak olarak seçili değil'), findsOneWidget,
        reason: 'Apple satırı Google okumasını yorumlamaz');

    final sync = find.byKey(const Key('settings-google-sync'));
    await tester.ensureVisible(sync);
    await tester.pumpAndSettle();
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(find.text('Google Health eşitlendi.'), findsOneWidget);
    expect(store.metrics.single.steps, 6400);

    final disconnect = find.byKey(const Key('settings-google-disconnect'));
    await tester.ensureVisible(disconnect);
    await tester.pumpAndSettle();
    await tester.tap(disconnect);
    await tester.pumpAndSettle();
    expect(find.text('Google bağlantısı kesilsin mi?'), findsOneWidget);

    // Vazgeç: hiçbir şey değişmez.
    await tester.tap(find.byKey(const Key('settings-google-disconnect-cancel')));
    await tester.pumpAndSettle();
    expect(auth.disconnectCalls, 0);

    await tester.ensureVisible(disconnect);
    await tester.pumpAndSettle();
    await tester.tap(disconnect);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-google-disconnect-confirm')));
    await tester.pumpAndSettle();

    expect(auth.disconnectCalls, 1);
    expect(container.read(googleConnectionProvider).status,
        GoogleLinkStatus.disconnected);
    expect(inGoogleRow('Bağlı değil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('oturum dolmuş: "Google\'a yeniden bağlan" durumu görünür',
      (tester) async {
    auth
      ..signedIn = true
      ..silentError = const GoogleAuthException(GoogleAuthErrorKind.expired);
    await pumpSettings(
      tester,
      source: HealthSourceKind.googleHealth,
      prefs: const GoogleLinkPrefs(email: 'sercan.ornek@gmail.com'),
    );

    expect(inGoogleRow('Google oturumunun süresi doldu'), findsOneWidget);
    expect(inGoogleRow('sercan.ornek@gmail.com'), findsOneWidget);
    final reconnect = find.byKey(const Key('settings-google-connect'));
    expect(
      find.descendant(of: reconnect, matching: find.text('Google\'a yeniden bağlan')),
      findsOneWidget,
    );

    await tester.ensureVisible(reconnect);
    await tester.pumpAndSettle();
    await tester.tap(reconnect);
    await tester.pumpAndSettle();

    expect(auth.connectCalls, 1);
    expect(inGoogleRow('Son eşitleme: Bugün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kaynak seçimi: Google Health\'e dokununca saklanır ve eşitlenir',
      (tester) async {
    auth.signedIn = true;
    final container = await pumpSettings(
      tester,
      prefs: const GoogleLinkPrefs(email: 'sercan.ornek@gmail.com'),
    );
    expect(picker(tester).selected, {HealthSourceKind.appleHealth});

    final segment = find.descendant(
      of: find.byKey(const Key('settings-health-source')),
      matching: find.text('Google Health'),
    );
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();

    expect(container.read(healthSourceProvider), HealthSourceKind.googleHealth);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HealthSourceStore.key), 'googleHealth');
    expect(store.metrics.single.steps, 6400);
    expect(tester.takeException(), isNull);
  });
}
