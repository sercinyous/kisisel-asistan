import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/food_catalog.dart';
import 'package:kisisel_asistan/features/health/domain/food_item.dart';
import 'package:kisisel_asistan/features/health/presentation/food_picker_sheet.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

/// Yazio tarzı besin seçici: kategori, arama, miktar sayfası, son kullanılanlar.
final _catalog = FoodCatalog.fromItems(const [
  FoodItem(
    id: 'k-yumurta-haslama',
    name: 'Haşlanmış yumurta',
    category: 'et-balık',
    categories: ['Haşlanmış Yiyecekler', 'Kahvaltılık Ürünler'],
    kcal100: 156,
    protein100: 12.6,
    carbs100: 1.1,
    fat100: 10.6,
    portions: [FoodPortion(name: '1 adet', grams: 50)],
    source: 'Kullanıcı listesi (yaklaşık)',
    verification: 'yaklaşık',
  ),
  FoodItem(
    id: 'k-kabak-kizarmis',
    name: 'Kızarmış kabak',
    category: 'diğer',
    categories: ['Kızartılmış Yiyecekler'],
    kcal100: 150,
    protein100: null,
    carbs100: null,
    fat100: null,
    note: 'Yağ miktarına göre değişir',
    source: 'Kullanıcı listesi (yaklaşık)',
    verification: 'yaklaşık',
  ),
  FoodItem(
    id: 'k-muz',
    name: 'Muz',
    category: 'meyve',
    categories: ['Meyveler'],
    kcal100: 89,
    protein100: 1.1,
    carbs100: 22.8,
    fat100: 0.3,
    portions: [FoodPortion(name: '1 orta boy', grams: 118)],
    source: 'Kullanıcı listesi (yaklaşık)',
    verification: 'yaklaşık',
  ),
]);

void main() {
  late FakeHealthRepository health;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    health = FakeHealthRepository();
  });

  Future<void> pumpPicker(WidgetTester tester, {String? mealType}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        foodCatalogProvider.overrideWith((ref) => _catalog),
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
                  onPressed: () =>
                      FoodPickerSheet.show(context, mealType: mealType),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String kcalText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('amount-kcal'))).data!;

  testWidgets('9 kategori çipi var; kategori listeyi süzer', (tester) async {
    await pumpPicker(tester);
    for (final c in FoodCategories.all) {
      expect(find.byKey(Key('food-category-$c')), findsOneWidget);
    }
    expect(find.byKey(const Key('picker-food-k-muz')), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('food-category-Meyveler')));
    expect(find.byKey(const Key('picker-food-k-muz')), findsOneWidget);
    expect(find.byKey(const Key('picker-food-k-yumurta-haslama')),
        findsNothing);
  });

  testWidgets('satır porsiyon ve 100 g kalorisini, kızartma notunu gösterir',
      (tester) async {
    await pumpPicker(tester);
    expect(find.text('1 adet (50 g): 78 kcal · 100 g: 156 kcal'),
        findsOneWidget);
    expect(find.textContaining('Yağ miktarına göre değişir'), findsOneWidget);
  });

  testWidgets('arama Türkçe karakterden bağımsız', (tester) async {
    await pumpPicker(tester);
    await tester.enterText(
        find.byKey(const Key('food-picker-search')), 'haslanmis');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picker-food-k-yumurta-haslama')),
        findsOneWidget);
    expect(find.byKey(const Key('picker-food-k-muz')), findsNothing);
  });

  testWidgets('miktar: adet artırma, gram birimi, öğün seçimi ve kayıt',
      (tester) async {
    await pumpPicker(tester, mealType: 'breakfast');
    await tapVisible(
        tester, find.byKey(const Key('picker-food-k-yumurta-haslama')));

    expect(kcalText(tester), '78 kcal');
    await tapVisible(tester, find.byKey(const Key('amount-inc')));
    await tapVisible(tester, find.byKey(const Key('amount-inc')));
    expect(kcalText(tester), '156 kcal');

    await tapVisible(tester, find.byKey(const Key('amount-unit-gram')));
    expect(kcalText(tester), '156 kcal'); // 100 g
    await tester.enterText(find.byKey(const Key('amount-grams')), '150');
    await tester.pumpAndSettle();
    expect(kcalText(tester), '234 kcal');

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Ara öğün'));
    await tapVisible(tester, find.text('Kaydet'));

    final log = health.nutritionLogs.last;
    expect(log.foodName, 'Haşlanmış yumurta');
    expect(log.mealType, 'snack');
    expect(log.calories, 234);
    expect(log.proteinG, 18.9);
    expect(log.quantityText, '150 g');
    // Kayıttan sonra seçici de kapanır.
    expect(find.byKey(const Key('food-picker-search')), findsNothing);
  });

  testWidgets('porsiyonla kayıt miktar metnini yazar; makrosuz besin 0 makro',
      (tester) async {
    await pumpPicker(tester, mealType: 'dinner');
    await tapVisible(
        tester, find.byKey(const Key('picker-food-k-kabak-kizarmis')));
    expect(find.byKey(const Key('amount-note')), findsOneWidget);
    await tapVisible(tester, find.text('Kaydet'));
    final log = health.nutritionLogs.last;
    expect(log.mealType, 'dinner');
    expect(log.calories, 150);
    expect(log.proteinG, 0);
    expect(log.quantityText, '100 g');
  });

  testWidgets('eklenen besin son kullanılanlarda üstte görünür',
      (tester) async {
    await pumpPicker(tester);
    expect(find.text('Son kullanılanlar'), findsNothing);
    await tapVisible(tester, find.byKey(const Key('picker-food-k-muz')));
    await tapVisible(tester, find.text('Kaydet'));
    expect(health.nutritionLogs.last.quantityText, '1 orta boy · 118 g');

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(find.text('Son kullanılanlar'), findsOneWidget);
    expect(find.byKey(const Key('recent-food-k-muz')), findsOneWidget);
  });
}
