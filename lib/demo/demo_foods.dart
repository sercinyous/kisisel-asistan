import 'package:flutter/services.dart';

import '../features/health/data/food_catalog.dart';
import '../features/health/domain/food_item.dart';

/// Tarayıcı demosunun besin listesi: paketli liste (`assets/data/foods_tr.json`)
/// doluysa o kullanılır; boşsa ya da okunamazsa aşağıdaki küçük örnek listeye
/// düşülür, böylece demoda "Besin ara" her durumda çalışır.
///
/// Örnek satırlar yalnızca demodadır ve doğrulanmış kaynak verisi değildir
/// (`verification: 'demo'`); uygulamaya gömülü listeye girmez.
Future<FoodCatalog> loadDemoFoodCatalog(AssetBundle bundle) async {
  try {
    final packaged = await FoodCatalog.load(bundle);
    if (packaged.items.isNotEmpty) return packaged;
  } catch (_) {
    // Paketli liste okunamazsa örnek listeyle devam edilir.
  }
  return demoFoodCatalog();
}

/// Demo örnek besinleri (100 g değerleri, yaygın yayımlanmış değerlere yakın).
FoodCatalog demoFoodCatalog() => FoodCatalog.fromItems(_demoFoods);

const String _demoSource = 'Demo örneği (doğrulanmamış)';
const String _demoVerification = 'demo';

FoodItem _food(
  String id,
  String name,
  String category,
  double kcal,
  double protein,
  double carbs,
  double fat, {
  List<String> aliases = const [],
  List<FoodPortion> portions = const [],
}) =>
    FoodItem(
      id: id,
      name: name,
      aliases: aliases,
      category: category,
      kcal100: kcal,
      protein100: protein,
      carbs100: carbs,
      fat100: fat,
      portions: portions,
      source: _demoSource,
      verification: _demoVerification,
    );

final List<FoodItem> _demoFoods = [
  _food('demo-yumurta', 'Yumurta (bütün, çiğ)', 'yumurta-süt', 143, 12.6, 0.7,
      9.5,
      aliases: const ['tavuk yumurtası'],
      portions: const [FoodPortion(name: '1 adet', grams: 50)]),
  _food('demo-yumurta-haslanmis', 'Yumurta (haşlanmış)', 'yumurta-süt', 155,
      12.6, 1.1, 10.6,
      aliases: const ['haşlama yumurta'],
      portions: const [FoodPortion(name: '1 adet', grams: 50)]),
  _food('demo-sut', 'Süt (tam yağlı)', 'yumurta-süt', 61, 3.2, 4.8, 3.3,
      aliases: const ['inek sütü'],
      portions: const [FoodPortion(name: '1 su bardağı', grams: 200)]),
  _food('demo-yogurt', 'Yoğurt (tam yağlı)', 'yumurta-süt', 61, 3.5, 4.7, 3.3,
      portions: const [FoodPortion(name: '1 kase', grams: 200)]),
  _food('demo-beyaz-peynir', 'Beyaz peynir', 'yumurta-süt', 264, 14.2, 4.1,
      21.3,
      portions: const [FoodPortion(name: '1 dilim', grams: 30)]),
  _food('demo-tavuk-gogsu', 'Tavuk göğsü (pişmiş)', 'et-balık', 165, 31, 0,
      3.6,
      aliases: const ['piliç göğüs'],
      portions: const [FoodPortion(name: '1 porsiyon', grams: 120)]),
  _food('demo-yulaf', 'Yulaf ezmesi (kuru)', 'tahıl-ekmek', 389, 16.9, 66.3,
      6.9,
      aliases: const ['oat'],
      portions: const [FoodPortion(name: '1 kase', grams: 40)]),
  _food('demo-tam-bugday-ekmegi', 'Tam buğday ekmeği', 'tahıl-ekmek', 252,
      12.5, 42.7, 3.5,
      aliases: const ['tam tahıllı ekmek'],
      portions: const [FoodPortion(name: '1 dilim', grams: 30)]),
  _food('demo-pirinc-pilavi', 'Pirinç pilavı (pişmiş)', 'tahıl-ekmek', 130,
      2.7, 28.2, 0.3,
      portions: const [FoodPortion(name: '1 porsiyon', grams: 150)]),
  _food('demo-mercimek', 'Mercimek (pişmiş)', 'baklagil', 116, 9, 20.1, 0.4,
      aliases: const ['kırmızı mercimek'],
      portions: const [FoodPortion(name: '1 kase', grams: 200)]),
  _food('demo-domates', 'Domates', 'sebze', 18, 0.9, 3.9, 0.2,
      portions: const [FoodPortion(name: '1 adet', grams: 120)]),
  _food('demo-muz', 'Muz', 'meyve', 89, 1.1, 22.8, 0.3,
      portions: const [FoodPortion(name: '1 adet', grams: 120)]),
  _food('demo-elma', 'Elma', 'meyve', 52, 0.3, 13.8, 0.2,
      portions: const [FoodPortion(name: '1 adet', grams: 180)]),
  _food('demo-badem', 'Badem', 'kuruyemiş-yağ', 579, 21.2, 21.6, 49.9,
      portions: const [FoodPortion(name: '1 avuç', grams: 28)]),
  _food('demo-zeytinyagi', 'Zeytinyağı', 'kuruyemiş-yağ', 884, 0, 0, 100,
      portions: const [FoodPortion(name: '1 yemek kaşığı', grams: 14)]),
];
