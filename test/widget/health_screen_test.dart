import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/demo/demo_health_extras.dart';
import 'package:kisisel_asistan/features/health/data/water_repository.dart';
import 'package:kisisel_asistan/features/reports/data/weekly_checkin_repository.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_screen.dart';
import 'package:kisisel_asistan/features/health/domain/safe_targets.dart';
import 'package:kisisel_asistan/features/health/presentation/streak_detail_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/weekly_detail_screen.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

void main() {
  late FakeHealthRepository health;
  late FakeRoutinesRepository routines;
  late DateTime today;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  /// Dolu örnek veri: kilo serisi, iki kahvaltı kalemi, iki antrenman,
  /// 7 günlük adım ve her güne planlı bir spor rutini.
  void seed() {
    health = FakeHealthRepository(
      weights: [
        WeightEntry(
          id: 'w1',
          weightKg: 84.5,
          loggedAt: AppDates.addDays(today, -20),
        ),
        WeightEntry(
          id: 'w2',
          weightKg: 84.1,
          loggedAt: AppDates.addDays(today, -10),
        ),
        WeightEntry(
          id: 'w3',
          weightKg: 83.6,
          loggedAt: AppDates.addDays(today, -1),
        ),
      ],
      nutritionLogs: [
        NutritionLog(
          id: 'n1',
          mealType: 'breakfast',
          foodName: 'Yulaf ezmesi',
          calories: 300,
          proteinG: 12,
          carbsG: 50,
          fatG: 6,
          eatenAt: today.add(const Duration(minutes: 1)),
        ),
        NutritionLog(
          id: 'n2',
          mealType: 'breakfast',
          foodName: 'Haşlanmış yumurta, tam buğday ekmeği ve beyaz peynir',
          quantityText: '2 adet',
          calories: 120,
          proteinG: 16,
          eatenAt: today.add(const Duration(minutes: 2)),
        ),
      ],
      workouts: [
        WorkoutLog(
          id: 'k1',
          workoutType: 'kickboxing',
          durationMin: 60,
          caloriesBurned: 540,
          loggedAt: today.add(const Duration(minutes: 3)),
        ),
        WorkoutLog(
          id: 'k2',
          workoutType: 'weights',
          title: 'Üst vücut: göğüs, sırt ve omuz ağırlık antrenmanı',
          durationMin: 45,
          distanceKm: 1.5,
          caloriesBurned: 1310,
          loggedAt: AppDates.addDays(today, -8).add(const Duration(hours: 19)),
        ),
      ],
      metrics: [
        for (var i = 0; i < 7; i++)
          DailyHealthMetric(
            day: AppDates.addDays(today, -i),
            steps: 12000 - i * 900,
            sleepMinutes: 430,
            activeKcal: 400,
          ),
      ],
    );
    routines = FakeRoutinesRepository(
      routines: const [
        Routine(id: 'r1', title: 'Antrenman', category: 'spor'),
      ],
    );
  }

  setUp(() {
    today = AppDates.startOfDay(DateTime.now());
    seed();
  });

  late FakeSettingsRepository settingsRepo;
  late FakeWaterRepository water;

  UserSettings baseSettings() => const UserSettings.defaults().copyWith(
        startWeightKg: 84.5,
        targetWeightKg: 78,
        heightCm: 180,
        birthYear: today.year - 35,
        sex: 'male',
        weeklyRate: FatLossRate.half,
      );

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    double textScale = 1.0,
    HealthSnapshot? snapshot,
    UserSettings? settings,
    HealthSegment segment = HealthSegment.today,
  }) async {
    settingsRepo = FakeSettingsRepository(settings: settings ?? baseSettings());
    water = FakeWaterRepository();
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        waterRepositoryProvider.overrideWithValue(water),
        weeklyCheckinRepositoryProvider
            .overrideWithValue(FakeWeeklyCheckinRepository()),
        healthRepositoryProvider.overrideWithValue(health),
        routinesRepositoryProvider.overrideWithValue(routines),
        kokpitRepositoryProvider
            .overrideWithValue(FakeKokpitRepository(health: health)),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        appleHealthConsentStoreProvider.overrideWithValue(
          MemoryAppleHealthConsentStore(grantAll: true),
        ),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(
            snapshot ??
                HealthSnapshot(
                  status: HealthStatus.ok,
                  steps: 8240,
                  activeKcal: 430,
                  sleepMinutes: 432,
                  readAt: today.add(const Duration(hours: 15, minutes: 34)),
                ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Kokpit açıkmış gibi: beslenme özeti dinleniyor ki tazelenme görülsün.
    container.listen(todayNutritionProvider, (_, __) {});
    container.read(healthSegmentProvider.notifier).state = segment;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: HealthScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) => tapVisible(tester, find.text('Kaydet'));

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('Bugün dolu veriyle 375x667 ve 1.3 metin ölçeğinde taşmadan çizilir',
      (tester) async {
    await pumpScreen(tester, textScale: 1.3);

    expect(find.text('Sağlık'), findsOneWidget);
    for (final s in HealthSegment.values) {
      expect(find.byKey(Key('health-segment-${s.name}')), findsOneWidget);
    }
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('Vücut'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);

    expect(find.byKey(const Key('streak-strip')), findsOneWidget);
    expect(find.byKey(const Key('streak-chip-steps')), findsOneWidget);
    expect(find.byKey(const Key('streak-chip-logging')), findsOneWidget);
    expect(find.byKey(const Key('streak-chip-deficit')), findsOneWidget);
    expect(find.byKey(const Key('streak-chip-week')), findsOneWidget);

    expect(text(tester, 'day-eaten'), '420 kcal');
    expect(text(tester, 'day-protein'), startsWith('28 / '));
    expect(find.byKey(const Key('day-empty')), findsNothing);
    expect(find.byKey(const Key('day-gap-line')), findsOneWidget);
    expect(find.byKey(const Key('day-water')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('week-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-steps')), findsOneWidget);
    expect(find.byKey(const Key('move-sleep')), findsOneWidget);
    expect(find.byKey(const Key('move-workouts')), findsOneWidget);
    expect(find.byKey(const Key('move-weekly')), findsOneWidget);
    expect(text(tester, 'week-avg-steps'), '9.300');
    expect(text(tester, 'week-avg-sleep'), '7 sa 10 dk');
    expect(find.byKey(const Key('health-source-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('öğün yokken gün kartı boş durumu gösterir, eksik satırı gizli',
      (tester) async {
    health = FakeHealthRepository();
    routines = FakeRoutinesRepository();
    await pumpScreen(
      tester,
      textScale: 1.3,
      snapshot: const HealthSnapshot(status: HealthStatus.unavailable),
    );
    expect(text(tester, 'day-eaten'), '0 kcal');
    expect(find.byKey(const Key('day-empty')), findsOneWidget);
    expect(find.byKey(const Key('day-gap-line')), findsNothing);
    // Sağlık kaynağı yok: Adım serisi gösterilmez.
    expect(find.byKey(const Key('streak-chip-steps')), findsNothing);
    expect(find.byKey(const Key('streak-chip-logging')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seri şeridi VoiceOver etiketleri ve bugün durumu taşır',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'Adım serisi \d+ gün, bugün (tamam|bekleniyor)')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Kayıt serisi \d+ gün, bugün tamam')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Haftalık kalori açığı ')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('seri şeridine dokununca Seri detayı açılır', (tester) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.byKey(const Key('streak-strip')));
    expect(find.byType(StreakDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('streak-card-logging')), findsOneWidget);
    expect(find.byKey(const Key('streak-card-deficit')), findsOneWidget);
    await tester.scrollUntilVisible(find.text(streakGraceNote), 200);
    expect(find.byKey(const Key('streak-weeks-current')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gün kartı ve hareket kutuları Haftalık detayı ölçüsüyle açar',
      (tester) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.byKey(const Key('day-eaten')));
    expect(find.byType(WeeklyDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('weekly-metric-kcal')))
          .selected,
      isTrue,
    );
    expect(text(tester, 'weekly-headline'), 'Ortalama 420 kcal');

    await tapVisible(tester, find.byKey(const Key('weekly-metric-protein')));
    expect(text(tester, 'weekly-headline'), 'Ortalama 28 g');
    await tapVisible(tester, find.text('30 gün'));
    expect(find.text('son 30 gün'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('move-steps')));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('weekly-metric-steps')))
          .selected,
      isTrue,
    );
    // Bugün HealthKit okuması (8.240) depoya yazılır; diğer 6 gün 11.100…6.600.
    expect(text(tester, 'weekly-headline'), 'Ortalama 8.763');
  });

  testWidgets('su satırı + ve − ile kayıt ekler ve geri alır', (tester) async {
    await pumpScreen(tester);
    expect(text(tester, 'day-water'), startsWith('0 ml'));
    await tapVisible(tester, find.byKey(const Key('day-water-plus')));
    expect(text(tester, 'day-water'), startsWith('250 ml'));
    await tapVisible(tester, find.byKey(const Key('day-water-minus')));
    expect(text(tester, 'day-water'), startsWith('0 ml'));
  });

  testWidgets('segment düğmesi Plan görünümüne geçer', (tester) async {
    final container = await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('health-segment-plan')));
    await tester.pumpAndSettle();
    expect(container.read(healthSegmentProvider), HealthSegment.plan);
    expect(find.byKey(const Key('plan-goal')), findsOneWidget);
    expect(find.byKey(const Key('streak-strip')), findsNothing);
  });

  testWidgets('öğün ekle düğmesi en az 44 pt', (tester) async {
    await pumpScreen(tester);
    final size = tester.getSize(find.byKey(const Key('meal-add')));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('kaynak sorunluyken tek satır uyarı görünür', (tester) async {
    await pumpScreen(
      tester,
      snapshot: const HealthSnapshot(status: HealthStatus.denied),
    );
    expect(find.byKey(const Key('health-source-banner')), findsOneWidget);
    expect(find.text('Yeniden bağlan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Antrenman kutusundaki Ekle antrenmanı depoya yazar',
      (tester) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.byKey(const Key('move-workout-add')));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Koşu'));
    await tester.enterText(find.byKey(const Key('workout-duration')), '30');
    await save(tester);
    expect(health.workouts.last.workoutType, 'running');
    expect(health.workouts.last.durationMin, 30);
  });

  group('Plan', () {
    testWidgets('dört tempo, rozetler ve hedefler 1.3 ölçekte taşmadan',
        (tester) async {
      await pumpScreen(tester,
          textScale: 1.3, segment: HealthSegment.plan);
      expect(find.byKey(const Key('plan-goal')), findsOneWidget);
      expect(text(tester, 'plan-goal-weights'), '83,6 → 78 kg');
      expect(find.byKey(const Key('plan-source')), findsOneWidget);
      expect(find.byKey(const Key('plan-targets')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('plan-tempo')));
      await tester.pumpAndSettle();
      for (final r in FatLossRate.values) {
        expect(find.byKey(Key('plan-rate-${r.name}')), findsOneWidget);
        expect(find.byKey(Key('plan-rate-${r.name}-sub')), findsOneWidget);
      }
      expect(find.text('Klasik (kg×26)'), findsWidgets);
      expect(find.text('0,50 kg/hafta'), findsWidgets);
      expect(find.text('0,75 kg/hafta'), findsWidgets);
      expect(find.text('1 kg/hafta'), findsWidgets);
      expect(find.text('0,25 kg/hafta'), findsNothing);
      expect(find.byKey(const Key('plan-rate-half-badge')), findsOneWidget);
      expect(find.byKey(const Key('plan-rate-warning')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tempo değişince ayara yazılır; 1 kg uyarı gösterir',
        (tester) async {
      await pumpScreen(tester, segment: HealthSegment.plan);
      await tapVisible(tester, find.byKey(const Key('plan-rate-one')));
      expect(settingsRepo.settings!.weeklyRate, FatLossRate.one);
      expect(find.byKey(const Key('plan-rate-warning')), findsOneWidget);
      expect(find.text(FatLossRate.one.warning!), findsWidgets);

      await tapVisible(tester, find.byKey(const Key('plan-rate-threeQuarter')));
      expect(settingsRepo.settings!.weeklyRate, FatLossRate.threeQuarter);
      expect(find.byKey(const Key('plan-rate-warning')), findsNothing);
    });

    testWidgets('kilitli plan: tempo gizli, koruma metni', (tester) async {
      await pumpScreen(
        tester,
        segment: HealthSegment.plan,
        settings: baseSettings().copyWith(birthYear: today.year - 16),
      );
      expect(find.byKey(const Key('plan-tempo')), findsNothing);
      expect(find.text(SafeTargets.lockedMessage), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tabana takılınca dürüst satır görünür', (tester) async {
      await pumpScreen(
        tester,
        segment: HealthSegment.plan,
        settings: baseSettings().copyWith(
          weeklyRate: FatLossRate.one,
          expenditureKcalManual: 1800,
        ),
      );
      expect(find.text(SafeTargets.clampedMessage), findsOneWidget);
      expect(
        find.textContaining('tabana takıldı'),
        findsWidgets,
      );
    });

    testWidgets('Neden ve Rehber açılır; menü ve magnezyum metni',
        (tester) async {
      await pumpScreen(tester, segment: HealthSegment.plan);
      await tapVisible(tester, find.byKey(const Key('plan-why-toggle')));
      expect(find.byKey(const Key('plan-why-expenditure')), findsOneWidget);
      expect(find.byKey(const Key('plan-menu')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('plan-guide-toggle')));
      expect(find.byKey(const Key('plan-equivalents')), findsOneWidget);
      expect(find.byKey(const Key('plan-menu')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('supplement-magnesium')));
      expect(
        find.textContaining(
            'Takviye genelde 200–350 mg; takviyeden günde 350 mg\'ı aşma.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ölçü günü ayarı kaydedilir', (tester) async {
      await pumpScreen(tester, segment: HealthSegment.plan);
      await tapVisible(tester, find.byKey(const Key('plan-checkin-weekday-3')));
      expect(settingsRepo.settings!.checkinWeekday, 3);
      await tapVisible(tester, find.text('Aylık'));
      expect(settingsRepo.settings!.checkinCadence.name, 'monthly');
      expect(find.byKey(const Key('plan-checkin-monthday')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('plan-checkin-reminder')));
      expect(settingsRepo.settings!.checkinReminder, isFalse);
    });
  });
}
