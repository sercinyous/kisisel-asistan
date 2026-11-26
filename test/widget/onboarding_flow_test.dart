import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_source.dart'
    show MemoryAppleHealthConsentStore, appleHealthConsentStoreProvider;
import 'package:kisisel_asistan/core/services/error_reporter.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_answers.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_op_key_store.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_repository.dart';
import 'package:kisisel_asistan/features/onboarding/presentation/onboarding_gate.dart';
import 'package:kisisel_asistan/features/onboarding/presentation/onboarding_screen.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

class _Harness {
  final reported = <(Object, StackTrace?)>[];
  final settings = FakeSettingsRepository();
  final routines = FakeRoutinesRepository();
  final health = FakeHealthRepository();
  final notifications = FakeNotificationService();
  final healthService =
      FakeHealthService(const HealthSnapshot(status: HealthStatus.ok));
  late final onboarding = FakeOnboardingRepository(
    settings: settings,
    routines: routines,
    health: health,
  );
  final keys = OnboardingOpKeyStore(
    scope: 'test',
    open: () async => throw StateError('depo yok'),
  );

  List<Override> get overrides => [
        settingsRepositoryProvider.overrideWithValue(settings),
        routinesRepositoryProvider.overrideWithValue(routines),
        healthRepositoryProvider.overrideWithValue(health),
        notificationServiceProvider.overrideWithValue(notifications),
        appleHealthConsentStoreProvider.overrideWithValue(
          MemoryAppleHealthConsentStore(grantAll: true),
        ),
        healthServiceProvider.overrideWithValue(healthService),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        onboardingOpKeyStoreProvider.overrideWithValue(keys),
        reportErrorProvider.overrideWithValue((e, s) => reported.add((e, s))),
      ];
}

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  void bigScreen(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpGate(WidgetTester tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const OnboardingGate(
            child: Scaffold(body: Center(child: Text('ana kabuk'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  bool nextEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
          .onPressed !=
      null;

  /// 5 tanıtım kartını geçip soru adımına gelir.
  Future<void> skipIntro(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tap(tester, 'onboarding-next');
    }
    expect(find.text('Seni tanıyalım'), findsOneWidget);
  }

  /// Profil (erkek, 36 yaş) → sağlık adımı atlanır → boy 180, kilo 80 →
  /// hedefler adımı (amaç [goal]).
  Future<void> fillToTargets(WidgetTester tester, {String goal = 'lose'}) async {
    await type(tester, 'onboarding-name', ' Ayşe ');
    await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
    await tap(tester, 'onboarding-sex-male');
    await tap(tester, 'onboarding-next');
    expect(find.text('Profilini seç'), findsOneWidget);
    await tap(tester, 'onboarding-next');
    expect(find.text('Sağlık verisi'), findsOneWidget);
    await tap(tester, 'onboarding-next');
    expect(find.text('Boy ve kilo'), findsOneWidget);
    await type(tester, 'onboarding-height', '180');
    await type(tester, 'onboarding-weight', '80');
    await tap(tester, 'onboarding-next');
    expect(find.text('Önerilen hedeflerin'), findsOneWidget);
    await tap(tester, 'onboarding-goal-$goal');
  }

  group('technicalErrorCode', () {
    test('PostgREST kodu, ağ ve tür', () {
      expect(
        technicalErrorCode(const PostgrestException(message: 'x', code: '42501')),
        'Kod: PG 42501',
      );
      expect(technicalErrorCode(TimeoutException('t')), 'Kod: NET Timeout');
      expect(technicalErrorCode(StateError('s')), 'Kod: StateError');
    });
  });

  group('OnboardingGate', () {
    testWidgets('onboarded_at boşsa kılavuz, doluysa ana kabuk', (tester) async {
      await pumpGate(tester);
      expect(find.text('ana kabuk'), findsNothing);
      expect(find.text('Adım 1 / 7'), findsOneWidget);
      expect(find.text('Kokpit: günün tek bakışta'), findsOneWidget);
    });

    testWidgets('onboarded_at doluysa doğrudan ana kabuk', (tester) async {
      h.settings.settings =
          const UserSettings.defaults().copyWith(onboardedAt: DateTime(2026, 1, 1));
      await pumpGate(tester);
      expect(find.text('ana kabuk'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('ayarlar okunamazsa tekrar dene gösterilir, sonra devam eder',
        (tester) async {
      h.settings.fetchError = StateError('ağ yok');
      await pumpGate(tester);
      expect(find.text('Hesabın yüklenemedi'), findsOneWidget);
      expect(find.text('ana kabuk'), findsNothing);
      expect(find.text('Kod: StateError'), findsOneWidget);
      expect(h.reported, hasLength(1));
      expect(h.reported.single.$1, isA<StateError>());
      expect(h.reported.single.$2, isNotNull);

      h.settings.fetchError = null;
      h.settings.settings =
          const UserSettings.defaults().copyWith(onboardedAt: DateTime(2026, 1, 1));
      await tap(tester, 'onboarding-retry');
      expect(find.text('ana kabuk'), findsOneWidget);
    });
  });

  group('Kılavuz (5 kart)', () {
    testWidgets('kartlar sırayla gelir; son kartta Başlayalım; Geri döner',
        (tester) async {
      await pumpGate(tester);
      const titles = [
        'Kokpit: günün tek bakışta',
        '+ ile iki ayrı giriş',
        'İşler ve aylık rutinler',
        'Sağlık: trend ve denge',
        'İçgörü ve Arkadaşlar',
      ];
      expect(find.byKey(const Key('onboarding-back')), findsNothing);
      for (final (index, title) in titles.indexed) {
        expect(find.text(title), findsOneWidget, reason: title);
        if (index < titles.length - 1) {
          expect(find.text('İleri'), findsOneWidget);
          await tap(tester, 'onboarding-next');
        }
      }
      expect(find.text('Başlayalım'), findsOneWidget);
      await tap(tester, 'onboarding-back');
      expect(find.text('Sağlık: trend ve denge'), findsOneWidget);
    });

    testWidgets('Tanıtımı atla doğrudan sorulara götürür', (tester) async {
      await pumpGate(tester);
      await tap(tester, 'onboarding-skip-intro');
      expect(find.text('Seni tanıyalım'), findsOneWidget);
      expect(find.text('Adım 2 / 7'), findsOneWidget);
    });

    testWidgets('yeniden gösterim: yalnızca kartlar, Bitti kapatır, hiçbir şey '
        'yazılmaz', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const OnboardingScreen(replay: true),
                      ),
                    ),
                    child: const Text('aç'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.text('Kılavuz'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-sign-out')), findsNothing);
      expect(find.byKey(const Key('onboarding-skip-intro')), findsNothing);

      for (var i = 0; i < 4; i++) {
        await tap(tester, 'onboarding-next');
      }
      expect(find.text('Bitti'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('aç'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(h.settings.saved, isEmpty);
      expect(h.health.weights, isEmpty);
      expect(h.routines.routines, isEmpty);
    });
  });

  group('Sıra: profil, sağlık, boy-kilo, hedefler, rutinler', () {
    testWidgets('profil: ad zorunlu; doğum yılı ve cinsiyet isteğe bağlı',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      expect(find.text('Adım 2 / 7'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-timezone')), findsOneWidget);
      expect(find.text('Belirtmek istemiyorum'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await type(tester, 'onboarding-name', 'Ayşe');
      expect(nextEnabled(tester), isTrue, reason: 'doğum yılı isteğe bağlı');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 12}');
      expect(nextEnabled(tester), isFalse, reason: '13 yaş altı');
      expect(find.text(OnboardingValidators.underAgeMessage), findsOneWidget);
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      expect(nextEnabled(tester), isTrue, reason: 'cinsiyet isteğe bağlı');

      await tap(tester, 'onboarding-next');
      expect(find.text('Adım 3 / 7'), findsOneWidget);
      expect(find.text('Profilini seç'), findsOneWidget);
      await tap(tester, 'onboarding-avatar-skip');
      expect(find.text('Adım 4 / 7'), findsOneWidget);
      expect(find.text('Sağlık verisi'), findsOneWidget);
      expect(find.text('İleri'), findsOneWidget);
    });

    testWidgets('boy ve kilo zorunlu ve sınırlı', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      expect(find.text('Adım 5 / 7'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
      await type(tester, 'onboarding-height', '50');
      expect(find.text('100–250 arasında olmalı.'), findsOneWidget);
      await type(tester, 'onboarding-height', '180');
      expect(nextEnabled(tester), isFalse, reason: 'kilo yok');
      await type(tester, 'onboarding-weight', '80');
      expect(nextEnabled(tester), isTrue);
      expect(fieldText(tester, 'onboarding-height'), '180');
    });

    testWidgets('Apple Sağlık bağlanınca boy ve kilo son ölçümle dolar',
        (tester) async {
      h.healthService.body =
          const BodyMeasurements(heightCm: 182, weightKg: 81.4);
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-health-request');
      expect(find.text('İzin verildi.'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('Boy ve kilo'), findsOneWidget);
      expect(fieldText(tester, 'onboarding-height'), '182');
      expect(fieldText(tester, 'onboarding-weight'), '81,4');
      expect(find.textContaining('son ölçümlerinle'), findsOneWidget);
      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('sağlık kaynağı bağlanmazsa alanlar boş kalır', (tester) async {
      h.healthService.body =
          const BodyMeasurements(heightCm: 182, weightKg: 81.4);
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      expect(fieldText(tester, 'onboarding-height'), '');
      expect(fieldText(tester, 'onboarding-weight'), '');
    });

    testWidgets('hedefler: VKİ, hareket düzeyi, önerilen hedef kilo ve '
        'düzenlenebilir hedefler', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillToTargets(tester);
      expect(find.text('Adım 6 / 7'), findsOneWidget);
      // 80 / 1,8² = 24,7 → Normal; hedef kilo = mevcut kilo.
      expect(find.text('24,7 · Normal'), findsOneWidget);
      expect(fieldText(tester, 'onboarding-target-weight'), '80');
      // Bazal 1750 x 1,375 = 2406; ver: -500.
      expect(fieldText(tester, 'onboarding-calories'), '1906');
      expect(fieldText(tester, 'onboarding-protein'), '128');
      expect(fieldText(tester, 'onboarding-steps'), '8000');
      expect(fieldText(tester, 'onboarding-sleep'), '450');
      expect(find.text('7 sa 30 dk'), findsOneWidget);

      await tap(tester, 'onboarding-activity-moderate');
      // 1750 x 1,55 = 2712,5 → 2713 - 500.
      expect(fieldText(tester, 'onboarding-calories'), '2213');
      await tap(tester, 'onboarding-goal-maintain');
      expect(fieldText(tester, 'onboarding-calories'), '2713');

      await type(tester, 'onboarding-calories', '99');
      expect(nextEnabled(tester), isFalse, reason: 'sınır altı');
      await type(tester, 'onboarding-calories', '2000');
      expect(nextEnabled(tester), isTrue);
      await tap(tester, 'onboarding-targets-reset');
      expect(fieldText(tester, 'onboarding-calories'), '2713');
    });

    testWidgets('geri dönünce düzenleme korunur; kilo değişince yeniden '
        'önerilir', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillToTargets(tester);
      await type(tester, 'onboarding-calories', '1900');

      await tap(tester, 'onboarding-back');
      expect(find.text('Boy ve kilo'), findsOneWidget);
      await tap(tester, 'onboarding-next');
      expect(fieldText(tester, 'onboarding-calories'), '1900');

      await tap(tester, 'onboarding-back');
      await type(tester, 'onboarding-weight', '100');
      await tap(tester, 'onboarding-next');
      // 100 / 1,8² = 30,9 → hedef 24,9 x 3,24 = 80,7.
      expect(fieldText(tester, 'onboarding-target-weight'), '80,7');
      expect(find.text('30,9 · Obez'), findsOneWidget);
      expect(fieldText(tester, 'onboarding-calories'), isNot('1900'));
    });
  });

  group('Profil resmi adımı', () {
    testWidgets('Atla baş harflerle sağlık adımına geçer, hiçbir şey yazılmaz',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe Demir');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      expect(find.text('Profilini seç'), findsOneWidget);
      expect(find.text('AD'), findsOneWidget, reason: 'baş harf önizlemesi');
      expect(find.byKey(const Key('mascot-kaplumbaga')), findsOneWidget);
      await tap(tester, 'onboarding-avatar-skip');
      expect(find.text('Sağlık verisi'), findsOneWidget);
      expect(h.settings.savedAvatars, isEmpty);
    });

    testWidgets('maskot seçimi hemen kaydedilir ve ilk kurulumla korunur',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'mascot-panda');
      expect(h.settings.savedAvatars.single.mascotId, 'panda');
      await tap(tester, 'onboarding-next');
      expect(find.text('Sağlık verisi'), findsOneWidget);
      expect(h.settings.settings!.avatar.mascotId, 'panda');
    });
  });

  group('Tamamlama', () {
    testWidgets('tek ayar kaydı, seçilen rutinler ve tartı yazılır; ana kabuk '
        'açılır', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillToTargets(tester);
      await tap(tester, 'onboarding-activity-moderate');
      await tap(tester, 'onboarding-goal-lose');
      await type(tester, 'onboarding-target-weight', '78');
      await type(tester, 'onboarding-calories', '1900');
      await tap(tester, 'onboarding-next');

      // Son adım: rutinler + bildirimler, Başla.
      expect(find.text('Adım 7 / 7'), findsOneWidget);
      expect(find.text('Başlangıç rutinleri'), findsOneWidget);
      expect(find.text('Bildirimler'), findsWidgets);
      expect(find.text('Başla'), findsOneWidget);
      await tap(tester, 'onboarding-routine-yuruyus');
      await tap(tester, 'onboarding-routine-kira');
      await tester.ensureVisible(
          find.byKey(const Key('onboarding-request-permission')));
      await tester.pumpAndSettle();
      await tap(tester, 'onboarding-request-permission');
      expect(h.notifications.permissionRequests, 1);
      expect(find.text('İzin verildi.'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('ana kabuk'), findsOneWidget);
      expect(h.settings.saved, hasLength(1));
      final saved = h.settings.saved.single;
      expect(saved.isOnboarded, isTrue);
      expect(saved.displayName, 'Ayşe');
      expect(saved.heightCm, 180);
      expect(saved.birthYear, DateTime.now().year - 36);
      expect(saved.sex, 'male');
      expect(saved.activityLevel, ActivityLevel.moderate);
      expect(saved.startWeightKg, 80);
      expect(saved.targetWeightKg, 78);
      expect(saved.dailyCalories, 1900);
      expect(saved.dailyProteinG, 128);
      expect(saved.dailySteps, 8000);
      expect(saved.sleepMinutes, 450);
      expect(saved.workDescription, isNull);
      expect(h.onboarding.payloads.single['timezone'], 'Europe/Istanbul');

      expect(h.routines.routines.map((r) => r.title),
          ['Yürüyüş yap', 'Kirayı öde']);
      expect(h.health.weights, hasLength(1));
      expect(h.health.weights.single.weightKg, 80);
    });

    testWidgets('cinsiyet seçilmezse "belirtmek istemiyorum" yazılır; hiç '
        'rutin seçilmezse boş başlanır', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      await type(tester, 'onboarding-height', '170');
      await type(tester, 'onboarding-weight', '70');
      await tap(tester, 'onboarding-next');
      await tap(tester, 'onboarding-next');
      expect(find.text('Başla'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('ana kabuk'), findsOneWidget);
      expect(h.routines.routines, isEmpty);
      expect(h.health.weights, hasLength(1));
      final saved = h.settings.saved.single;
      expect(saved.isOnboarded, isTrue);
      expect(saved.sex, 'unspecified');
      expect(saved.activityLevel, ActivityLevel.light);
    });

    testWidgets('kayıt hatasında kapı açılmaz ve hiçbir şey yazılmaz; yeniden '
        'denemede aynı işlem anahtarı kullanılır, tartı çiftlenmez',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillToTargets(tester);
      await tap(tester, 'onboarding-next');
      h.settings.saveError = StateError('ağ yok');
      await tap(tester, 'onboarding-next');

      expect(find.text('ana kabuk'), findsNothing);
      expect(find.byKey(const Key('onboarding-error')), findsOneWidget);
      expect(h.settings.saved, isEmpty);
      expect(h.health.weights, isEmpty, reason: 'tek transaction geri alındı');

      h.settings.saveError = null;
      await tap(tester, 'onboarding-next');
      expect(find.text('ana kabuk'), findsOneWidget);
      expect(h.onboarding.calls, hasLength(2));
      expect(h.onboarding.calls.toSet(), hasLength(1));
      expect(h.health.weights, hasLength(1), reason: 'çift tartı olmamalı');
      expect(h.settings.saved, hasLength(1));
    });
  });
}
