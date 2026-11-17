import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_data.dart';
import 'package:kisisel_asistan/demo/demo_foods.dart';
import 'package:kisisel_asistan/features/health/data/food_catalog.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

/// Tarayıcı demosunun Faz 4A verisi: 60 günlük sağlık ve öğün geçmişi, dolu
/// profil, trend ve enerji ekranlarının gerçek hesaplarla anlamlı sayı
/// üretmesi ve besin aramasının demoda çalışması.
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

void main() {
  // Farklı ay uzunlukları ve ay başı/sonu: demo her gün açılabilir.
  final samples = <DateTime>[
    DateTime(2026, 11, 18, 15, 34),
    DateTime(2026, 12, 1, 9, 5),
    DateTime(2027, 2, 28, 21, 40),
    DateTime(2028, 3, 1, 12, 0),
  ];

  for (final now in samples) {
    group('demo verisi, ${AppDates.ymd(now)}', () {
      final today = AppDates.startOfDay(now);
      late DemoData data;
      late ProviderContainer container;

      setUp(() {
        data = DemoData.seed(now);
        container = ProviderContainer(
          overrides: [
            healthRepositoryProvider.overrideWithValue(data.health),
            settingsRepositoryProvider.overrideWithValue(data.settings),
            trendClockProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(container.dispose);
      });

      test('profil dolu: Enerji dengesi sayı gösterir', () async {
        final settings = await data.settings.fetch();
        expect(settings.profileComplete, isTrue);
        expect(settings.heightCm, demoHeightCm);
        expect(settings.birthYear, demoBirthYear);
        expect(settings.sex, demoSex);
      });

      test('sağlık ve öğün geçmişi 60 günü kapsar; son üç hafta eksiksiz',
          () async {
        final from = AppDates.addDays(today, -(demoHistoryDays - 1));
        final metrics = await data.health.fetchDailyMetrics(from, today);
        final nutrition = await data.health
            .fetchNutritionTotals(from, AppDates.endOfDay(today));

        // Bugün ve son üç hafta (raporların kapsadığı gün sayısı) tam.
        final recentFrom = AppDates.addDays(today, -20);
        final recentMetricDays = {
          for (final m in metrics)
            if (!m.day.isBefore(recentFrom)) m.day,
        };
        final recentMealDays = {
          for (final n in nutrition)
            if (!n.day.isBefore(recentFrom) && n.entryCount > 0) n.day,
        };
        expect(recentMetricDays, hasLength(21));
        expect(recentMealDays, hasLength(21));

        // Daha eski günlerin bazısında veri yok ("veri yok" günü görünür).
        expect(metrics.length, lessThan(demoHistoryDays));
        expect(nutrition.length, lessThan(demoHistoryDays));
        expect(metrics.first.day.isBefore(recentFrom), isTrue);
        expect(nutrition.first.day.isBefore(recentFrom), isTrue);
        expect(metrics.every((m) => m.steps > 0 && m.sleepMinutes > 0), isTrue);
        expect(nutrition.every((n) => n.entryCount > 0), isTrue);
        expect(metrics.last.day, today);
        expect(nutrition.last.day, today);
      });

      test('trend: adım, uyku ve kalori hem tutan hem tutmayan gün gösterir',
          () async {
        final months = [
          today,
          DateTime(today.year, today.month - 1, 15),
        ];
        for (final metric in TrendMetric.values) {
          var hit = 0;
          var dataDays = 0;
          for (final anchor in months) {
            final stats = await container.read(
              trendStatsProvider(TrendQuery(
                metric: metric,
                period: TrendPeriod.month,
                anchor: anchor,
              )).future,
            );
            hit += stats.hitDays;
            dataDays += stats.dataDays;
            if (stats.dataDays > 0) {
              expect(stats.percent, isNotNull);
              expect(stats.percent!.isFinite, isTrue);
              expect(stats.average!.isFinite, isTrue);
            }
          }
          expect(dataDays, greaterThan(15), reason: '${metric.name}: veri az');
          expect(hit, greaterThan(0), reason: '${metric.name}: hiç tutmuyor');
          expect(hit, lessThan(dataDays), reason: '${metric.name}: hep tutuyor');
        }
      });

      test('trend: protein ikincil satırı ve geçen ayın verisiz günleri',
          () async {
        final previousMonth = TrendQuery(
          metric: TrendMetric.calories,
          period: TrendPeriod.month,
          anchor: DateTime(today.year, today.month - 1, 15),
        );
        final protein =
            await container.read(trendProteinStatsProvider(previousMonth).future);
        expect(protein.dataDays, greaterThan(0));
        expect(protein.hitDays, lessThanOrEqualTo(protein.dataDays));
      });

      test('enerji: bir aylık aralıkta birden çok yorum ve boş günler',
          () async {
        final days = await container.read(
          energyRangeProvider((
            from: AppDates.addDays(today, -(demoHistoryDays - 1)),
            to: today,
          )).future,
        );
        expect(days, hasLength(demoHistoryDays));

        final verdicts = {for (final d in days) d.verdict};
        expect(verdicts, contains(EnergyVerdict.noMeals));
        expect(verdicts.length, greaterThanOrEqualTo(3),
            reason: 'yorum çeşitliliği: $verdicts');
        for (final d in days.where((d) => d.net != null)) {
          expect(d.net!.isFinite, isTrue);
          expect(d.basal.isFinite && d.basal > 0, isTrue);
        }
        // Öğünü olup sağlık satırı olmayan gün: "aktif kalori verisi yok".
        expect(
          days.any((d) => d.net != null && d.activeDataMissing),
          isTrue,
        );
        // Son üç haftada sağlık verisi eksik gün yok (bugün dahil).
        final recent = days.skip(days.length - 21);
        expect(recent.any((d) => d.activeDataMissing), isFalse);

        final summary = summarize(days);
        expect(summary.days, greaterThan(30));
        expect(summary.sumNet.isFinite, isTrue);
        expect(summary.estimatedFatKg.isFinite, isTrue);
      });

      test('enerji: bugünün kartı öğünlerle dolu', () async {
        final todayEnergy =
            await container.read(energyDayProvider(today).future);
        expect(todayEnergy, isNotNull);
        expect(todayEnergy!.isToday, isTrue);
        expect(todayEnergy.verdict, isNot(EnergyVerdict.noMeals));
        expect(todayEnergy.intake, 880);
      });
    });
  }

  group('demo besin listesi', () {
    test('örnek liste Türkçe karakterden bağımsız aranır', () {
      final catalog = demoFoodCatalog();
      expect(catalog.items.length, greaterThanOrEqualTo(10));
      expect(catalog.search('SUT').first.name, startsWith('Süt'));
      expect(catalog.search('yumurta').first.name, startsWith('Yumurta'));
      expect(catalog.search('İnek').map((f) => f.name), contains('Süt (tam yağlı)'));
      expect(catalog.search(''), isEmpty);
      // 1 adet yumurta = 50 g: kcal100 143 → 71,5.
      final egg = catalog.search('yumurta').first;
      expect(egg.portions.first.grams, 50);
      expect(egg.forGrams(50).kcal, closeTo(71.5, 0.01));
    });

    test('örnek satırlar doğrulanmış veri gibi görünmez', () {
      for (final item in demoFoodCatalog().items) {
        expect(item.verification, 'demo');
        expect(item.source, contains('doğrulanmamış'));
        expect(item.id, startsWith('demo-'));
      }
    });

    test('paketli liste boşsa ya da okunamazsa örnek liste kullanılır',
        () async {
      final empty = await loadDemoFoodCatalog(
        _MemoryBundle({FoodCatalog.assetPath: '[]'}),
      );
      expect(empty.items, isNotEmpty);
      expect(empty.items.first.id, startsWith('demo-'));

      final missing = await loadDemoFoodCatalog(_MemoryBundle({}));
      expect(missing.items, isNotEmpty);

      final broken = await loadDemoFoodCatalog(
        _MemoryBundle({FoodCatalog.assetPath: '{"bu": "dizi değil"}'}),
      );
      expect(broken.items, isNotEmpty);
    });

    test('paketli liste doluysa o kullanılır', () async {
      final catalog = await loadDemoFoodCatalog(
        _MemoryBundle({
          FoodCatalog.assetPath: jsonEncode([
            {
              'id': 'gercek-pirinc',
              'name': 'Pirinç',
              'category': 'tahıl-ekmek',
              'kcal100': 130,
              'protein100': 2.7,
              'carbs100': 28,
              'fat100': 0.3,
            },
          ]),
        }),
      );
      expect(catalog.items.map((f) => f.id), ['gercek-pirinc']);
    });
  });
}
