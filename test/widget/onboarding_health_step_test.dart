import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/onboarding/presentation/onboarding_health_step.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String clientId = '123-abc.apps.googleusercontent.com',
    VoidCallback? onSkip,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(const HealthSnapshot(status: HealthStatus.ok)),
        ),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        googleClientIdProvider.overrideWithValue(clientId),
        googleAuthClientProvider.overrideWithValue(
          FakeGoogleAuthClient(email: 'ben@gmail.com'),
        ),
        googleHealthSourceProvider.overrideWith(
          (ref) => FakeGoogleHealthSource(
            link: ref.watch(googleConnectionProvider.notifier),
            today: const HealthSnapshot(
              status: HealthStatus.ok,
              steps: 5200,
              source: HealthSourceKind.googleHealth,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingHealthStep(
                access: OnboardingHealthAccess.idle,
                onRequest: () {},
                onSkip: onSkip ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('iki kaynak ve atla seçeneği gösterilir', (tester) async {
    var skipped = 0;
    await pump(tester, onSkip: () => skipped++);
    expect(find.text('Apple Sağlık'), findsOneWidget);
    expect(find.text('Google Health'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-health-skip')));
    expect(skipped, 1);
  });

  testWidgets('Google bağlanınca kaynak seçilir ve adım gösterilir',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('onboarding-health-google')));
    await tester.pumpAndSettle();
    expect(container.read(healthSourceProvider), HealthSourceKind.googleHealth);
    expect(
      find.text('Google Health bağlandı. Bugün 5200 adım.'),
      findsOneWidget,
    );
  });

  testWidgets('istemci kimliği yoksa Google düğmesi gizlenir', (tester) async {
    await pump(tester, clientId: '');
    expect(find.byKey(const Key('onboarding-health-google')), findsNothing);
  });
}
