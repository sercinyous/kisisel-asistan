import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/food_item.dart';

/// Paketli besin listesi (`assets/data/foods_tr.json`) ve arama.
///
/// Liste sunucusuzdur: çevrimdışı çalışır, demoda ve testte aynı dosya
/// kullanılır. Arama Türkçe karakter ve büyük/küçük harf duyarsızdır.
class FoodCatalog {
  FoodCatalog._(this._entries);

  /// Hazır besin satırlarından katalog kurar (testler ve demo için).
  factory FoodCatalog.fromItems(List<FoodItem> items) => FoodCatalog._([
        for (final item in items)
          _Entry(
            item: item,
            name: normalize(item.name),
            aliases: [
              for (final alias in item.aliases)
                if (normalize(alias).isNotEmpty) normalize(alias),
            ],
          ),
      ]);

  static const String assetPath = 'assets/data/foods_tr.json';

  /// [bundle]'dan listeyi okur. Dosyanın kendisi (JSON dizisi değilse) bozuksa
  /// [FormatException] fırlatır; tek bir bozuk satır atlanır, geri kalanı
  /// kullanılır.
  static Future<FoodCatalog> load(AssetBundle bundle) async {
    final raw = await bundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Besin listesi bir JSON dizisi olmalı.');
    }
    final items = <FoodItem>[];
    for (final row in decoded) {
      if (row is! Map<String, dynamic>) continue;
      try {
        items.add(FoodItem.fromMap(row));
      } on FormatException {
        continue;
      }
    }
    return FoodCatalog.fromItems(items);
  }

  final List<_Entry> _entries;

  /// Listedeki tüm satırlar (dosya sırasıyla).
  List<FoodItem> get items =>
      List.unmodifiable([for (final entry in _entries) entry.item]);

  /// [category] kategorisindeki besinler (dosya sırasıyla).
  List<FoodItem> inCategory(String category) => [
        for (final entry in _entries)
          if (entry.item.categories.contains(category)) entry.item,
      ];

  /// Kimliğe göre besin; yoksa `null`.
  FoodItem? byId(String id) {
    for (final entry in _entries) {
      if (entry.item.id == id) return entry.item;
    }
    return null;
  }

  static const Map<String, String> _fold = {
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ç': 'c',
    'ç': 'c',
    'Ğ': 'g',
    'ğ': 'g',
    'Ö': 'o',
    'ö': 'o',
    'Ş': 's',
    'ş': 's',
    'Ü': 'u',
    'ü': 'u',
    'Â': 'a',
    'â': 'a',
    'Î': 'i',
    'î': 'i',
    'Û': 'u',
    'û': 'u',
  };

  /// Aramada iki tarafa da uygulanan sadeleştirme: küçük harf (Türkçe `İ/I/ı`
  /// hepsi `i`), `ç→c ğ→g ö→o ş→s ü→u`, art arda boşluk tek boşluk.
  /// Dart'ın `toLowerCase`'i `İ`'yi "i + birleşik nokta" yaptığı için harfler
  /// elle eşlenir.
  static String normalize(String input) {
    final out = StringBuffer();
    var pendingSpace = false;
    for (final rune in input.runes) {
      // U+0307 birleşik nokta: "İ" ayrıştırılmış yazıldığında kalan artık.
      if (rune == 0x307) continue;
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) {
        pendingSpace = out.isNotEmpty;
        continue;
      }
      if (pendingSpace) {
        out.write(' ');
        pendingSpace = false;
      }
      out.write(_fold[char] ?? char.toLowerCase());
    }
    return out.toString();
  }

  /// Sorguya uyan en çok [limit] besin. Sıra: adı sorguyla başlayanlar, adında
  /// geçenler, takma adında geçenler; her grupta liste sırası korunur. Birden
  /// çok sözcüklü sorguda sözcükler sırasız aranır ("peynir beyaz").
  /// Boş sorgu boş liste döner.
  List<FoodItem> search(String query, {int limit = 8}) {
    final q = normalize(query);
    if (q.isEmpty || limit <= 0) return const [];
    final tokens = q.split(' ');

    final hits = <(int, int)>[];
    for (final (index, entry) in _entries.indexed) {
      final tier = _tier(entry, q, tokens);
      if (tier != null) hits.add((tier, index));
    }
    hits.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final hit in hits.take(limit)) _entries[hit.$2].item];
  }

  static int? _tier(_Entry entry, String q, List<String> tokens) {
    if (entry.name.startsWith(q)) return 0;
    if (entry.name.contains(q) || _containsAll(entry.name, tokens)) return 1;
    for (final alias in entry.aliases) {
      if (alias.contains(q) || _containsAll(alias, tokens)) return 2;
    }
    return null;
  }

  static bool _containsAll(String text, List<String> tokens) =>
      tokens.every(text.contains);
}

class _Entry {
  const _Entry({
    required this.item,
    required this.name,
    required this.aliases,
  });

  final FoodItem item;

  /// [FoodCatalog.normalize] uygulanmış ad ve takma adlar.
  final String name;
  final List<String> aliases;
}

/// Paketli besin listesi; ilk kullanımda bir kez okunur ve uygulama boyunca
/// bellekte kalır.
final foodCatalogProvider = FutureProvider<FoodCatalog>(
  (ref) => FoodCatalog.load(rootBundle),
);
