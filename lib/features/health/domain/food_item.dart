/// Besin listesindeki bir porsiyon ölçüsü ("1 adet" = 50 g).
class FoodPortion {
  const FoodPortion({required this.name, required this.grams});

  factory FoodPortion.fromMap(Map<String, dynamic> map) {
    final name = (map['name'] as String).trim();
    final grams = (map['grams'] as num).toDouble();
    if (name.isEmpty || !grams.isFinite || grams <= 0) {
      throw FormatException('Geçersiz porsiyon: $map');
    }
    return FoodPortion(name: name, grams: grams);
  }

  /// "1 adet", "1 su bardağı", "1 dilim"
  final String name;
  final double grams;

  /// Başında sayı olan ad: "1 adet", "2 dilim", "0,5 bardak".
  static final RegExp _leadingCount = RegExp(r'^(\d+(?:[.,]\d+)?)\s+(\S.*)$');

  /// [count] porsiyonun okunur adı: "1 adet" için 2 → "2 adet", "1 dilim"
  /// için 3 → "3 dilim". Adın başında sayı yoksa "3 × Orta boy".
  String describe(int count) {
    final match = _leadingCount.firstMatch(name);
    if (match == null) return count == 1 ? name : '$count × $name';
    final base = double.parse(match.group(1)!.replaceAll(',', '.'));
    return '${_number(base * count)} ${match.group(2)}';
  }

  static String _number(double value) {
    final rounded = (value * 100).round() / 100;
    if (rounded == rounded.truncateToDouble()) return rounded.toInt().toString();
    return rounded.toString().replaceAll('.', ',');
  }

  @override
  bool operator ==(Object other) =>
      other is FoodPortion && other.name == name && other.grams == grams;

  @override
  int get hashCode => Object.hash(name, grams);
}

/// Belirli bir gram için hesaplanmış enerji ve makrolar.
class FoodMacros {
  const FoodMacros({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double kcal;

  /// Kaynağında makro yoksa `null` (yalnızca kalori bilinir).
  final double? protein;
  final double? carbs;
  final double? fat;
}

/// Besin seçicideki kategori adları (kullanıcı listesi, sırası korunur).
abstract final class FoodCategories {
  static const List<String> all = [
    'İçecekler',
    'Haşlanmış Yiyecekler',
    'Kızartılmış Yiyecekler',
    'Temel Gıdalar',
    'Meyveler',
    'Sebzeler',
    'Kahvaltılık Ürünler',
    'Öğle Atıştırmalıkları',
    'Akşam Öğünleri',
  ];
}

/// Paketli besin listesinin (`assets/data/foods_tr.json`) bir satırı.
/// Değerler 100 g içindir.
class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    required this.category,
    required this.kcal100,
    required this.protein100,
    required this.carbs100,
    required this.fat100,
    this.aliases = const [],
    this.categories = const [],
    this.note,
    this.portions = const [],
    this.source = '',
    this.verification = '',
  });

  /// JSON satırından okur; zorunlu alan eksik ya da türü yanlışsa
  /// [FormatException] fırlatır.
  factory FoodItem.fromMap(Map<String, dynamic> map) {
    try {
      final id = (map['id'] as String).trim();
      final name = (map['name'] as String).trim();
      if (id.isEmpty || name.isEmpty) {
        throw const FormatException('Besin satırında id ya da ad boş.');
      }
      double number(String key) {
        final value = (map[key] as num).toDouble();
        if (!value.isFinite || value < 0) {
          throw FormatException('"$key" geçersiz: $value');
        }
        return value;
      }

      double? optional(String key) => map[key] == null ? null : number(key);

      return FoodItem(
        id: id,
        name: name,
        aliases: [
          for (final alias in (map['aliases'] as List<dynamic>? ?? const []))
            alias as String,
        ],
        category: map['category'] as String? ?? 'diğer',
        kcal100: number('kcal100'),
        categories: [
          for (final category
              in (map['categories'] as List<dynamic>? ?? const []))
            category as String,
        ],
        note: (map['note'] as String?)?.trim().isEmpty ?? true
            ? null
            : (map['note'] as String).trim(),
        protein100: optional('protein100'),
        carbs100: optional('carbs100'),
        fat100: optional('fat100'),
        portions: [
          for (final portion
              in (map['portions'] as List<dynamic>? ?? const []))
            FoodPortion.fromMap(portion as Map<String, dynamic>),
        ],
        source: map['source'] as String? ?? '',
        verification: map['verification'] as String? ?? '',
      );
    } on FormatException {
      rethrow;
    } on TypeError catch (error) {
      throw FormatException('Besin satırı okunamadı: $error');
    }
  }

  final String id;
  final String name;

  /// Arama için ek adlar ("patates" için "kartof").
  final List<String> aliases;
  final String category;
  final double kcal100;

  /// 100 g makrolar; kaynağında yoksa `null`.
  final double? protein100;
  final double? carbs100;
  final double? fat100;
  final List<FoodPortion> portions;

  /// Seçicideki kategoriler ([FoodCategories.all] adları); bir besin birden
  /// çok kategoride olabilir.
  final List<String> categories;

  /// Uyarı notu (ör. kızartmalarda "Yağ miktarına göre değişir").
  final String? note;

  /// Üç makro da biliniyor mu.
  bool get hasMacros => protein100 != null && carbs100 != null && fat100 != null;

  /// Varsayılan porsiyon: listedeki ilk porsiyon, yoksa 100 g.
  FoodPortion get defaultPortion =>
      portions.isNotEmpty ? portions.first : const FoodPortion(name: '100 g', grams: 100);

  /// `USDA FDC kimlik | TürKomp kod` biçiminde kaynak notu.
  final String source;

  /// "iki kaynak" | "tek kaynak" | "yaklaşık"
  final String verification;

  /// [grams] gram için değerler. Gram sonlu ve pozitif değilse hepsi 0.
  FoodMacros forGrams(double grams) {
    final g = grams.isFinite && grams > 0 ? grams : 0.0;
    return FoodMacros(
      kcal: kcal100 * g / 100,
      protein: protein100 == null ? null : protein100! * g / 100,
      carbs: carbs100 == null ? null : carbs100! * g / 100,
      fat: fat100 == null ? null : fat100! * g / 100,
    );
  }
}
