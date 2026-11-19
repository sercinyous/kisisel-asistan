import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/demo/demo_health_extras.dart';
import 'package:kisisel_asistan/features/health/data/water_repository.dart';
import 'package:kisisel_asistan/features/reports/data/weekly_checkin_repository.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/widgets/bento.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/health_widgets.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/weight_card.dart';
import 'package:kisisel_asistan/features/health/presentation/weight_detail_screen.dart';
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

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    double textScale = 1.0,
    HealthSnapshot? snapshot,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        waterRepositoryProvider.overrideWithValue(FakeWaterRepository()),
        weeklyCheckinRepositoryProvider
            .overrideWithValue(FakeWeeklyCheckinRepository()),
        healthRepositoryProvider.overrideWithValue(health),
        routinesRepositoryProvider.overrideWithValue(routines),
        kokpitRepositoryProvider
            .overrideWithValue(FakeKokpitRepository(health: health)),
        settingsRepositoryProvider.overrideWithValue(
          FakeSettingsRepository(
            settings: const UserSettings.defaults()
                .copyWith(startWeightKg: 84.5, targetWeightKg: 78),
          ),
        ),
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

  Future<void> segment(WidgetTester tester, HealthSegment value) async {
    await tester.tap(find.byKey(Key('health-segment-${value.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> expandMeal(WidgetTester tester, String mealType) =>
      tapVisible(tester, find.byKey(ValueKey('meal-group-$mealType')));

  Future<void> openWeightDetail(WidgetTester tester) async {
    await tapVisible(tester, find.byType(WeightCard));
    expect(find.byType(WeightDetailScreen), findsOneWidget);
  }

  String bigValue(WidgetTester tester, String key) =>
      tester.widget<HealthBigValue>(find.byKey(Key(key))).value;

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('dolu veriyle 375x667 ve 1.3 metin ölçeğinde taşmadan çizilir',
      (tester) async {
    await pumpScreen(tester, textScale: 1.3);

    // Özet: kilo, enerji, bu hafta.
    expect(find.text('Sağlık'), findsOneWidget);
    expect(find.text('Özet'), findsOneWidget);
    expect(find.text('Beslenme'), findsOneWidget);
    expect(find.text('Hareket'), findsOneWidget);
    expect(bigValue(tester, 'weight-latest'), '83,6');
    expect(text(tester, 'weight-last-label'), '83,6');
    expect(find.text('Hedef 78 kg'), findsOneWidget);
    expect(text(tester, 'weight-summary'), contains('hedefe'));
    expect(find.text('Bu hafta'), findsOneWidget);
    expect(text(tester, 'week-steps'), '9.300');
    expect(text(tester, 'week-sleep'), '7 sa 10 dk');
    expect(text(tester, 'week-workouts'), '1 / 7');
    // Kaynak sorunsuz: uyarı yok, kaynak kartı da yok.
    expect(find.byKey(const Key('health-source-banner')), findsNothing);
    expect(find.text('HealthKit'), findsNothing);
    expect(tester.takeException(), isNull);

    await segment(tester, HealthSegment.nutrition);
    expect(bigValue(tester, 'nutrition-day-calories'), '420');
    expect(find.text('Kahvaltı · 420 kcal'), findsOneWidget);
    expect(find.text('Yulaf ezmesi'), findsNothing);
    await expandMeal(tester, 'breakfast');
    expect(find.text('Yulaf ezmesi'), findsOneWidget);
    expect(find.text('Kalori'), findsOneWidget);
    await tester.ensureVisible(find.text('Kalori'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await segment(tester, HealthSegment.movement);
    expect(find.text('Kickboks'), findsOneWidget);
    expect(find.text('Uyku'), findsOneWidget);
    await tester.ensureVisible(find.text('Kickboks'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('öğün ekle düğmesi en az 44 pt', (tester) async {
    await pumpScreen(tester);
    await segment(tester, HealthSegment.nutrition);
    final size = tester.getSize(find.byKey(const Key('meal-add')));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('healthSegmentProvider Beslenme görünümünü doğrudan açar',
      (tester) async {
    final container = await pumpScreen(tester);
    container.read(healthSegmentProvider.notifier).state =
        HealthSegment.nutrition;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('meal-group-breakfast')), findsOneWidget);
    expect(find.byType(WeightCard), findsNothing);
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

  testWidgets('haftalık antrenman ve adım kartları plan ve ortalamayı gösterir',
      (tester) async {
    await pumpScreen(tester);
    await segment(tester, HealthSegment.movement);

    // Bu hafta: bugünkü kickboks sayılır; 8 gün önceki sayılmaz. Plan 7 gün.
    expect(bigValue(tester, 'workout-week-count'), '1');
    expect(find.textContaining('/ 7 bu hafta', findRichText: true), findsOneWidget);
    // 12000, 11100, ... 6600 ortalaması.
    expect(bigValue(tester, 'steps-average'), '9.300');
    // Yedi gün de 430 dk uyku: 7 sa 10 dk.
    expect(bigValue(tester, 'sleep-average'), '7 sa 10 dk');

    await segment(tester, HealthSegment.nutrition);
    // Yalnızca bugünün öğünü var (300 + 120); öğünsüz günler ortalamayı çekmez.
    expect(bigValue(tester, 'calories-average'), '420');
  });

  testWidgets('Bu hafta satırları trend ekranını ve Hareket görünümünü açar',
      (tester) async {
    await pumpScreen(tester);

    for (final (key, metric) in [
      ('week-row-steps', TrendMetric.steps),
      ('week-row-sleep', TrendMetric.sleep),
    ]) {
      await tapVisible(tester, find.byKey(Key(key)));
      expect(find.byType(TrendScreen), findsOneWidget, reason: key);
      expect(
        tester
            .widget<SegmentedButton<TrendMetric>>(
              find.byKey(const Key('trend-metric')),
            )
            .selected,
        {metric},
        reason: key,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tapVisible(tester, find.byKey(const Key('week-row-workouts')));
    expect(find.byKey(const Key('workout-week-count')), findsOneWidget);
  });

  testWidgets('Adım, Uyku ve Kalori kartlarına dokununca ilgili trend açılır',
      (tester) async {
    await pumpScreen(tester);

    for (final (label, metric, view) in [
      ('Adım', TrendMetric.steps, HealthSegment.movement),
      ('Uyku', TrendMetric.sleep, HealthSegment.movement),
      ('Kalori', TrendMetric.calories, HealthSegment.nutrition),
    ]) {
      await segment(tester, view);
      await tapVisible(tester, find.text(label));
      expect(find.byType(TrendScreen), findsOneWidget, reason: label);
      expect(
        tester
            .widget<SegmentedButton<TrendMetric>>(
              find.byKey(const Key('trend-metric')),
            )
            .selected,
        {metric},
        reason: label,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TrendScreen), findsNothing);

      // Grafik alanı da kartın parçasıdır: dokunuşu yutmamalı (fl_chart kendi
      // dokunma tanıyıcısını ekler; kapatılmazsa Trend açılmaz).
      final chart = find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(BentoCard)),
        matching: find.byType(BarChart),
      );
      expect(chart, findsOneWidget, reason: '$label grafiği');
      await tapVisible(tester, chart);
      expect(find.byType(TrendScreen), findsOneWidget, reason: '$label grafik');
      expect(
        tester
            .widget<SegmentedButton<TrendMetric>>(
              find.byKey(const Key('trend-metric')),
            )
            .selected,
        {metric},
        reason: '$label grafik',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TrendScreen), findsNothing);
    }
  });

  testWidgets(
      'büyük metinde ortalama değeri tek satır ölçülür: kartlarda ölü boşluk yok',
      (tester) async {
    // "7 sa 22 dk ort." yarım genişlikte sığmaz; değer küçülür, ama içsel
    // yükseklik iki satır ölçerse satır bir satır uzar.
    health.metrics = [
      for (var i = 0; i < 7; i++)
        DailyHealthMetric(
          day: AppDates.addDays(today, -i),
          steps: 9300,
          sleepMinutes: 442,
          activeKcal: 400,
        ),
    ];
    health.nutritionLogs = [
      NutritionLog(
        id: 'big',
        mealType: 'lunch',
        foodName: 'Büyük öğün',
        calories: 1824,
        proteinG: 100,
        eatenAt: today.add(const Duration(minutes: 5)),
      ),
    ];
    await pumpScreen(tester, textScale: 1.3);
    await segment(tester, HealthSegment.movement);

    expect(bigValue(tester, 'sleep-average'), '7 sa 22 dk');
    for (final label in ['Adım', 'Uyku']) {
      final card = find.ancestor(
        of: find.text(label),
        matching: find.byType(BentoCard),
      );
      // Tek satırlı değerle ~186; iki satır ölçümüyle ~227 çıkıyordu.
      expect(tester.getSize(card).height, lessThan(196), reason: label);
    }
    await segment(tester, HealthSegment.nutrition);
    expect(bigValue(tester, 'calories-average'), '1.824');
    expect(tester.takeException(), isNull);
  });

  testWidgets('veri yokken her bölüm boş durumunu gösterir', (tester) async {
    health = FakeHealthRepository();
    routines = FakeRoutinesRepository();
    await pumpScreen(
      tester,
      textScale: 1.3,
      snapshot: const HealthSnapshot(status: HealthStatus.unavailable),
    );

    expect(
      find.text('Son 30 günde kilo ölçümü yok. İlk ölçümünü ekle.'),
      findsOneWidget,
    );
    // Bu cihazda kaynak yok: sorun sayılmaz, uyarı çıkmaz.
    expect(find.byKey(const Key('health-source-banner')), findsNothing);
    expect(tester.takeException(), isNull);

    await segment(tester, HealthSegment.nutrition);
    expect(find.text('Son 7 günde öğün kaydı yok.'), findsOneWidget);
    expect(find.text('Henüz kayıt yok'), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await segment(tester, HealthSegment.movement);
    expect(find.text('Planlı antrenman yok.'), findsOneWidget);
    expect(find.text('Son 7 günde adım verisi yok.'), findsOneWidget);
    expect(find.text('Son 7 günde uyku verisi yok.'), findsOneWidget);
    expect(find.text('Son 30 günde antrenman kaydı yok.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('okuma hatasında bölümler hata gösterir ve tekrar dene yükler',
      (tester) async {
    health.fetchError = Exception('ağ yok');
    await pumpScreen(tester, textScale: 1.3);

    expect(find.text('Kilo ölçümleri yüklenemedi.'), findsOneWidget);

    await segment(tester, HealthSegment.movement);
    expect(find.text('Antrenman planı yüklenemedi.'), findsOneWidget);
    expect(find.text('Adım verisi yüklenemedi.'), findsOneWidget);
    expect(find.text('Uyku verisi yüklenemedi.'), findsOneWidget);
    expect(find.text('Antrenmanlar yüklenemedi.'), findsOneWidget);

    await segment(tester, HealthSegment.nutrition);
    expect(find.text('Kalori verisi yüklenemedi.'), findsOneWidget);
    expect(find.text('Öğünler yüklenemedi.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    health.fetchError = null;
    await tapVisible(
      tester,
      find.descendant(
        of: find.ancestor(
          of: find.text('Öğünler yüklenemedi.'),
          matching: find.byType(Row),
        ),
        matching: find.text('Tekrar dene'),
      ),
    );
    expect(find.text('Öğünler yüklenemedi.'), findsNothing);
    await expandMeal(tester, 'breakfast');
    expect(find.text('Yulaf ezmesi'), findsOneWidget);
  });

  testWidgets('kilo eklemek depoyu çağırır ve grafik yeni son değeri gösterir',
      (tester) async {
    await pumpScreen(tester);
    await openWeightDetail(tester);

    await tapVisible(tester, find.text('Kilo ekle'));
    await tester.enterText(find.byKey(const Key('weight-kg')), '82,9');
    await save(tester);

    expect(health.weights, hasLength(4));
    expect(health.weights.last.weightKg, 82.9);
    expect(find.byKey(const Key('weight-kg')), findsNothing);
    expect(bigValue(tester, 'weight-latest'), '82,9');
    expect(text(tester, 'weight-last-label'), '82,9');

    // Özet kartı da yeni değeri gösterir.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(bigValue(tester, 'weight-latest'), '82,9');
  });

  testWidgets('sınır dışı kilo doğrulama iletisi verir ve kaydedilmez',
      (tester) async {
    await pumpScreen(tester);
    await openWeightDetail(tester);

    await tapVisible(tester, find.text('Kilo ekle'));
    await tester.enterText(find.byKey(const Key('weight-kg')), '20');
    await save(tester);
    expect(find.text('30 ile 250 arasında olmalı.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weight-kg')), '');
    await save(tester);
    expect(find.text('Bu alan boş olamaz.'), findsOneWidget);
    expect(health.weights, hasLength(3));
  });

  testWidgets('öğün eklemek depoya doğru değerleri yazar ve Kokpit özetini tazeler',
      (tester) async {
    final container = await pumpScreen(tester);
    await segment(tester, HealthSegment.nutrition);
    expect(container.read(todayNutritionProvider).requireValue.calories, 420);

    await tapVisible(tester, find.text('Öğün ekle'));
    await tapVisible(tester, find.text('Elle gir'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Öğle'));
    await tester.enterText(find.byKey(const Key('meal-name')), 'Tavuk göğsü');
    await tester.enterText(find.byKey(const Key('meal-quantity')), '150 g');
    await tester.enterText(find.byKey(const Key('meal-calories')), '250');
    await tester.enterText(find.byKey(const Key('meal-protein')), '45,5');
    await tester.enterText(find.byKey(const Key('meal-fat')), '5');
    await save(tester);

    final created = health.nutritionLogs.last;
    expect(created.mealType, 'lunch');
    expect(created.foodName, 'Tavuk göğsü');
    expect(created.quantityText, '150 g');
    expect(created.calories, 250);
    expect(created.proteinG, 45.5);
    expect(created.carbsG, 0);
    expect(created.fatG, 5);
    expect(AppDates.startOfDay(created.eatenAt), today);

    await expandMeal(tester, 'lunch');
    expect(find.text('Tavuk göğsü'), findsOneWidget);
    final summary = container.read(todayNutritionProvider).requireValue;
    expect(summary.calories, 670);
    expect(summary.entryCount, 3);
    // Kalori kartı da yeni toplamı gösterir (420 + 250).
    expect(bigValue(tester, 'calories-average'), '670');
  });

  testWidgets('öğün düzenlemek aynı kaydı günceller ve Kokpit özetini tazeler',
      (tester) async {
    final container = await pumpScreen(tester);
    await segment(tester, HealthSegment.nutrition);
    await expandMeal(tester, 'breakfast');

    await tapVisible(tester, find.text('Yulaf ezmesi'));
    expect(find.text('Öğünü düzenle'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('meal-calories')), '350');
    await save(tester);

    expect(health.nutritionLogs, hasLength(2));
    final updated = health.nutritionLogs.firstWhere((l) => l.id == 'n1');
    expect(updated.calories, 350);
    expect(updated.mealType, 'breakfast');
    expect(updated.foodName, 'Yulaf ezmesi');
    expect(updated.proteinG, 12);
    expect(updated.carbsG, 50);
    expect(updated.eatenAt, today.add(const Duration(minutes: 1)));
    expect(container.read(todayNutritionProvider).requireValue.calories, 470);
  });

  testWidgets('öğün silmek onaydan sonra depodan kaldırır ve özeti tazeler',
      (tester) async {
    final container = await pumpScreen(tester);
    await segment(tester, HealthSegment.nutrition);
    await expandMeal(tester, 'breakfast');

    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('meal-n1')),
        matching: find.byTooltip('Seçenekler'),
      ),
    );
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Kayıt silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sil'));
    await tester.pumpAndSettle();

    expect(health.deletedIds, ['n1']);
    expect(find.text('Yulaf ezmesi'), findsNothing);
    expect(container.read(todayNutritionProvider).requireValue.calories, 120);
    expect(bigValue(tester, 'calories-average'), '120');
  });

  testWidgets('öğün formu boş adı ve sınır dışı değerleri reddeder',
      (tester) async {
    await pumpScreen(tester);
    await segment(tester, HealthSegment.nutrition);

    await tapVisible(tester, find.text('Öğün ekle'));
    await tapVisible(tester, find.text('Elle gir'));
    await tester.enterText(find.byKey(const Key('meal-calories')), '-5');
    await tester.enterText(find.byKey(const Key('meal-protein')), '10000');
    await tester.enterText(find.byKey(const Key('meal-carbs')), 'çok');
    await save(tester);

    expect(find.text('Ad boş olamaz.'), findsOneWidget);
    expect(find.text('0 ile 99999,9 arasında olmalı.'), findsOneWidget);
    expect(find.text('0 ile 9999,9 arasında olmalı.'), findsOneWidget);
    expect(find.text('Geçerli bir sayı gir.'), findsOneWidget);
    expect(health.nutritionLogs, hasLength(2));
  });

  testWidgets('antrenman eklemek depoya yazar ve haftalık sayıyı artırır',
      (tester) async {
    await pumpScreen(tester);
    await segment(tester, HealthSegment.movement);

    await tapVisible(tester, find.text('Ekle'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Koşu'));
    await tester.enterText(find.byKey(const Key('workout-title')), 'Sahil koşusu');
    await tester.enterText(find.byKey(const Key('workout-duration')), '30');
    await tester.enterText(find.byKey(const Key('workout-distance')), '5,2');
    await tester.enterText(find.byKey(const Key('workout-calories')), '320');
    await save(tester);

    final created = health.workouts.last;
    expect(created.workoutType, 'running');
    expect(created.title, 'Sahil koşusu');
    expect(created.durationMin, 30);
    expect(created.distanceKm, 5.2);
    expect(created.caloriesBurned, 320);
    expect(created.notes, isNull);
    expect(AppDates.startOfDay(created.loggedAt), today);

    expect(find.text('Sahil koşusu'), findsOneWidget);
    expect(bigValue(tester, 'workout-week-count'), '2');
  });

  testWidgets('antrenman formu sınır dışı süre ve mesafeyi reddeder',
      (tester) async {
    await pumpScreen(tester);
    await segment(tester, HealthSegment.movement);

    await tapVisible(tester, find.text('Ekle'));
    await tester.enterText(find.byKey(const Key('workout-duration')), '700');
    await tester.enterText(find.byKey(const Key('workout-distance')), '10000');
    await save(tester);

    expect(find.text('1 ile 600 arasında olmalı.'), findsOneWidget);
    expect(find.text('0 ile 9999,99 arasında olmalı.'), findsOneWidget);
    expect(health.workouts, hasLength(2));
  });

  testWidgets('yazma hatasında form açık kalır ve hata gösterir', (tester) async {
    await pumpScreen(tester);
    await openWeightDetail(tester);
    health.writeError = Exception('ağ yok');

    await tapVisible(tester, find.text('Kilo ekle'));
    await tester.enterText(find.byKey(const Key('weight-kg')), '82,9');
    await save(tester);

    expect(
      find.text('Kaydedilemedi. Bağlantını kontrol edip tekrar dene.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('weight-kg')), findsOneWidget);
    expect(health.weights, hasLength(3));
  });
}
