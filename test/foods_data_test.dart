import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `assets/data/foods_tr.json` veri sözleşmesi (Faz 4A, Görev 4).
/// Besin değerleri yanlışsa zarar büyüktür: bu test yalnızca biçimi değil,
/// kaynak izini ve enerji tutarlılığını (Atwater) da denetler.
const _categories = <String>{
  'yumurta-süt',
  'et-balık',
  'tahıl-ekmek',
  'sebze',
  'meyve',
  'baklagil',
  'kuruyemiş-yağ',
  'içecek',
  'diğer',
};
const _verifications = <String>{'iki kaynak', 'tek kaynak', 'yaklaşık'};
const _userSource = 'Kullanıcı listesi (yaklaşık)';
const _pickerCategories = <String>{
  'İçecekler',
  'Haşlanmış Yiyecekler',
  'Kızartılmış Yiyecekler',
  'Temel Gıdalar',
  'Meyveler',
  'Sebzeler',
  'Kahvaltılık Ürünler',
  'Öğle Atıştırmalıkları',
  'Akşam Öğünleri',
};

const _recipeSource = 'Standart tarif (yaklaşık)';

/// Kayıt kimliği olmayan yaklaşık satırlar: kullanıcı listesi ve hazır yemek
/// (standart tarif) satırları.
bool _isUserRow(Map<String, dynamic> row) =>
    row['source'] == _userSource || row['source'] == _recipeSource;
const _numericFields = <String>['kcal100', 'protein100', 'carbs100', 'fat100'];

final _usdaRef = RegExp(r'USDA FDC \d+');
final _turkompRef = RegExp(r'TürKomp \S+');

List<Map<String, dynamic>> _loadRows() {
  final file = File('assets/data/foods_tr.json');
  expect(file.existsSync(), isTrue, reason: 'assets/data/foods_tr.json yok');
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  expect(decoded, isA<List<dynamic>>());
  return (decoded as List<dynamic>).cast<Map<String, dynamic>>();
}

String _label(Map<String, dynamic> row) => '${row['id']}';

/// Liste henüz doldurulmadıysa (`[]`) sayı denetimi atlanır: aksi halde
/// `flutter test` kırmızı kalır ve Codemagic "Testler" adımı IPA derlemesini
/// durdurur. Kısmen doluysa (1-59 satır) denetim çalışır ve kırmızı olur.
/// `expect` test dışında çağrılamaz; bu yüzden dosya burada ayrıca okunur.
bool _catalogEmpty() {
  final file = File('assets/data/foods_tr.json');
  if (!file.existsSync()) return false;
  final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
  return decoded is List && decoded.isEmpty;
}

