import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';
import '../helpers/kokpit_fakes.dart';
import '../helpers/test_fonts.dart';

const String testClientId = '123-abc.apps.googleusercontent.com';

void main() {
  late FakeGoogleAuthClient auth;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = FakeGoogleAuthClient(email: 'ben@gmail.com', signedIn: true);
  });

  List<Override> googleOverrides({
    GoogleLinkPrefs prefs = const GoogleLinkPrefs(email: 'ben@gmail.com'),
  }) =>
      [
        googleClientIdProvider.overrideWithValue(testClientId),
        googleAuthClientProvider.overrideWithValue(auth),
        initialHealthSourceProvider
            .overrideWithValue(HealthSourceKind.googleHealth),
        initialGoogleLinkProvider.overrideWithValue(prefs),
        googleHealthSourceProvider.overrideWith(
          (ref) => FakeGoogleHealthSource(
            link: ref.watch(googleConnectionProvider.notifier),
            today: const HealthSnapshot(
              status: HealthStatus.ok,
              steps: 7321,
              activeKcal: 455,
              sleepMinutes: 428,
            ),
          ),
        ),
      ];

  group('Kokpit sağlık kartı', () {
    late KokpitHarness harness;

    setUp(() => harness = KokpitHarness()..mockPlatformChannel());

    testWidgets('Google seçiliyken veriler Google Health\'ten okunur',
        (tester) async {
      await harness.pump(tester, textScale: 1.3, overrides: googleOverrides());

      expect(find.textContaining('7.321 /'), findsOneWidget);
      expect(find.textContaining('HealthKit'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Apple seçiliyken HealthKit verisi gösterilir', (tester) async {
      await harness.pump(tester);
      expect(find.textContaining(' adım'), findsOneWidget);
      expect(find.text('Adım verisi yok'), findsNothing);
    });

    testWidgets('oturum dolmuşsa yeniden bağlan mesajı ve düğmesi',
        (tester) async {
      auth.silentError = const GoogleAuthException(GoogleAuthErrorKind.expired);
      await harness.pump(tester, textScale: 1.3, overrides: googleOverrides());

      expect(find.textContaining('Google\'a yeniden bağlan'), findsOneWidget);
      expect(find.text('Yeniden bağlan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Yeniden bağlan'));
      await tester.pumpAndSettle();
      expect(auth.connectCalls, 1);
      expect(find.textContaining('7.321 /'), findsOneWidget);
    });

    testWidgets('bağlı değilken "Bağlan" düğmesi', (tester) async {
      auth.signedIn = false;
      await harness.pump(
        tester,
        textScale: 1.3,
        overrides: googleOverrides(prefs: const GoogleLinkPrefs()),
      );
      expect(find.text('Google Health bağlı değil.'), findsOneWidget);
      expect(find.text('Bağlan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
