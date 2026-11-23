import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_screen.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart' show Sex;
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart'
    show dayNutritionLogsProvider;
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Eski cihaz tercihlerinin yerini alan user_settings alanları (testlerde
/// kısa yazım için anahtar adları korunur).
const String fatLossRateKey = 'weekly_rate';
const String fatLossExpenditureKey = 'expenditure_kcal_manual';

/// Ayarlar: hız ve elle harcama; hedef kilo, plan kilitlenmeyecek ve kilo
/// verme modu seçilecek şekilde (VKİ 18,6 ya da 30 kg).
UserSettings _withPlan(UserSettings s, Map<String, Object> plan) {
  final h = s.heightCm;
  final target = h == null ? 30.0 : (18.6 * h * h / 10000).ceilToDouble();
  return s.copyWith(
    targetWeightKg: target,
    weeklyRate: FatLossRate.parse(plan[fatLossRateKey] as String?),
    expenditureKcalManual: plan[fatLossExpenditureKey] as int?,
  );
}

Future<FakeSettingsRepository> _pump(
  WidgetTester tester, {
  List<WeightEntry> weights = const [],
  UserSettings settings = const UserSettings.defaults(),
  Map<String, Object> prefs = const {},
  FakeHealthRepository? health,
  FakeSettingsRepository? settingsRepo,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = settingsRepo ??
      FakeSettingsRepository(
          settings: _applied(_withPlan(settings, prefs),
              weights.isNotEmpty ? weights : health?.weights ?? const []));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthRepositoryProvider.overrideWithValue(
            health ?? FakeHealthRepository(weights: [...weights])),
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const FatLossScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

WeightEntry _weight(double kg, {Duration ago = const Duration(hours: 1)}) =>
    WeightEntry(
      id: 'w$kg-${ago.inMinutes}',
      weightKg: kg,
      loggedAt: DateTime.now().subtract(ago),
    );

UserSettings _profile({
  ActivityLevel activity = ActivityLevel.moderate,
  int height = 180,
}) =>
    const UserSettings.defaults().copyWith(
      sex: 'male',
      heightCm: height,
      birthYear: DateTime.now().year - 30,
      activityLevel: activity,
    );

/// Hedefler motorun yazdığı gibi (ilk kurulum / tempo sonrası durum).
UserSettings _applied(UserSettings s, List<WeightEntry> weights) {
  if (weights.isEmpty) return s;
  final latest =
      weights.reduce((a, b) => b.loggedAt.isAfter(a.loggedAt) ? b : a);
  final r = resolveTargets(
    settings: s,
    latestWeightKg: latest.weightKg,
    age: ageFromSettings(s, DateTime.now()),
    sex: Sex.tryParse(s.sex),
  );
  return planWrite(
    settings: s,
    resolved: r,
    trigger: PlanTrigger.rateChanged,
    now: DateTime.now(),
  )!
      .settings;
}

void main() {
  testWidgets('kilo yoksa boş durum ve Kilo ekle', (tester) async {
    await _pump(tester);
    expect(find.text('Planı hesaplamak için bir kilo ölçümü gerekli.'),
        findsOneWidget);
    expect(find.byKey(const Key('fat-loss-add-weight')), findsOneWidget);
    expect(find.text(fatLossDisclaimer), findsOneWidget);
  });

  testWidgets('kiloyla hedefler, karşılıklar ve menü', (tester) async {
    await _pump(tester, weights: [_weight(84)]);
    expect(find.text('2.184'), findsOneWidget);
    expect(find.text('168 g'), findsOneWidget);
    expect(find.text('216 g'), findsOneWidget);
    expect(find.text('Tavuk göğsü · 540 g'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-menu-total')), findsOneWidget);
    expect(find.text(fatLossDisclaimer), findsOneWidget);
    // Varsayılan harcama 3000: 816 kcal açık → 0,74 kg/hafta (%0,88: Hızlı).
    expect(find.text('≈ 0,74 kg/hafta'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-menu-target')), findsOneWidget);
    expect(find.text(fatLossApproxNote), findsOneWidget);
    expect(find.text(fatLossFastWarning(RateHealth.fast)), findsOneWidget);
    expect(find.text(fatLossWaterNote), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<FatLossMacro>),
      matching: find.text('Yağ'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Zeytinyağı · 5 yemek kaşığı'), findsOneWidget);
  });

  testWidgets('agresif hızda uyarı', (tester) async {
    // 60 kg → 1560 kcal; 3000 harcama → 1440 açık → 1,3 kg/hafta (%2,2).
    await _pump(tester, weights: [_weight(60)]);
    expect(find.byKey(const Key('fat-loss-warning')), findsOneWidget);
    expect(find.text(fatLossFastWarning(RateHealth.aggressive)),
        findsOneWidget);
  });

  testWidgets('klasik 1.200 altı: uyarı, sayılar aynı', (tester) async {
    // 40 kg → 1040 kcal.
    await _pump(tester, weights: [_weight(40)]);
    expect(find.text('1.040'), findsOneWidget);
    expect(find.text(classicFloorWarning(1040)), findsOneWidget);
  });

  testWidgets('saklanan tanınmayan hız klasiğe düşer', (tester) async {
    await _pump(tester,
        weights: [_weight(84)], prefs: {fatLossRateKey: 'bilinmeyen'});
    expect(find.text('2.184'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-rate-classic-info')), findsOneWidget);
  });

  testWidgets('açık yoksa kayıp yok açıklaması', (tester) async {
    // 120 kg → 3120 kcal > 3000.
    await _pump(tester, weights: [_weight(120)]);
    expect(find.byKey(const Key('fat-loss-no-loss')), findsOneWidget);
    expect(find.text(fatLossNegativeDeficit), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-warning')), findsNothing);
  });

  testWidgets('en son tartı kullanılır', (tester) async {
    await _pump(tester, weights: [
      _weight(90, ago: const Duration(days: 2)),
      _weight(84),
      _weight(70, ago: const Duration(days: 5)),
    ]);
    expect(find.text('2.184'), findsOneWidget);
  });

  testWidgets('profil tamsa harcama profilden; Elle gir saklanır',
      (tester) async {
    final repo =
        await _pump(tester, weights: [_weight(84)], settings: _profile());
    expect(
        find.text('Harcama profilinden (bazal × hareket düzeyi) hesaplandı.'),
        findsOneWidget);
    // 10×84 + 6,25×180 − 5×30 + 5 = 1820 × 1,55 = 2821.
    expect(find.textContaining('Günlük harcama 2.821 kcal'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-edit-expenditure')), findsNothing);

    await tester.tap(find.text('Elle gir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fat-loss-edit-expenditure')), findsOneWidget);
    expect(find.textContaining('Günlük harcama 3.000 kcal'), findsOneWidget);
    expect(repo.settings!.expenditureKcalManual, 3000);

    await tester.tap(find.text('Profilden hesapla'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Günlük harcama 2.821 kcal'), findsOneWidget);
  });

  testWidgets('profil harcaması 6000 kcal ile sınırlanır', (tester) async {
    await _pump(
      tester,
      weights: [_weight(250)],
      settings: _profile(activity: ActivityLevel.veryActive, height: 250),
    );
    expect(find.textContaining('Günlük harcama 6.000 kcal'), findsOneWidget);
  });

  testWidgets('kayıtlı harcama okunur ve düzenleme saklanır', (tester) async {
    final repo = await _pump(
      tester,
      weights: [_weight(84)],
      prefs: {fatLossExpenditureKey: 2600},
    );
    // 2600 − 2184 = 416 → 0,38 kg/hafta.
    expect(find.text('≈ 0,38 kg/hafta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fat-loss-edit-expenditure')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('fat-loss-expenditure-field')), '3500');
    await tester.tap(find.byKey(const Key('fat-loss-expenditure-save')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenditureDialog), findsNothing);
    expect(repo.settings!.expenditureKcalManual, 3500);
    // 1316 kcal açık → 1,20 kg/hafta, uyarı.
    expect(find.text('≈ 1,20 kg/hafta'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-warning')), findsOneWidget);
  });

  testWidgets('harcama diyaloğu: geçersizde kapanmaz, kapanışta hata yok',
      (tester) async {
    await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-edit-expenditure')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('fat-loss-expenditure-field'));

    await tester.enterText(field, '12ab');
    await tester.pump();
    expect(find.text('12'), findsOneWidget);

    await tester.enterText(field, '900');
    await tester.tap(find.byKey(const Key('fat-loss-expenditure-save')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpenditureDialog), findsOneWidget);
    expect(find.text(fatLossExpenditureError), findsOneWidget);

    await tester.enterText(field, '3200');
    await tester.tap(find.byKey(const Key('fat-loss-expenditure-save')));
    // Kapanış animasyonu kare kare: denetleyici atıldıktan sonra kullanılmaz.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenditureDialog), findsNothing);
    expect(find.textContaining('Günlük harcama 3.200 kcal'), findsOneWidget);

    // Vazgeç de animasyonla kapanır.
    await tester.tap(find.byKey(const Key('fat-loss-edit-expenditure')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenditureDialog), findsNothing);
  });

  testWidgets('kilo hatası: dokununca yeniden yüklenir', (tester) async {
    final health = FakeHealthRepository(weights: [_weight(84)])
      ..fetchError = Exception('ağ');
    await _pump(tester, health: health);
    expect(find.text(fatLossLoadError), findsOneWidget);
    health.fetchError = null;
    await tester.tap(find.byKey(const Key('fat-loss-retry')));
    await tester.pumpAndSettle();
    expect(find.text(fatLossLoadError), findsNothing);
    expect(find.text('2.184'), findsOneWidget);
  });

  testWidgets('ayar hatası plan hatası olarak görünür', (tester) async {
    final settingsRepo = FakeSettingsRepository()..fetchError = Exception('x');
    await _pump(tester, weights: [_weight(84)], settingsRepo: settingsRepo);
    expect(find.text(fatLossLoadError), findsOneWidget);
    settingsRepo.fetchError = null;
    await tester.tap(find.byKey(const Key('fat-loss-retry')));
    await tester.pumpAndSettle();
    expect(find.text('2.184'), findsOneWidget);
  });

  group('Bugün kartı', () {
    NutritionLog meal(String type, double kcal, double p, double f, double c) =>
        NutritionLog(
          id: '',
          foodName: type,
          mealType: type,
          calories: kcal,
          proteinG: p,
          fatG: f,
          carbsG: c,
          eatenAt: DateTime.now(),
        );

    testWidgets('öğün yokken bilgi, eklenince öneriler ve özet satırı',
        (tester) async {
      final health = FakeHealthRepository(weights: [_weight(84)]);
      await _pump(tester, health: health);
      expect(find.byKey(const Key('fat-loss-today')), findsOneWidget);
      expect(find.textContaining('Henüz öğün girilmedi'), findsOneWidget);
      expect(find.byKey(const Key('fat-loss-gap-fiber')), findsOneWidget);
      expect(find.text('veri yok'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.byType(FatLossScreen)));
      await health.createNutritionLog(meal('breakfast', 700, 60, 41, 70));
      await health.createNutritionLog(meal('lunch', 700, 63, 41, 70));
      container.invalidate(dayNutritionLogsProvider);
      await tester.pumpAndSettle();

      expect(find.textContaining('Henüz öğün girilmedi'), findsNothing);
      expect(find.text('Protein 45 g eksik'), findsOneWidget);
      expect(find.text('Yağ 10 g fazla'), findsOneWidget);
      expect(
          find.textContaining(RegExp(r'(yemeğinde|öğünde): \d+ g ton balığı')),
          findsOneWidget);
      expect(find.text(fatLossDisclaimer), findsOneWidget);
      expect(container.read(todayMealGapProvider).value!.summary,
          'Protein 45 g eksik · Yağ 10 g fazla');
    });

    testWidgets('özet satırı öğün eklenince güncellenir ve planı açar',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final health = FakeHealthRepository(weights: [_weight(84)]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          healthRepositoryProvider.overrideWithValue(health),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(
              settings: _applied(_withPlan(const UserSettings.defaults(), {}),
                  health.weights))),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: FatLossGapLine()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Henüz öğün yok · hedef 2.184 kcal'), findsOneWidget);

      await health.createNutritionLog(meal('lunch', 600, 123, 30, 100));
      ProviderScope.containerOf(tester.element(find.byType(FatLossGapLine)))
          .invalidate(dayNutritionLogsProvider);
      await tester.pumpAndSettle();
      expect(find.text('Protein 45 g eksik · Yağ 42 g eksik'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fat-loss-gap-line')));
      await tester.pumpAndSettle();
      expect(find.byType(FatLossScreen), findsOneWidget);
    });
  });

  group('haftalık hız', () {
    Finder inCard(String key, Finder f) =>
        find.descendant(of: find.byKey(Key(key)), matching: f);

    testWidgets('hız değişince kalori, makro, menü ve öğün açığı güncellenir',
        (tester) async {
      final repo = await _pump(tester, weights: [_weight(84)]);
      expect(find.text('2.184'), findsOneWidget);
      expect(find.byKey(const Key('fat-loss-rate-classic-info')), findsOneWidget);
      final chip = find.byKey(const Key('fat-loss-rate-half'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      // 3000 − 550 = 2450; P 168, Y 68, K 291, lif 34.
      expect(find.text('2.450'), findsOneWidget);
      expect(find.text('68 g'), findsOneWidget);
      expect(find.text('291 g'), findsOneWidget);
      expect(
          find.text('Hedef 2.450 kcal · P 168 g · Y 68 g · K 291 g · Lif 34 g'),
          findsOneWidget);
      expect(inCard('fat-loss-today', find.textContaining('2.450')),
          findsWidgets);
      expect(find.text('≈ 0,50 kg/hafta'), findsOneWidget);
      expect(inCard('fat-loss-rate-card', find.text('Sürdürülebilir')),
          findsOneWidget);
      expect(find.byKey(const Key('fat-loss-rate-classic-info')), findsNothing);
      expect(repo.settings!.weeklyRate, FatLossRate.half);

      await tester.tap(find.byKey(const Key('fat-loss-rate-threeQuarter')));
      await tester.pumpAndSettle();
      expect(find.text('2.175'), findsOneWidget);
      expect(inCard('fat-loss-rate-card', find.text('Hızlı')), findsOneWidget);
      // Tempo değişimi hedefleri motorla yazar (tek yazar).
      expect(repo.settings!.dailyCalories, 2175);
      expect(repo.settings!.targetsSource, TargetsSource.plan);
    });

    testWidgets('saklanan 1 kg seçimi, taban notu, agresif ve multivitamin',
        (tester) async {
      await _pump(tester, weights: [
        _weight(60)
      ], prefs: {
        fatLossRateKey: 'one',
        fatLossExpenditureKey: 1900,
      });
      expect(find.text('1.200'), findsOneWidget);
      expect(find.byKey(const Key('fat-loss-rate-floor')), findsOneWidget);
      expect(find.text(rateFloorNote(700 * 7 / 7700)), findsOneWidget);
      expect(inCard('fat-loss-rate-card', find.text('Agresif')),
          findsOneWidget);
      expect(find.text(fatLossWaterNote), findsOneWidget);
      expect(find.text(rateClampLine(1200)), findsOneWidget);
      expect(inCard('supplement-fiber', find.textContaining('hedefin: 16 g')),
          findsOneWidget);
      expect(find.text('Multivitamin · önerilir'), findsOneWidget);
      expect(find.text(supplementDisclaimer), findsOneWidget);
    });

    testWidgets('vitamin kartı cinsiyete göre magnezyum', (tester) async {
      await _pump(tester, weights: [_weight(84)], settings: _profile());
      expect(inCard('supplement-magnesium', find.textContaining('Erkek: 400')),
          findsOneWidget);
      expect(find.text('Multivitamin'), findsOneWidget);
      expect(inCard('supplement-water', find.textContaining('2.950 ml')),
          findsOneWidget);
    });

    testWidgets('kadın ve belirsiz profil', (tester) async {
      await _pump(tester,
          weights: [_weight(60)],
          settings: _profile().copyWith(sex: 'female'));
      expect(inCard('supplement-magnesium', find.textContaining('Kadın: 310')),
          findsOneWidget);
    });

    testWidgets('cinsiyet bilinmeyen profil: iki değer, su sınırı',
        (tester) async {
      await _pump(tester,
          weights: [_weight(150)],
          settings: _profile().copyWith(sex: 'other'));
      expect(
          inCard('supplement-magnesium',
              find.textContaining('Kadın 310–320 mg, erkek 400–420')),
          findsOneWidget);
      expect(
          inCard('supplement-magnesium', find.textContaining('350 mg\'ı aşma')),
          findsOneWidget);
      expect(inCard('supplement-water', find.textContaining('4.000 ml/gün')),
          findsOneWidget);
    });

    testWidgets('kayıp yokken ≈0,00 gösterilmez', (tester) async {
      await _pump(tester,
          weights: [_weight(70)],
          prefs: {fatLossRateKey: 'half', fatLossExpenditureKey: 1200});
      expect(find.textContaining('0,00'), findsNothing);
      expect(find.text(rateFloorNote(0)), findsOneWidget);
      expect(find.text('Bu harcamayla kilo kaybı beklenmez.'), findsOneWidget);
    });

    testWidgets('profil yoksa iki magnezyum değeri', (tester) async {
      await _pump(tester, weights: [_weight(84)]);
      final f = inCard('supplement-magnesium',
          find.textContaining('Kadın 310–320 mg, erkek 400–420'));
      expect(f, findsOneWidget);
    });
  });
}
