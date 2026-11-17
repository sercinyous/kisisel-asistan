import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_card.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_detail_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/health_widgets.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/weight_card.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

// 17 Kasım 2026 Salı. Profil: 180 cm, 1996, erkek (yaş 30); 80 kg ile bazal
// 10·80 + 6,25·180 − 5·30 + 5 = 1780 kcal/gün (12:00'de 890).
final _mon = DateTime(2026, 11, 16);
final _tue = DateTime(2026, 11, 17);
final _wed = DateTime(2026, 11, 18);
final _thu = DateTime(2026, 11, 19);
DateTime _now = DateTime(2026, 11, 17, 12);

final UserSettings _complete = const UserSettings.defaults()
    .copyWith(startWeightKg: 84.5, heightCm: 180, birthYear: 1996, sex: 'male');

void main() {
  late FakeHealthRepository health;
  late FakeSettingsRepository settings;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    _now = DateTime(2026, 11, 17, 12);
    settings = FakeSettingsRepository(settings: _complete);
    health = FakeHealthRepository(
      weights: [
        WeightEntry(
          id: 'w1',
          weightKg: 80,
          loggedAt: DateTime(2026, 11, 1, 8),
        ),
      ],
    );
  });

  DailyNutritionTotal meals(DateTime day, double kcal, {int entries = 2}) =>
      DailyNutritionTotal(day: day, calories: kcal, entryCount: entries);

  DailyHealthMetric active(DateTime day, int kcal) =>
      DailyHealthMetric(day: day, activeKcal: kcal);

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        kokpitRepositoryProvider
            .overrideWithValue(FakeKokpitRepository(health: health)),
        settingsRepositoryProvider.overrideWithValue(settings),
        trendClockProvider.overrideWithValue(() => _now),
        // Profil düğmesi Ayarlar'ı açar.
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(const HealthSnapshot(status: HealthStatus.denied)),
        ),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  void phoneView(WidgetTester tester, double textScale) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<ProviderContainer> pumpCard(
    WidgetTester tester, {
    double textScale = 1.0,
  }) async {
    phoneView(tester, textScale);
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.page),
              child: EnergyCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<ProviderContainer> pumpDetail(
    WidgetTester tester, {
    double textScale = 1.0,
  }) async {
    phoneView(tester, textScale);
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const EnergyDetailScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  String bigValue(WidgetTester tester, String key) =>
      tester.widget<HealthBigValue>(find.byKey(Key(key))).value;

  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('energy-next'))).onPressed !=
      null;

  group('EnergyCard yorumları', () {
    // 12:00'de bazal 890 + aktif 520 = yakılan 1410; net = alınan − 1410.
    Future<void> pumpVerdict(WidgetTester tester, double intake) async {
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, intake)];
      await pumpCard(tester);
    }

    testWidgets('yağ yaktın: net −410, bugün için "Şu ana kadar"', (tester) async {
      await pumpVerdict(tester, 1000);

      expect(find.text('Enerji dengesi'), findsOneWidget);
      expect(find.text('Şu ana kadar'), findsOneWidget);
      expect(text(tester, 'energy-intake'), '1.000');
      expect(text(tester, 'energy-burned'), '1.410');
      expect(text(tester, 'energy-net'), '−410');
      expect(find.text('Bugün yağ yaktın'), findsOneWidget);
      expect(find.text('Yakılan = bazal 890 + aktif 520 kcal'), findsOneWidget);
      expect(find.byKey(const Key('energy-compensation')), findsNothing);
      expect(find.byKey(const Key('energy-active-missing')), findsNothing);
    });

    testWidgets('yerinde saydın: net −10', (tester) async {
      await pumpVerdict(tester, 1400);
      expect(text(tester, 'energy-net'), '−10');
      expect(find.text('Bugün yerinde saydın, yağ almadın'), findsOneWidget);
    });

    testWidgets('biraz kaçırdın: net +300, telafi 62 dk ya da yarın 300 kcal',
        (tester) async {
      await pumpVerdict(tester, 1710);
      expect(text(tester, 'energy-net'), '+300');
      expect(
        find.text('Bugün biraz kaçırdın, telafi edebilirsin'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Telafi: yaklaşık 62 dk tempolu yürüyüş ya da yarın 300 kcal daha az ye',
        ),
        findsOneWidget,
      );
    });

    testWidgets('fazla geçti: net +590, telafi satırı yok', (tester) async {
      await pumpVerdict(tester, 2000);
      expect(text(tester, 'energy-net'), '+590');
      expect(
        find.text('Bugün fazla geçti; bir günle bozulmaz, yarın toparla'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('energy-compensation')), findsNothing);
    });

    testWidgets('çok yüksek açık: uyarı, övgü yok', (tester) async {
      health
        ..metrics = [active(_tue, 1200)]
        ..nutrition = [meals(_tue, 300)];
      await pumpCard(tester);

      expect(text(tester, 'energy-net'), '−1.790');
      expect(
        find.text('Çok yüksek kalori açığı: yeterince yediğinden emin ol'),
        findsOneWidget,
      );
      expect(find.textContaining('yaktın'), findsNothing);
      expect(find.textContaining('yağ'), findsNothing);
    });

    testWidgets('öğün yoksa yorum yok: "Henüz öğün girilmedi", net boş',
        (tester) async {
      health.metrics = [active(_tue, 520)];
      await pumpCard(tester);

      expect(find.text('Henüz öğün girilmedi'), findsOneWidget);
      expect(text(tester, 'energy-intake'), '—');
      expect(text(tester, 'energy-net'), '—');
      // Yakılan yine gösterilir.
      expect(text(tester, 'energy-burned'), '1.410');
      expect(find.textContaining('yaktın'), findsNothing);
      expect(find.textContaining('kaçırdın'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aktif kalori verisi yoksa not çıkar ve antrenman yedek olur',
        (tester) async {
      health
        ..nutrition = [meals(_tue, 1500)]
        ..workouts = [
          WorkoutLog(
            id: 'k1',
            workoutType: 'kickboxing',
            caloriesBurned: 300,
            loggedAt: _tue.add(const Duration(hours: 9)),
          ),
        ];
      await pumpCard(tester);

      expect(
        find.text('aktif kalori verisi yok, tahmin bazala dayanıyor'),
        findsOneWidget,
      );
      // 890 + 300 (antrenman yedeği).
      expect(text(tester, 'energy-burned'), '1.190');
      expect(find.text('Yakılan = bazal 890 + aktif 300 kcal'), findsOneWidget);
      expect(text(tester, 'energy-net'), '+310');
    });

    testWidgets('aktif kalori varsa antrenman kalorisi çift sayılmaz',
        (tester) async {
      health
        ..metrics = [active(_tue, 600)]
        ..nutrition = [meals(_tue, 1500)]
        ..workouts = [
          WorkoutLog(
            id: 'k1',
            workoutType: 'kickboxing',
            caloriesBurned: 300,
            loggedAt: _tue.add(const Duration(hours: 9)),
          ),
        ];
      await pumpCard(tester);

      expect(text(tester, 'energy-burned'), '1.490');
      expect(find.byKey(const Key('energy-active-missing')), findsNothing);
    });

    testWidgets('son tartı kullanılır; tartı yoksa başlangıç kilosu',
        (tester) async {
      health
        ..weights = [
          WeightEntry(id: 'w1', weightKg: 80, loggedAt: DateTime(2026, 11, 1)),
          // Bugünden sonraki tartı bugünün bazalını etkilemez.
          WeightEntry(id: 'w2', weightKg: 70, loggedAt: DateTime(2026, 11, 18)),
        ]
        ..nutrition = [meals(_tue, 1000)];
      await pumpCard(tester);
      // 80 kg: 890.
      expect(find.text('Yakılan = bazal 890 + aktif 0 kcal'), findsOneWidget);
    });

    testWidgets('18 yaş altı: yalnızca sayılar, yorum ve telafi yok',
        (tester) async {
      settings = FakeSettingsRepository(
        settings: _complete.copyWith(birthYear: 2012),
      );
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, 1710)];
      await pumpCard(tester);

      expect(text(tester, 'energy-intake'), '1.710');
      expect(find.byKey(const Key('energy-verdict')), findsNothing);
      expect(find.byKey(const Key('energy-compensation')), findsNothing);
      expect(find.textContaining('kaçırdın'), findsNothing);
      expect(find.textContaining('yağ'), findsNothing);
    });

    testWidgets('öğün eklenip sağlayıcılar tazelenince kart güncellenir',
        (tester) async {
      health.metrics = [active(_tue, 520)];
      final container = await pumpCard(tester);
      expect(find.text('Henüz öğün girilmedi'), findsOneWidget);

      health.nutrition = [meals(_tue, 1000)];
      invalidateHealthData(container);
      await tester.pumpAndSettle();

      expect(find.text('Henüz öğün girilmedi'), findsNothing);
      expect(find.text('Bugün yağ yaktın'), findsOneWidget);
    });
  });

  group('EnergyCard profil ve durumlar', () {
    testWidgets('profil eksikse açıklama ve Ayarlar düğmesi görünür',
        (tester) async {
      settings = FakeSettingsRepository();
      health.nutrition = [meals(_tue, 1000)];
      await pumpCard(tester);

      expect(
        find.text('Dengeyi hesaplamak için boy, yaş ve cinsiyet gerekli'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('energy-net')), findsNothing);
      expect(find.text('Şu ana kadar'), findsNothing);

      await tester.tap(find.byKey(const Key('energy-open-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('profil doldurulunca kart hesaplamaya başlar', (tester) async {
      settings = FakeSettingsRepository();
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, 1000)];
      final container = await pumpCard(tester);
      expect(find.byKey(const Key('energy-net')), findsNothing);

      await container.read(userSettingsProvider.notifier).save(_complete);
      await tester.pumpAndSettle();

      expect(text(tester, 'energy-net'), '−410');
      expect(find.text('Bugün yağ yaktın'), findsOneWidget);
    });

    testWidgets('okuma hatasında hata metni ve Tekrar dene çıkar',
        (tester) async {
      health.fetchError = Exception('ağ yok');
      await pumpCard(tester);
      expect(find.text('Enerji dengesi yüklenemedi.'), findsOneWidget);

      health.fetchError = null;
      health.nutrition = [meals(_tue, 1000)];
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(find.text('Enerji dengesi yüklenemedi.'), findsNothing);
      expect(find.byKey(const Key('energy-net')), findsOneWidget);
    });

    testWidgets('gece yarısı geçince bugün, dün ve bazal oranı yeniden hesaplanır',
        (tester) async {
      _now = DateTime(2026, 11, 17, 23, 30);
      health.nutrition = [meals(_tue, 1500)];
      final container = await pumpCard(tester);

      // 1780 · (23:30 / 24:00) = 1742,9; aktif kalori yok.
      expect(text(tester, 'energy-burned'), '1.743');
      expect(find.text('Bugün yağ yaktın'), findsOneWidget);

      // Gece yarısı geçti, uygulama 06:00'da öne geldi.
      _now = DateTime(2026, 11, 18, 6);
      invalidateHealthData(container);
      await tester.pumpAndSettle();

      // Yeni gün: dünün öğünleri sayılmaz, bazal günün dörtte biri.
      expect(find.text('Henüz öğün girilmedi'), findsOneWidget);
      expect(text(tester, 'energy-intake'), '—');
      expect(text(tester, 'energy-burned'), '445');
      expect(find.text('Bugün yağ yaktın'), findsNothing);
    });

    testWidgets('karta dokununca detay ekranı açılır', (tester) async {
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, 1000)];
      await pumpCard(tester);

      await tester.tap(find.byKey(const Key('energy-net')));
      await tester.pumpAndSettle();
      expect(find.byType(EnergyDetailScreen), findsOneWidget);
    });

    testWidgets('profil eksikken kart detaya götürmez', (tester) async {
      settings = FakeSettingsRepository();
      await pumpCard(tester);
      await tester.tap(find.text('Enerji dengesi'));
      await tester.pumpAndSettle();
      expect(find.byType(EnergyDetailScreen), findsNothing);
    });
  });

  group('EnergyCard 375x667, metin ölçeği 1,3', () {
    testWidgets('fazla gün ve aktif kalori notuyla taşmaz', (tester) async {
      health.nutrition = [meals(_tue, 2000)];
      await pumpCard(tester, textScale: 1.3);
      expect(find.byKey(const Key('energy-active-missing')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('biraz kaçırdın + telafi satırıyla taşmaz', (tester) async {
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, 1710)];
      await pumpCard(tester, textScale: 1.3);
      expect(find.byKey(const Key('energy-compensation')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok yüksek açık uyarısı ve büyük sayılarla taşmaz',
        (tester) async {
      health
        ..metrics = [active(_tue, 1200)]
        ..nutrition = [meals(_tue, 300)];
      await pumpCard(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('öğünsüz gün ve profil eksik durumlarında taşmaz',
        (tester) async {
      await pumpCard(tester, textScale: 1.3);
      expect(find.text('Henüz öğün girilmedi'), findsOneWidget);
      expect(tester.takeException(), isNull);

      settings = FakeSettingsRepository();
      await pumpCard(tester, textScale: 1.3);
      expect(find.byKey(const Key('energy-open-settings')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Sağlık sekmesinde', () {
    Future<ProviderContainer> pumpHealth(WidgetTester tester) async {
      phoneView(tester, 1.0);
      final container = makeContainer();
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

    testWidgets('Enerji dengesi kartı Kilo kartının hemen altında durur',
        (tester) async {
      health
        ..metrics = [active(_tue, 520)]
        ..nutrition = [meals(_tue, 1000)];
      await pumpHealth(tester);

      expect(find.byType(EnergyCard), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(EnergyCard)).dy,
        greaterThan(tester.getBottomLeft(find.byType(WeightCard)).dy),
      );
      expect(text(tester, 'energy-net'), '−410');
      expect(tester.takeException(), isNull);
    });
  });

  group('energyDayProvider ve energyRangeProvider', () {
    test('profil eksikse gün null, aralık boş', () async {
      settings = FakeSettingsRepository();
      final container = makeContainer();
      expect(await container.read(energyDayProvider(_tue).future), isNull);
      expect(
        await container.read(energyRangeProvider((from: _mon, to: _tue)).future),
        isEmpty,
      );
    });

    test('her gün için o güne kadarki son tartı; yoksa başlangıç kilosu',
        () async {
      health.weights = [
        WeightEntry(id: 'w1', weightKg: 80, loggedAt: DateTime(2026, 11, 10, 8)),
        WeightEntry(id: 'w2', weightKg: 70, loggedAt: DateTime(2026, 11, 18, 7)),
      ];
      _now = DateTime(2026, 11, 19, 12);
      final container = makeContainer();
      final days = await container
          .read(energyRangeProvider((from: _mon, to: _thu)).future);

      expect(days.map((d) => d.day), [_mon, _tue, _wed, _thu]);
      expect(days[0].basal, 1780); // 80 kg
      expect(days[1].basal, 1780);
      expect(days[2].basal, 1680); // 70 kg (aynı gün sabah tartı)
      expect(days[3].basal, 840); // 70 kg, günün yarısı

      health.weights = [];
      container.invalidate(energyRangeProvider);
      final noWeight = await container
          .read(energyRangeProvider((from: _mon, to: _mon)).future);
      // Başlangıç 84,5 kg: 845 + 1125 − 150 + 5.
      expect(noWeight.single.basal, 1825);
    });

    test('aralık bugünde biter; tamamen gelecek aralık boştur', () async {
      _now = DateTime(2026, 11, 19, 12);
      final container = makeContainer();
      final week = await container.read(
        energyRangeProvider((from: _mon, to: DateTime(2026, 11, 22))).future,
      );
      expect(week, hasLength(4));
      expect(week.last.isToday, isTrue);

      expect(
        await container.read(
          energyRangeProvider(
            (from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 22)),
          ).future,
        ),
        isEmpty,
      );
    });

    test('toplam yalnızca öğünü olan günleri sayar', () async {
      _now = DateTime(2026, 11, 19, 12);
      health
        ..metrics = [active(_mon, 400), active(_tue, 400), active(_thu, 400)]
        ..nutrition = [meals(_mon, 2000), meals(_tue, 2300), meals(_thu, 1000)];
      final container = makeContainer();
      final days = await container
          .read(energyRangeProvider((from: _mon, to: _thu)).future);

      expect(days[2].verdict, EnergyVerdict.noMeals);
      final summary = summarize(days);
      expect(summary.days, 3);
      // −180 + 120 − 290
      expect(summary.sumNet, -350);
    });

    test('okuma hatası sağlayıcıdan iletilir', () async {
      health.fetchError = Exception('ağ yok');
      final container = makeContainer();
      await expectLater(
        container.read(energyDayProvider(_tue).future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('EnergyDetailScreen', () {
    // Per 19 Kas 12:00; hafta 16–22. Pzt −180, Sal +120, Çar öğünsüz,
    // bugün −290 (şu ana kadar): toplam −350, 3 gün.
    void seedWeek() {
      _now = DateTime(2026, 11, 19, 12);
      health
        ..metrics = [active(_mon, 400), active(_tue, 400), active(_thu, 400)]
        ..nutrition = [meals(_mon, 2000), meals(_tue, 2300), meals(_thu, 1000)];
    }

    testWidgets('hafta özeti: N gün üzerinden, toplam net ve tahmini yağ',
        (tester) async {
      seedWeek();
      await pumpDetail(tester);

      expect(text(tester, 'energy-period-label'), '16–22 Kas 2026');
      expect(bigValue(tester, 'energy-sum-net'), '−350');
      expect(text(tester, 'energy-sum-days'), '3 gün üzerinden');
      // −350 / 7700 = −0,045 kg
      expect(find.text('Tahmini yağ: −0,05 kg'), findsOneWidget);
      expect(
        find.text('Bugün şu ana kadarki değerle sayıldı.'),
        findsOneWidget,
      );
      expect(
        find.text('1 gün öğün girilmediği için sayılmadı.'),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Açık'), findsOneWidget);
      expect(find.text('Fazla'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('çok yüksek açık günleri övülmez (kartla aynı uyarı rengi)', () {
      // Pzt ve Sal: bazal 1780 + aktif 400, alınan 880 → net −1300.
      void seedVeryHighDeficit() {
        _now = DateTime(2026, 11, 19, 12);
        health
          ..metrics = [active(_mon, 400), active(_tue, 400)]
          ..nutrition = [meals(_mon, 880), meals(_tue, 880)];
      }

      List<BarChartRodData> rods(WidgetTester tester) => [
            for (final g in tester.widget<BarChart>(find.byType(BarChart))
                .data
                .barGroups)
              g.barRods.first,
          ];

      testWidgets('çubuklar mint değil uyarı renginde, yağ çipi nötr',
          (tester) async {
        seedVeryHighDeficit();
        await pumpDetail(tester);

        final bars = rods(tester);
        expect(bars[0].color, AppColors.warning);
        expect(bars[1].color, AppColors.warning);
        expect(bars[0].color, isNot(AppColors.accent));

        // Çip mint (olumlu) değil; nötr: renk verilmez.
        expect(find.text('Tahmini yağ: −0,34 kg'), findsOneWidget);
        final chip =
            tester.widget<HealthChip>(find.byKey(const Key('energy-fat')));
        expect(chip.color, isNull);
        expect(tester.takeException(), isNull);
      });

      testWidgets('uyarı notu ve açıklayıcı gösterge çıkar', (tester) async {
        seedVeryHighDeficit();
        await pumpDetail(tester);

        expect(
          find.text(
            'Çok yüksek açık günleri var: yeterince yediğinden emin ol.',
          ),
          findsOneWidget,
        );
        expect(find.text('Çok yüksek açık'), findsOneWidget);
      });

      testWidgets('normal açık gün hâlâ mint, uyarı notu yok', (tester) async {
        _now = DateTime(2026, 11, 19, 12);
        health
          ..metrics = [active(_mon, 400)]
          ..nutrition = [meals(_mon, 2000)];
        await pumpDetail(tester);

        expect(rods(tester)[0].color, AppColors.accent);
        final chip =
            tester.widget<HealthChip>(find.byKey(const Key('energy-fat')));
        expect(chip.color, AppColors.accent);
        expect(find.textContaining('Çok yüksek açık'), findsNothing);
      });

      testWidgets('karışık dönem: yalnızca çok yüksek gün uyarı renginde',
          (tester) async {
        _now = DateTime(2026, 11, 19, 12);
        health
          ..metrics = [active(_mon, 400), active(_tue, 400)]
          ..nutrition = [meals(_mon, 880), meals(_tue, 2000)];
        await pumpDetail(tester);

        final bars = rods(tester);
        expect(bars[0].color, AppColors.warning, reason: 'net −1300');
        expect(bars[1].color, AppColors.accent, reason: 'net −180');
        expect(find.text('Çok yüksek açık'), findsOneWidget);
      });
    });

    testWidgets('anahtar çizgi görünümüne ve geri geçer', (tester) async {
      seedWeek();
      await pumpDetail(tester);

      await tapText(tester, 'Alınan / Yakılan');
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
      expect(find.text('Alınan'), findsOneWidget);
      expect(find.text('Yakılan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Net');
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('önceki döneme gidilir, sonraki geçerli dönemde pasiftir',
        (tester) async {
      seedWeek();
      await pumpDetail(tester);
      expect(nextEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('energy-prev')));
      await tester.pumpAndSettle();
      expect(text(tester, 'energy-period-label'), '9–15 Kas 2026');
      expect(nextEnabled(tester), isTrue);
      // O haftada hiç öğün yok: boş durum, sahte yüzde ya da övgü yok.
      expect(find.text('Bu dönemde öğün girilmiş gün yok'), findsOneWidget);
      expect(find.byKey(const Key('energy-sum-net')), findsNothing);
      expect(find.byKey(const Key('energy-fat')), findsNothing);

      await tester.tap(find.byKey(const Key('energy-next')));
      await tester.pumpAndSettle();
      expect(text(tester, 'energy-period-label'), '16–22 Kas 2026');
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('ay görünümü kasım ayının tüm günlerini kapsar', (tester) async {
      seedWeek();
      health.nutrition = [
        ...health.nutrition,
        // 3 Kasım: bu hafta dışında ama ay içinde.
        meals(DateTime(2026, 11, 3), 1780),
      ];
      health.metrics = [...health.metrics, active(DateTime(2026, 11, 3), 0)];
      await pumpDetail(tester);

      await tapText(tester, 'Ay');
      expect(text(tester, 'energy-period-label'), 'Kasım 2026');
      expect(text(tester, 'energy-sum-days'), '4 gün üzerinden');
      // 3 Kasım: 1780 − 1780 = 0; toplam yine −350.
      expect(bigValue(tester, 'energy-sum-net'), '−350');
      expect(nextEnabled(tester), isFalse);
      expect(find.byType(BarChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hiç öğün yoksa boş durum metni', (tester) async {
      _now = DateTime(2026, 11, 19, 12);
      await pumpDetail(tester);

      expect(find.text('Bu dönemde öğün girilmiş gün yok'), findsOneWidget);
      expect(
        find.text('Öğün ekledikçe günlük denge burada görünür.'),
        findsOneWidget,
      );
      expect(find.byType(BarChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profil eksikse detay profil uyarısı gösterir', (tester) async {
      settings = FakeSettingsRepository();
      seedWeek();
      await pumpDetail(tester);

      expect(find.text('Profil eksik'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('18 yaş altı: yağ tahmini ve açık/fazla yorumu yok',
        (tester) async {
      settings = FakeSettingsRepository(
        settings: _complete.copyWith(birthYear: 2012),
      );
      seedWeek();
      await pumpDetail(tester);

      expect(find.byKey(const Key('energy-sum-net')), findsOneWidget);
      expect(find.byKey(const Key('energy-fat')), findsNothing);
      expect(find.text('Açık'), findsNothing);
      expect(
        find.text('Yorum ve yağ tahmini 18 yaşın altında gösterilmez.'),
        findsOneWidget,
      );
    });

    testWidgets('gece yarısı geçince hafta görünümü yeni güne taşınır',
        (tester) async {
      _now = DateTime(2026, 11, 22, 23, 30); // Pazar gecesi
      health
        ..metrics = [active(DateTime(2026, 11, 22), 400)]
        ..nutrition = [meals(DateTime(2026, 11, 22), 1500)];
      await pumpDetail(tester);
      expect(text(tester, 'energy-period-label'), '16–22 Kas 2026');

      _now = DateTime(2026, 11, 23, 6); // Pazartesi sabahı, uygulama öne geldi
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(text(tester, 'energy-period-label'), '23–29 Kas 2026');
      expect(find.text('Bu dönemde öğün girilmiş gün yok'), findsOneWidget);
    });
  });

  group('EnergyDetailScreen 375x667, metin ölçeği 1,3', () {
    void seedWeek() {
      _now = DateTime(2026, 11, 19, 12);
      health
        ..metrics = [active(_mon, 400), active(_tue, 400), active(_thu, 400)]
        ..nutrition = [meals(_mon, 2000), meals(_tue, 2300), meals(_thu, 1000)];
    }

    testWidgets('hafta, ay ve çizgi görünümü taşmaz', (tester) async {
      seedWeek();
      await pumpDetail(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Alınan / Yakılan');
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Ay');
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Net');
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok yüksek açık notu ve göstergesi taşmaz', (tester) async {
      _now = DateTime(2026, 11, 19, 12);
      health
        ..metrics = [active(_mon, 400), active(_tue, 400)]
        ..nutrition = [meals(_mon, 880), meals(_tue, 880)];
      await pumpDetail(tester, textScale: 1.3);
      expect(find.text('Çok yüksek açık'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapText(tester, 'Ay');
      expect(tester.takeException(), isNull);
    });

    testWidgets('boş dönem ve profil uyarısı taşmaz', (tester) async {
      _now = DateTime(2026, 11, 19, 12);
      await pumpDetail(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);

      settings = FakeSettingsRepository();
      await pumpDetail(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('metin yardımcıları', () {
    test('formatEnergyNet tipografik eksi ve binlik ayraç kullanır', () {
      expect(formatEnergyNet(-410.4), '−410');
      expect(formatEnergyNet(300), '+300');
      expect(formatEnergyNet(-1790), '−1.790');
      expect(formatEnergyNet(0.4), '0');
      expect(formatEnergyNet(-0.4), '0');
    });

    test('18 yaş altı dışındaki her durumun yorumu vardır', () {
      for (final verdict in EnergyVerdict.values) {
        expect(
          energyVerdictText(verdict) == null,
          verdict == EnergyVerdict.underAge,
          reason: verdict.name,
        );
      }
    });
  });
}
