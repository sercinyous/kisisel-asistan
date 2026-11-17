import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/food_catalog.dart';
import 'package:kisisel_asistan/features/health/domain/food_item.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/meal_form_sheet.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

/// Öğün formundaki besin arama ve gram hesabı (Faz 4A, Görev 5). Gerçek
/// `foods_tr.json` yerine küçük bir deneme kataloğu kullanılır.
FoodItem food(
  String id,
  String name, {
  List<String> aliases = const [],
  required double kcal,
  required double protein,
  required double carbs,
  required double fat,
  List<FoodPortion> portions = const [],
}) =>
    FoodItem(
      id: id,
      name: name,
      aliases: aliases,
      category: 'diğer',
      kcal100: kcal,
      protein100: protein,
      carbs100: carbs,
      fat100: fat,
      portions: portions,
      source: 'USDA FDC 1 | TürKomp 2',
      verification: 'iki kaynak',
    );

final fixtureCatalog = FoodCatalog.fromItems([
  food(
    'yumurta',
    'Yumurta (bütün, çiğ)',
    kcal: 143,
    protein: 12.6,
    carbs: 0.7,
    fat: 9.5,
    portions: const [FoodPortion(name: '1 adet', grams: 50)],
  ),
  food(
    'sut',
    'Süt (inek, tam yağlı)',
    aliases: ['inek sütü'],
    kcal: 61,
    protein: 3.2,
    carbs: 4.8,
    fat: 3.3,
    portions: const [FoodPortion(name: '1 su bardağı', grams: 200)],
  ),
  food(
    'yulaf',
    'Yulaf ezmesi',
    kcal: 389,
    protein: 16.9,
    carbs: 66.3,
    fat: 6.9,
    portions: const [
      FoodPortion(name: '1 yemek kaşığı', grams: 10),
      FoodPortion(name: '1 su bardağı', grams: 90),
    ],
  ),
  food(
    'zeytinyagi',
    'Zeytinyağı',
    kcal: 884,
    protein: 0,
    carbs: 0,
    fat: 100,
  ),
]);