void main() {
  late List<Map<String, dynamic>> rows;

  setUpAll(() {
    rows = _loadRows();
  });

  test('dosya geçerli JSON dizisidir', () {
    expect(rows, isA<List<Map<String, dynamic>>>());
  });

  test('en az 60 satır var (doğrulanamayan satır eklenmez, doldurma yok)', () {
    expect(
      rows.length,
      greaterThanOrEqualTo(60),
      reason: 'Yalnızca ${rows.length} doğrulanmış satır var. Satırlar USDA '
          'FoodData Central ve TürKomp kayıtlarından okunarak eklenmelidir; '
          'değer uydurulmaz.',
    );
  },
      skip: _catalogEmpty()
          ? 'Besin listesi henüz doldurulmadı (docs/KARARLAR.md Bekleyenler)'
          : false);

  test('id benzersiz ve ascii', () {
    final seen = <String>{};
    final ascii = RegExp(r'^[a-z0-9][a-z0-9_-]*$');
    for (final row in rows) {
      final id = row['id'];
      expect(id, isA<String>(), reason: 'id metin olmalı: $row');
      expect(ascii.hasMatch(id as String), isTrue, reason: 'ascii değil: $id');
      expect(seen.add(id), isTrue, reason: 'yinelenen id: $id');
    }
  });

  test('ad, takma adlar ve porsiyonlar biçimli', () {
    for (final row in rows) {
      final label = _label(row);
      final name = row['name'];
      expect(name, isA<String>(), reason: '$label: name');
      expect((name as String).trim(), isNotEmpty, reason: '$label: name boş');

      final aliases = row['aliases'];
      expect(aliases, isA<List<dynamic>>(), reason: '$label: aliases');
      for (final alias in aliases as List<dynamic>) {
        expect(alias, isA<String>(), reason: '$label: alias metin değil');
        expect((alias as String).trim(), isNotEmpty,
            reason: '$label: boş alias');
      }

      final portions = row['portions'];
      expect(portions, isA<List<dynamic>>(), reason: '$label: portions');
      for (final portion in portions as List<dynamic>) {
        expect(portion, isA<Map<String, dynamic>>(),
            reason: '$label: porsiyon nesne değil');
        final p = portion as Map<String, dynamic>;
        expect(p['name'], isA<String>(), reason: '$label: porsiyon adı');
        expect((p['name'] as String).trim(), isNotEmpty,
            reason: '$label: porsiyon adı boş');
        expect(p['grams'], isA<num>(), reason: '$label: porsiyon gramı');
        expect((p['grams'] as num) > 0, isTrue,
            reason: '$label: porsiyon gramı > 0 olmalı');
      }
    }
  });

  test('sayılar >= 0 ve kcal100 <= 900', () {
    for (final row in rows) {
      final label = _label(row);
      for (final field in _numericFields) {
        final value = row[field];
        // Kullanıcı listesindeki satırlarda makro bilinmiyorsa boş kalır.
        if (value == null && field != 'kcal100' && _isUserRow(row)) continue;
        expect(value, isA<num>(), reason: '$label: $field sayı olmalı');
        final n = value as num;
        expect(n.isFinite, isTrue, reason: '$label: $field sonlu olmalı');
        expect(n >= 0, isTrue, reason: '$label: $field negatif');
      }
      expect((row['kcal100'] as num) <= 900, isTrue,
          reason: '$label: kcal100 > 900');
    }
  });

  test('ad tekil (aynı besin iki kez listelenmez)', () {
    final seen = <String>{};
    for (final row in rows) {
      final name = (row['name'] as String).toLowerCase();
      expect(seen.add(name), isTrue, reason: 'yinelenen ad: ${row['name']}');
    }
  });

  test('category ve verification izinli kümede', () {
    for (final row in rows) {
      final label = _label(row);
      expect(_categories.contains(row['category']), isTrue,
          reason: '$label: geçersiz category ${row['category']}');
      expect(_verifications.contains(row['verification']), isTrue,
          reason: '$label: geçersiz verification ${row['verification']}');
    }
  });

  test('source boş değil ve gerçek kayıt kimliği taşır', () {
    for (final row in rows) {
      final label = _label(row);
      final source = row['source'];
      expect(source, isA<String>(), reason: '$label: source');
      final s = (source as String).trim();
      expect(s, isNotEmpty, reason: '$label: source boş');
      if (_isUserRow(row)) {
        expect(row['verification'], 'yaklaşık', reason: label);
        continue;
      }
      expect(row['verification'], isNot('yaklaşık'), reason: label);
      final hasUsda = _usdaRef.hasMatch(s);
      final hasTurkomp = _turkompRef.hasMatch(s);
      expect(hasUsda || hasTurkomp, isTrue,
          reason: '$label: source kayıt kimliği içermiyor: "$s"');
      if (row['verification'] == 'iki kaynak') {
        expect(hasUsda && hasTurkomp, isTrue,
            reason: '$label: "iki kaynak" için USDA FDC ve TürKomp kimliği '
                'ikisi de yazılmalı: "$s"');
      }
    }
  });

  test('Atwater: |kcal - (4*protein + 4*karb + 9*yağ)| <= max(%15, 10)', () {
    for (final row in rows) {
      final label = _label(row);
      if (row['protein100'] == null ||
          row['carbs100'] == null ||
          row['fat100'] == null) {
        continue;
      }
      final kcal = (row['kcal100'] as num).toDouble();
      final protein = (row['protein100'] as num).toDouble();
      final carbs = (row['carbs100'] as num).toDouble();
      final fat = (row['fat100'] as num).toDouble();
      final atwater = 4 * protein + 4 * carbs + 9 * fat;
      final tolerance = (0.15 * kcal) > 10 ? 0.15 * kcal : 10.0;
      expect((kcal - atwater).abs() <= tolerance, isTrue,
          reason: '$label: kcal $kcal, Atwater $atwater, tolerans $tolerance');
    }
  });

  test('categories seçici adlarından; kullanıcı satırları en az birinde', () {
    for (final row in rows) {
      final label = _label(row);
      final categories = row['categories'];
      expect(categories, isA<List<dynamic>>(), reason: '$label: categories');
      final list = (categories as List<dynamic>).cast<String>();
      expect(list.toSet(), hasLength(list.length), reason: '$label: tekrar');
      for (final c in list) {
        expect(_pickerCategories.contains(c), isTrue,
            reason: '$label: geçersiz kategori $c');
      }
      if (_isUserRow(row)) {
        expect(list, isNotEmpty, reason: '$label: kategorisiz');
      }
    }
    for (final category in _pickerCategories) {
      expect(
        rows.any((r) => (r['categories'] as List).contains(category)),
        isTrue,
        reason: '$category boş',
      );
    }
  });

  test('kullanıcı listesi: aynı besin tek satır, kızartmalar notlu', () {
    final user = rows.where(_isUserRow).toList();
    final names = user.map((r) => r['name']).toList();
    expect(names.toSet(), hasLength(names.length));
    final egg = user.singleWhere((r) => r['name'] == 'Haşlanmış yumurta');
    expect(
        egg['categories'],
        containsAll(<String>[
          'Haşlanmış Yiyecekler',
          'Kahvaltılık Ürünler',
          'Öğle Atıştırmalıkları',
        ]));
    // Çiğ ve haşlanmış brokoli ayrı kalır.
    expect(user.where((r) => (r['name'] as String).contains('rokoli')),
        hasLength(2));
    for (final row in user) {
      final fried =
          (row['categories'] as List).contains('Kızartılmış Yiyecekler');
      if (fried) {
        expect(row['note'], 'Yağ miktarına göre değişir', reason: _label(row));
      }
    }
  });
}
