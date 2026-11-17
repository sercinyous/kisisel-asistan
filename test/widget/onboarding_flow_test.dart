import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
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
        healthServiceProvider.overrideWithValue(healthService),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        onboardingOpKeyStoreProvider.overrideWithValue(keys),
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

  /// Erkek, 80 kg, 180 cm, 36 yaşında, "kilo ver".
  Future<void> fillProfile(WidgetTester tester, {String goal = 'lose'}) async {
    await type(tester, 'onboarding-name', ' Ayşe ');
    await type(tester, 'onboarding-height', '180');
    await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
    await tap(tester, 'onboarding-sex-male');
    await type(tester, 'onboarding-weight', '80');
    await type(tester, 'onboarding-target-weight', '78');
    await tap(tester, 'onboarding-goal-$goal');
  }

  group('OnboardingGate', () {
    testWidgets('onboarded_at boşsa kılavuz, doluysa ana kabuk', (tester) async {
      await pumpGate(tester);
      expect(find.text('ana kabuk'), findsNothing);
      expect(find.text('Adım 1 / 6'), findsOneWidget);
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
        'Operasyon ve aylık sabitler',
        'Sağlık: trend ve denge',
        'Raporlar ve Arkadaşlar',
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
      expect(find.text('Adım 2 / 6'), findsOneWidget);
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

  group('Sorular ve hedefler', () {
    testWidgets('İleri, tüm zorunlu cevaplar geçerli olana dek kapalı',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      expect(nextEnabled(tester), isFalse);

      await type(tester, 'onboarding-name', 'Ayşe');
      await type(tester, 'onboarding-height', '50');
      expect(find.text('100–250 arasında olmalı.'), findsOneWidget);
      await type(tester, 'onboarding-height', '180');
      await type(tester, 'onboarding-birth-year', '${DateTime.now().year - 36}');
      await type(tester, 'onboarding-weight', '80');
      expect(nextEnabled(tester), isFalse, reason: 'cinsiyet ve amaç yok');
      await tap(tester, 'onboarding-sex-female');
      expect(nextEnabled(tester), isFalse, reason: 'amaç yok');
      await tap(tester, 'onboarding-goal-maintain');
      // Hedef kilo ve iş tanımı isteğe bağlı.
      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('önerilen hedefler formüle göre dolar ve düzenlenebilir',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillProfile(tester);
      await tap(tester, 'onboarding-next');

      expect(find.text('Önerilen hedeflerin'), findsOneWidget);
      // Bazal 1750 x 1,4 = 2450; ver: -500.
      expect(fieldText(tester, 'onboarding-calories'), '1950');
      expect(fieldText(tester, 'onboarding-protein'), '144');
      expect(fieldText(tester, 'onboarding-steps'), '8000');
      expect(fieldText(tester, 'onboarding-sleep'), '450');
      expect(find.text('7 sa 30 dk'), findsOneWidget);

      await type(tester, 'onboarding-calories', '99');
      expect(nextEnabled(tester), isFalse, reason: 'sınır altı');
      await type(tester, 'onboarding-calories', '1900');
      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('geri dönünce düzenleme korunur; hesabı etkileyen cevap '
        'değişince yeniden önerilir', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillProfile(tester);
      await tap(tester, 'onboarding-next');
      await type(tester, 'onboarding-calories', '1900');

      await tap(tester, 'onboarding-back');
      expect(find.text('Seni tanıyalım'), findsOneWidget);
      await tap(tester, 'onboarding-next');
      expect(fieldText(tester, 'onboarding-calories'), '1900');

      await tap(tester, 'onboarding-back');
      await tap(tester, 'onboarding-goal-maintain');
      await tap(tester, 'onboarding-next');
      expect(fieldText(tester, 'onboarding-calories'), '2450');

      await type(tester, 'onboarding-calories', '2000');
      await tap(tester, 'onboarding-targets-reset');
      expect(fieldText(tester, 'onboarding-calories'), '2450');
    });
  });

  group('Tamamlama', () {
    testWidgets('tek ayar kaydı, seçilen rutinler ve tartı yazılır; ana kabuk '
        'açılır', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillProfile(tester);
      await tap(tester, 'onboarding-next');
      await type(tester, 'onboarding-calories', '1900');
      await tap(tester, 'onboarding-next');

      // Bildirimler: izin istenir.
      expect(find.text('Bildirimler'), findsWidgets);
      await tap(tester, 'onboarding-request-permission');
      expect(h.notifications.permissionRequests, 1);
      expect(find.text('İzin verildi.'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      // Rutinler: varsayılan boş; ikisi seçilir.
      expect(find.text('Başlangıç rutinleri'), findsOneWidget);
      await tap(tester, 'onboarding-routine-yuruyus');
      await tap(tester, 'onboarding-routine-kira');
      await tap(tester, 'onboarding-next');

      // Sağlık kaynağı.
      expect(find.text('Sağlık verisi'), findsOneWidget);
      await tap(tester, 'onboarding-health-request');
      expect(find.text('İzin verildi.'), findsOneWidget);
      expect(find.text('Başla'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('ana kabuk'), findsOneWidget);
      expect(h.settings.saved, hasLength(1));
      final saved = h.settings.saved.single;
      expect(saved.isOnboarded, isTrue);
      expect(saved.displayName, 'Ayşe');
      expect(saved.heightCm, 180);
      expect(saved.birthYear, DateTime.now().year - 36);
      expect(saved.sex, 'male');
      expect(saved.startWeightKg, 80);
      expect(saved.targetWeightKg, 78);
      expect(saved.dailyCalories, 1900);
      expect(saved.dailyProteinG, 144);
      expect(saved.dailySteps, 8000);
      expect(saved.sleepMinutes, 450);
      expect(saved.workDescription, isNull);

      expect(h.routines.routines.map((r) => r.title),
          ['Yürüyüş yap', 'Kirayı öde']);
      expect(h.health.weights, hasLength(1));
      expect(h.health.weights.single.weightKg, 80);
    });

    testWidgets('hiç rutin seçilmezse boş başlanır', (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillProfile(tester, goal: 'maintain');
      for (var i = 0; i < 4; i++) {
        await tap(tester, 'onboarding-next');
      }
      expect(find.text('Sağlık verisi'), findsOneWidget);
      await tap(tester, 'onboarding-next');

      expect(find.text('ana kabuk'), findsOneWidget);
      expect(h.routines.routines, isEmpty);
      expect(h.health.weights, hasLength(1));
      expect(h.settings.saved.single.isOnboarded, isTrue);
    });

    testWidgets('kayıt hatasında kapı açılmaz ve hiçbir şey yazılmaz; yeniden '
        'denemede aynı işlem anahtarı kullanılır, tartı çiftlenmez',
        (tester) async {
      await pumpGate(tester);
      await skipIntro(tester);
      await fillProfile(tester);
      for (var i = 0; i < 4; i++) {
        await tap(tester, 'onboarding-next');
      }
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