void main() {
  late FakeHealthRepository health;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    health = FakeHealthRepository();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    double textScale = 1.0,
    NutritionLog? log,
    Future<FoodCatalog> Function()? catalog,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        foodCatalogProvider.overrideWith(
          (ref) => catalog != null ? catalog() : fixtureCatalog,
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
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => MealFormSheet.show(context, log: log),
                  child: const Text('Formu aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Formu aç'));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(Key(key));

  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(field(key)).controller!.text;

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(field('meal-food-search'), query);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String query, String id) async {
    await search(tester, query);
    await tapVisible(tester, field('food-$id'));
  }

  Future<void> setGrams(WidgetTester tester, String value) async {
    await tester.ensureVisible(field('meal-grams'));
    await tester.pumpAndSettle();
    await tester.enterText(field('meal-grams'), value);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) => tapVisible(tester, find.text('Kaydet'));

  const gramsNotPositive = 'Gram 0\'dan büyük olmalı.';

  testWidgets('arama Türkçe karakterden bağımsız sonuç listeler', (tester) async {
    await pumpSheet(tester);

    await search(tester, 'SUT');
    expect(field('food-sut'), findsOneWidget);
    expect(field('food-yumurta'), findsNothing);
    // Sonuç satırı 100 g değerlerini gösterir.
    expect(find.textContaining('61 kcal'), findsOneWidget);

    await search(tester, 'İnek');
    expect(field('food-sut'), findsOneWidget);

    await search(tester, 'yumurta');
    expect(field('food-yumurta'), findsOneWidget);

    await search(tester, '');
    expect(field('food-yumurta'), findsNothing);
  });

  testWidgets('arama → seçim → ad, gram, miktar ve değerler dolar',
      (tester) async {
    await pumpSheet(tester);
    expect(field('meal-grams'), findsNothing);

    await pick(tester, 'sut', 'sut');

    expect(text(tester, 'meal-name'), 'Süt (inek, tam yağlı)');
    expect(text(tester, 'meal-grams'), '100');
    expect(text(tester, 'meal-quantity'), '100 g');
    expect(text(tester, 'meal-calories'), '61');
    expect(text(tester, 'meal-protein'), '3,2');
    expect(text(tester, 'meal-carbs'), '4,8');
    expect(text(tester, 'meal-fat'), '3,3');
    // Arama kutusu boşalır, sonuç listesi kapanır.
    expect(
      tester.widget<TextField>(field('meal-food-search')).controller!.text,
      isEmpty,
    );
    expect(field('food-sut'), findsNothing);
  });

  testWidgets('seçilen besini kaydetmek kaynağı manual bırakır', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    await setGrams(tester, '150');
    // 143 kcal/100 g → 214,5.
    expect(text(tester, 'meal-calories'), '214,5');
    await save(tester);

    final created = health.nutritionLogs.single;
    expect(created.foodName, 'Yumurta (bütün, çiğ)');
    expect(created.quantityText, '150 g');
    expect(created.calories, 214.5);
    expect(created.proteinG, 18.9);
    expect(created.carbsG, 1.1);
    expect(created.fatG, 14.3);
    expect(created.source, 'manual');
  });

  testWidgets('gram alanı virgüllü değeri kabul eder', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    await setGrams(tester, '150,5');

    expect(find.text(gramsNotPositive), findsNothing);
    expect(find.text('Geçerli bir sayı gir.'), findsNothing);
    // 143 × 1,505 = 215,215 → 215,2.
    expect(text(tester, 'meal-calories'), '215,2');
    expect(text(tester, 'meal-quantity'), '150,5 g');

    await save(tester);
    final created = health.nutritionLogs.single;
    expect(created.calories, 215.2);
    expect(created.quantityText, '150,5 g');
  });

  testWidgets('gram boş, 0, negatif ya da sayı değilse hesap uygulanmaz',
      (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    expect(text(tester, 'meal-calories'), '143');

    for (final bad in ['-5', '0', '0,04']) {
      await setGrams(tester, bad);
      expect(find.text(gramsNotPositive), findsOneWidget, reason: bad);
      expect(text(tester, 'meal-calories'), '143', reason: bad);
      expect(text(tester, 'meal-quantity'), '100 g', reason: bad);
    }

    await setGrams(tester, '');
    expect(find.text('Gram girilmeli.'), findsOneWidget);
    expect(text(tester, 'meal-calories'), '143');

    await setGrams(tester, 'çok');
    expect(find.text('Geçerli bir sayı gir.'), findsOneWidget);
    expect(text(tester, 'meal-calories'), '143');

    await setGrams(tester, '6000');
    expect(find.text('Gram en fazla 5000 olabilir.'), findsOneWidget);
    expect(text(tester, 'meal-calories'), '143');

    // Geçerli değere dönünce hesap yeniden işler ve hata kaybolur.
    await setGrams(tester, '200');
    expect(find.text(gramsNotPositive), findsNothing);
    expect(text(tester, 'meal-calories'), '286');
  });

  testWidgets('geçersiz gramla kaydetmek engellenir', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    await setGrams(tester, '-5');
    await save(tester);

    expect(health.nutritionLogs, isEmpty);
    expect(find.text('Öğün ekle'), findsOneWidget);
    expect(find.text(gramsNotPositive), findsOneWidget);

    await setGrams(tester, '120');
    await save(tester);
    expect(health.nutritionLogs, hasLength(1));
    expect(health.nutritionLogs.single.calories, 171.6);
  });

  testWidgets('porsiyon çipi gramı ve miktar metnini ayarlar', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    expect(field('portion-count'), findsNothing);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, '1 adet (50 g)'));
    expect(text(tester, 'meal-grams'), '50');
    expect(text(tester, 'meal-quantity'), '1 adet · 50 g');
    expect(text(tester, 'meal-calories'), '71,5');

    await tapVisible(tester, field('portion-inc'));
    expect(text(tester, 'meal-grams'), '100');
    expect(text(tester, 'meal-quantity'), '2 adet · 100 g');
    expect(text(tester, 'meal-calories'), '143');
    expect(tester.widget<Text>(field('portion-count')).data, '2');

    await tapVisible(tester, field('portion-dec'));
    await tapVisible(tester, field('portion-dec'));
    // En az 1 adet: azaltma pasif.
    expect(text(tester, 'meal-quantity'), '1 adet · 50 g');
    expect(tester.widget<IconButton>(field('portion-dec')).onPressed, isNull);

    // Gramı elle değiştirmek porsiyon seçimini bırakır.
    await setGrams(tester, '75');
    expect(field('portion-count'), findsNothing);
    expect(text(tester, 'meal-quantity'), '75 g');
    expect(text(tester, 'meal-calories'), '107,3');
  });

  testWidgets('porsiyon çipine yeniden dokunmak seçimi kaldırır, gram kalır',
      (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yulaf', 'yulaf');

    final chip = find.widgetWithText(ChoiceChip, '1 su bardağı (90 g)');
    await tapVisible(tester, chip);
    expect(text(tester, 'meal-quantity'), '1 su bardağı · 90 g');

    await tapVisible(tester, chip);
    expect(field('portion-count'), findsNothing);
    expect(text(tester, 'meal-grams'), '90');
    expect(text(tester, 'meal-quantity'), '90 g');
  });

  testWidgets('değerler seçimden sonra elle düzenlenebilir', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'yumurta', 'yumurta');
    await tester.enterText(field('meal-calories'), '200');
    await tester.enterText(field('meal-name'), 'Yumurta, yağda');
    await save(tester);

    final created = health.nutritionLogs.single;
    expect(created.foodName, 'Yumurta, yağda');
    expect(created.calories, 200);
    expect(created.proteinG, 12.6);
    expect(created.source, 'manual');
  });

  testWidgets('yağsız besinin sıfır makroları boş alan olarak gösterilir',
      (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'zeytin', 'zeytinyagi');

    expect(text(tester, 'meal-calories'), '884');
    expect(text(tester, 'meal-protein'), '');
    expect(text(tester, 'meal-carbs'), '');
    expect(text(tester, 'meal-fat'), '100');
    // Porsiyonu olmayan besinde porsiyon çipi yoktur.
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    await save(tester);
    expect(health.nutritionLogs.single.proteinG, 0);
  });

  testWidgets('seçimi kaldırmak gram alanını gizler, alanlar elle düzenlenir',
      (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'sut', 'sut');
    expect(field('meal-grams'), findsOneWidget);

    await tapVisible(tester, find.byTooltip('Seçimi kaldır'));
    expect(field('meal-grams'), findsNothing);
    // Doldurulan değerler silinmez; kullanıcı elle sürdürür.
    expect(text(tester, 'meal-calories'), '61');
    await tester.enterText(field('meal-calories'), '70');
    await save(tester);
    expect(health.nutritionLogs.single.calories, 70);
    expect(health.nutritionLogs.single.quantityText, '100 g');
  });

  testWidgets('başka besin seçmek öncekinin yerine geçer', (tester) async {
    await pumpSheet(tester);
    await pick(tester, 'sut', 'sut');
    await tapVisible(tester, find.widgetWithText(ChoiceChip, '1 su bardağı (200 g)'));
    expect(text(tester, 'meal-quantity'), '1 su bardağı · 200 g');

    await pick(tester, 'yumurta', 'yumurta');
    expect(text(tester, 'meal-name'), 'Yumurta (bütün, çiğ)');
    expect(text(tester, 'meal-grams'), '100');
    expect(text(tester, 'meal-quantity'), '100 g');
    expect(text(tester, 'meal-calories'), '143');
    // Önceki besinin porsiyon seçimi taşınmaz.
    expect(field('portion-count'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '1 adet (50 g)'), findsOneWidget);
  });

  testWidgets('elle giriş akışı besin aramasından bağımsız çalışır',
      (tester) async {
    await pumpSheet(tester);
    expect(field('meal-grams'), findsNothing);

    await tester.enterText(field('meal-name'), 'Ev yapımı çorba');
    await tester.enterText(field('meal-quantity'), '1 kase');
    await tester.enterText(field('meal-calories'), '180');
    await tester.enterText(field('meal-protein'), '9,5');
    await save(tester);

    final created = health.nutritionLogs.single;
    expect(created.foodName, 'Ev yapımı çorba');
    expect(created.quantityText, '1 kase');
    expect(created.calories, 180);
    expect(created.proteinG, 9.5);
    expect(created.source, 'manual');
  });

  testWidgets('listede olmayan arama elle girişe yönlendirir', (tester) async {
    await pumpSheet(tester);
    await search(tester, 'zzzz');

    expect(find.text('Listede yok. Ad ve değerleri aşağıdan elle gir.'),
        findsOneWidget);
    await tester.enterText(field('meal-name'), 'Zzzz');
    await save(tester);
    expect(health.nutritionLogs.single.foodName, 'Zzzz');
  });

  testWidgets('besin listesi yüklenemezse form elle girişle çalışır',
      (tester) async {
    await pumpSheet(
      tester,
      catalog: () => Future<FoodCatalog>.error(Exception('asset yok')),
    );

    await search(tester, 'sut');
    expect(find.text('Besin listesi yüklenemedi. Elle girebilirsin.'),
        findsOneWidget);
    expect(field('food-sut'), findsNothing);

    await tester.enterText(field('meal-name'), 'Süt');
    await tester.enterText(field('meal-calories'), '120');
    await save(tester);
    expect(health.nutritionLogs.single.calories, 120);
  });

  testWidgets('düzenleme modunda da besin seçilebilir ve kaynak korunur',
      (tester) async {
    final existing = NutritionLog(
      id: 'n9',
      mealType: 'dinner',
      foodName: 'Eski kayıt',
      calories: 99,
      eatenAt: AppDates.startOfDay(DateTime.now())
          .add(const Duration(hours: 1)),
      source: 'ai',
    );
    health = FakeHealthRepository(nutritionLogs: [existing]);
    await pumpSheet(tester, log: existing);
    expect(find.text('Öğünü düzenle'), findsOneWidget);

    await pick(tester, 'sut', 'sut');
    await save(tester);

    final updated = health.nutritionLogs.single;
    expect(updated.id, 'n9');
    expect(updated.foodName, 'Süt (inek, tam yağlı)');
    expect(updated.calories, 61);
    expect(updated.mealType, 'dinner');
    // Besin listesinden seçmek kaydın kaynağını değiştirmez.
    expect(updated.source, 'ai');
  });

  group('taşma', () {
    testWidgets('sonuç listesi 375x667 ve 1,3 metin ölçeğinde taşmaz',
        (tester) async {
      await pumpSheet(tester, textScale: 1.3);
      await search(tester, 'a');
      expect(field('food-yumurta'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(field('food-zeytinyagi'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('seçili besin, porsiyon ve hata 375x667 ve 1,3 ölçekte taşmaz',
        (tester) async {
      await pumpSheet(tester, textScale: 1.3);
      await pick(tester, 'yulaf', 'yulaf');
      await tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, '1 su bardağı (90 g)'),
      );
      await tapVisible(tester, field('portion-inc'));
      expect(tester.takeException(), isNull);

      await setGrams(tester, '-5');
      expect(find.text(gramsNotPositive), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
