import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart'
    show dayNutritionLogsProvider;
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

Future<FakeSettingsRepository> _pump(
  WidgetTester tester, {
  List<WeightEntry> weights = const [],
  UserSettings settings = const UserSettings.defaults(),
  Map<String, Object> prefs = const {},
  FakeHealthRepository? health,
  FakeSettingsRepository? settingsRepo,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = settingsRepo ?? FakeSettingsRepository(settings: settings);
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

Map<String, dynamic> _withoutTargets(UserSettings s) => s.toMap()
  ..remove('daily_calories')
  ..remove('daily_protein_g')
  ..remove('daily_fat_g')
  ..remove('daily_carbs_g');

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
    // Varsayılan harcama 3000: 816 kcal açık → 0,74 kg/hafta, uyarı yok.
    expect(find.text('≈ 0,74 kg/hafta'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-menu-target')), findsOneWidget);
    expect(find.text(fatLossApproxNote), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-warning')), findsNothing);
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

  testWidgets('hedefleri ayarla: onay sonrası yalnızca makrolar yazılır',
      (tester) async {
    final repo = await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Hedefler güncellensin mi?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fat-loss-apply-confirm')));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    final s = repo.saved.single;
    const d = UserSettings.defaults();
    expect(s.dailyCalories, 2184);
    expect(s.dailyProteinG, 168);
    expect(s.dailyFatG, 72);
    expect(s.dailyCarbsG, 216);
    expect(_withoutTargets(s), _withoutTargets(d));
    expect(find.text('Hedefler güncellendi'), findsOneWidget);
  });

  testWidgets('vazgeçince kaydedilmez', (tester) async {
    final repo = await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
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
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(fatLossManualModeKey), isTrue);

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
    await _pump(
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
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(fatLossExpenditureKey), 3500);
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

  testWidgets('kalori sınırı: diyalog kaydedilecek değeri gösterir',
      (tester) async {
    // 30 kg → 780 kcal; sınır 800 → oran 800/780.
    final repo = await _pump(tester, weights: [_weight(30)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    expect(find.text(fatLossClampNote(800)), findsOneWidget);
    expect(
      find.text('Günlük hedeflerin 800 kcal, 62 g protein, 27 g yağ ve '
          '78 g karbonhidrat olacak.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('fat-loss-apply-confirm')));
    await tester.pumpAndSettle();
    final s = repo.saved.single;
    expect(s.dailyCalories, 800);
    expect(s.dailyProteinG, 62);
    expect(s.dailyFatG, 27);
    expect(s.dailyCarbsG, 78);
    expect(_withoutTargets(s), _withoutTargets(const UserSettings.defaults()));
  });

  testWidgets('sınır içinde not yok', (tester) async {
    await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fat-loss-apply-clamp')), findsNothing);
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
          settingsRepositoryProvider.overrideWithValue(
              FakeSettingsRepository(settings: const UserSettings.defaults())),
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
      await _pump(tester, weights: [_weight(84)]);
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
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(fatLossRateKey), 'half');

      await tester.tap(find.byKey(const Key('fat-loss-rate-threeQuarter')));
      await tester.pumpAndSettle();
      expect(find.text('2.175'), findsOneWidget);
      expect(inCard('fat-loss-rate-card', find.text('Hızlı')), findsOneWidget);

      await tester.tap(find.byKey(const Key('fat-loss-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2.175 kcal'), findsWidgets);
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
