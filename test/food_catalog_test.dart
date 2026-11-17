import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/data/food_catalog.dart';
import 'package:kisisel_asistan/features/health/domain/food_item.dart';

/// Bellekteki dosyalardan okuyan sahte paket.
class _MemoryBundle extends CachingAssetBundle {
  _MemoryBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final content = files[key];
    if (content == null) throw FlutterError('Asset yok: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }
}

FoodItem item(
  String id,
  String name, {
  List<String> aliases = const [],
  double kcal = 100,
  double protein = 10,
  double carbs = 10,
  double fat = 1,
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
    );

Map<String, dynamic> row(String id, String name) => {
      'id': id,
      'name': name,
      'aliases': ['takma'],
      'category': 'sebze',
      'kcal100': 20,
      'protein100': 1,
      'carbs100': 4,
      'fat100': 0.2,
      'portions': [
        {'name': '1 adet', 'grams': 80},
      ],
      'source': 'USDA FDC 1 | TürKomp 2',
      'verification': 'iki kaynak',
    };

void main() {
  group('FoodItem', () {
    test('forGrams 143 kcal/100 g için 150 g = 214,5 kcal', () {
      final food = item('x', 'Deneme', kcal: 143, protein: 12, carbs: 2, fat: 9);
      final macros = food.forGrams(150);
      expect(macros.kcal, 214.5);
      expect(macros.protein, 18);
      expect(macros.carbs, 3);
      expect(macros.fat, 13.5);
      expect(food.forGrams(100).kcal, 143);
    });

    test('forGrams sıfır, negatif ve sonsuzda hepsi 0 döner', () {
      final food = item('x', 'Deneme', kcal: 143);
      for (final grams in [0.0, -5.0, double.nan, double.infinity]) {
        final macros = food.forGrams(grams);
        expect(macros.kcal, 0, reason: '$grams');
        expect(macros.protein, 0, reason: '$grams');
        expect(macros.carbs, 0, reason: '$grams');
        expect(macros.fat, 0, reason: '$grams');
      }
    });

    test('fromMap sözleşmedeki tüm alanları okur', () {
      final food = FoodItem.fromMap(row('havuc', 'Havuç (çiğ)'));
      expect(food.id, 'havuc');
      expect(food.name, 'Havuç (çiğ)');
      expect(food.aliases, ['takma']);
      expect(food.category, 'sebze');
      expect(food.kcal100, 20);
      expect(food.fat100, 0.2);
      expect(food.portions.single, const FoodPortion(name: '1 adet', grams: 80));
      expect(food.source, 'USDA FDC 1 | TürKomp 2');
      expect(food.verification, 'iki kaynak');
    });

    test('fromMap eksik ya da bozuk alanda FormatException fırlatır', () {
      expect(
        () => FoodItem.fromMap({...row('a', 'A'), 'kcal100': null}),
        throwsFormatException,
      );
      expect(
        () => FoodItem.fromMap({...row('a', 'A'), 'kcal100': -1}),
        throwsFormatException,
      );
      expect(
        () => FoodItem.fromMap({...row('a', 'A'), 'name': '  '}),
        throwsFormatException,
      );
      expect(
        () => FoodItem.fromMap({
          ...row('a', 'A'),
          'portions': [
            {'name': '1 adet', 'grams': 0},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('kullanıcı listesi alanları', () {
    test('makrosuz satır okunur; forGrams makroları null döner', () {
      final food = FoodItem.fromMap({
        ...row('kizarmis', 'Kızarmış kabak'),
        'kcal100': 150,
        'protein100': null,
        'carbs100': null,
        'fat100': null,
        'categories': ['Kızartılmış Yiyecekler'],
        'note': 'Yağ miktarına göre değişir',
      });
      expect(food.hasMacros, isFalse);
      expect(food.categories, ['Kızartılmış Yiyecekler']);
      expect(food.note, 'Yağ miktarına göre değişir');
      final macros = food.forGrams(200);
      expect(macros.kcal, 300);
      expect(macros.protein, isNull);
      expect(macros.fat, isNull);
    });

    test('defaultPortion ilk porsiyon, yoksa 100 g', () {
      final withPortion = FoodItem.fromMap(row('a', 'A'));
      expect(withPortion.defaultPortion.grams, 80);
      final bare = FoodItem.fromMap({...row('b', 'B'), 'portions': []});
      expect(bare.defaultPortion, const FoodPortion(name: '100 g', grams: 100));
    });

    test('inCategory ve byId', () {
      final catalog = FoodCatalog.fromItems([
        FoodItem.fromMap({
          ...row('a', 'A'),
          'categories': ['Meyveler', 'Öğle Atıştırmalıkları'],
        }),
        FoodItem.fromMap({...row('b', 'B'), 'categories': ['Sebzeler']}),
      ]);
      expect(catalog.inCategory('Meyveler').map((f) => f.id), ['a']);
      expect(catalog.inCategory('Öğle Atıştırmalıkları').map((f) => f.id),
          ['a']);
      expect(catalog.byId('b')?.name, 'B');
      expect(catalog.byId('x'), isNull);
    });
  });

  group('FoodPortion.describe', () {
    test('başındaki sayıyı adetle çarpar', () {
      const adet = FoodPortion(name: '1 adet', grams: 50);
      expect(adet.describe(1), '1 adet');
      expect(adet.describe(2), '2 adet');
      const dilim = FoodPortion(name: '2 dilim', grams: 60);
      expect(dilim.describe(3), '6 dilim');
      const yarim = FoodPortion(name: '0,5 bardak', grams: 100);
      expect(yarim.describe(1), '0,5 bardak');
      expect(yarim.describe(3), '1,5 bardak');
    });

    test('sayısız adda "n × ad" biçimi kullanılır', () {
      const orta = FoodPortion(name: 'Orta boy', grams: 130);
      expect(orta.describe(1), 'Orta boy');
      expect(orta.describe(2), '2 × Orta boy');
    });
  });

  group('FoodCatalog.normalize', () {
    test('Türkçe harfleri ve büyük/küçük harfi eşler', () {
      expect(FoodCatalog.normalize('SÜT'), 'sut');
      expect(FoodCatalog.normalize('İnek'), 'inek');
      expect(FoodCatalog.normalize('ınek'), 'inek');
      expect(FoodCatalog.normalize('INEK'), 'inek');
      expect(FoodCatalog.normalize('ÇĞÖŞÜ çğıöşü'), 'cgosu cgiosu');
      expect(FoodCatalog.normalize('Pırasa'), 'pirasa');
    });

    test('boşlukları sadeleştirir ve birleşik noktayı atar', () {
      expect(FoodCatalog.normalize('  beyaz \t  peynir '), 'beyaz peynir');
      expect(FoodCatalog.normalize('i̇nek'), 'inek');
      expect(FoodCatalog.normalize('   '), '');
    });
  });

  group('FoodCatalog.search', () {
    final catalog = FoodCatalog.fromItems([
      item('omlet', 'Omlet', aliases: ['yumurta yemeği']),
      item('yumurta-hasl', 'Haşlanmış yumurta'),
      item('yumurta', 'Yumurta (bütün, çiğ)'),
      item('sut', 'Süt (tam yağlı)', aliases: ['inek sütü']),
      item('inek-pey', 'Peynir (inek, taze)'),
      item('beyaz-peynir', 'Beyaz peynir', aliases: ['süzme peynir']),
      item('yulaf', 'Yulaf ezmesi'),
    ]);

    List<String> ids(String query, {int limit = 8}) =>
        [for (final f in catalog.search(query, limit: limit)) f.id];

    test('"SUT" Süt kaydını bulur', () {
      expect(ids('SUT'), ['sut']);
      expect(ids('süt'), ['sut']);
    });

    test('"yumurta" ilk sonuç yumurtadır; sıra ad öneki, ad içi, takma ad', () {
      expect(ids('yumurta'), ['yumurta', 'yumurta-hasl', 'omlet']);
    });

    test('"İnek" büyük/küçük İ ve ı farkından bağımsızdır', () {
      for (final query in ['İnek', 'inek', 'INEK', 'ınek']) {
        // Adında geçen (Peynir inek) takma adda geçenden (Süt) önce gelir.
        expect(ids(query), ['inek-pey', 'sut'], reason: query);
      }
    });

    test('boş ve yalnız boşluk sorgusu boş liste döner', () {
      expect(ids(''), isEmpty);
      expect(ids('   '), isEmpty);
    });

    test('eşleşme yoksa boş liste döner', () {
      expect(ids('zzzz'), isEmpty);
    });

    test('limit sonuç sayısını sınırlar; sıfır ve negatif boş döner', () {
      expect(ids('e', limit: 3), hasLength(3));
      expect(ids('e', limit: 0), isEmpty);
      expect(ids('e', limit: -1), isEmpty);
    });

    test('sözcükler sırasız aranır', () {
      expect(ids('peynir beyaz'), ['beyaz-peynir']);
    });

    test('takma adla bulur', () {
      expect(ids('suzme'), ['beyaz-peynir']);
    });

    test('regex karakterleri sorguyu bozmaz', () {
      expect(ids('(bütün'), ['yumurta']);
      expect(ids('.*'), isEmpty);
    });
  });

  group('FoodCatalog.load', () {
    test('paketten okur ve bozuk satırı atlar', () async {
      final bundle = _MemoryBundle({
        FoodCatalog.assetPath: jsonEncode([
          row('a', 'Armut'),
          {'id': 'b', 'name': 'Bozuk'},
          'satır değil',
          row('c', 'Çilek'),
        ]),
      });
      final catalog = await FoodCatalog.load(bundle);
      expect([for (final f in catalog.items) f.id], ['a', 'c']);
      expect(catalog.search('cilek').single.name, 'Çilek');
    });

    test('dizi olmayan JSON FormatException fırlatır', () {
      final bundle = _MemoryBundle({FoodCatalog.assetPath: '{"a": 1}'});
      expect(FoodCatalog.load(bundle), throwsFormatException);
    });

    test('dosya yoksa hata verir', () {
      expect(FoodCatalog.load(_MemoryBundle({})), throwsA(anything));
    });

    test('gerçek besin dosyasındaki hiçbir satır sessizce düşmez', () async {
      final raw = File(FoodCatalog.assetPath).readAsStringSync();
      final rows = jsonDecode(raw) as List<dynamic>;
      final catalog = await FoodCatalog.load(
        _MemoryBundle({FoodCatalog.assetPath: raw}),
      );
      expect(catalog.items, hasLength(rows.length));
    });
  });
}
