import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_widgets.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_chart.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/trend_screen.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

/// 19 Kasım 2026 Perşembe; hafta 16–22 Kasım.
final _mon = DateTime(2026, 11, 16);
final _tue = DateTime(2026, 11, 17);
final _thu = DateTime(2026, 11, 19);
DateTime _now = DateTime(2026, 11, 19, 12);

void main() {
  late FakeHealthRepository health;
  late FakeSettingsRepository settingsRepo;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    _now = DateTime(2026, 11, 19, 12);
    health = FakeHealthRepository();
    settingsRepo = FakeSettingsRepository();
  });

  DailyHealthMetric metric(DateTime day, {int steps = 0, int sleep = 0}) =>
      DailyHealthMetric(day: day, steps: steps, sleepMinutes: sleep);

  DailyNutritionTotal meals(
    DateTime day,
    double kcal,
    double protein, {
    int entries = 2,
  }) =>
      DailyNutritionTotal(
        day: day,
        calories: kcal,
        proteinG: protein,
        entryCount: entries,
      );

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        trendClockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpTrend(
    WidgetTester tester, {
    TrendMetric metric = TrendMetric.steps,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: TrendScreen(initialMetric: metric),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String bigValue(WidgetTester tester, String key) =>
      tester.widget<HealthBigValue>(find.byKey(Key(key))).value;

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('trend-next'))).onPressed !=
      null;

  group('TrendQuery', () {
    test('hafta Pazartesi-Pazar, pencere hafta içi hangi günden olursa olsun',
        () {
      for (final anchor in [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 19, 23, 59),
        DateTime(2026, 11, 22),
      ]) {
        final days = TrendQuery(
          metric: TrendMetric.steps,
          period: TrendPeriod.week,
          anchor: anchor,
        ).days;
        expect(days, hasLength(7));
        expect(days.first, DateTime(2026, 11, 16));
        expect(days.first.weekday, DateTime.monday);
        expect(days.last, DateTime(2026, 11, 22));
        expect(days.last.weekday, DateTime.sunday);
      }
    });

    test('ay 1. günden son güne: 28 / 29 / 30 / 31 gün', () {
      const cases = {
        (2026, 2): 28,
        (2028, 2): 29,
        (2026, 4): 30,
        (2026, 1): 31,
        (2026, 12): 31,
      };
      cases.forEach((ym, length) {
        final q = TrendQuery(
          metric: TrendMetric.steps,
          period: TrendPeriod.month,
          anchor: DateTime(ym.$1, ym.$2, 15, 9),
        );
        expect(q.days, hasLength(length), reason: '$ym');
        expect(q.from, DateTime(ym.$1, ym.$2, 1));
        expect(q.to, DateTime(ym.$1, ym.$2, length));
      });
    });

    test('shifted ay sonundan ayı atlamaz, haftayı 7 gün kaydırır', () {
      final jan31 = TrendQuery(
        metric: TrendMetric.steps,
        period: TrendPeriod.month,
        anchor: DateTime(2026, 1, 31),
      );
      expect(jan31.shifted(1).from, DateTime(2026, 2, 1));
      expect(jan31.shifted(-1).from, DateTime(2025, 12, 1));

      final week = TrendQuery(
        metric: TrendMetric.steps,
        period: TrendPeriod.week,
        anchor: _thu,
      );
      expect(week.shifted(-1).from, DateTime(2026, 11, 9));
      expect(week.shifted(1).from, DateTime(2026, 11, 23));
    });

    test('değer eşitliği: saat bileşeni yok sayılır, alanlar ayırır', () {
      TrendQuery q(DateTime a, {TrendMetric m = TrendMetric.steps}) =>
          TrendQuery(metric: m, period: TrendPeriod.week, anchor: a);
      expect(q(_thu), q(DateTime(2026, 11, 19, 15)));
      expect(q(_thu).hashCode, q(DateTime(2026, 11, 19, 15)).hashCode);
      expect(q(_thu) == q(_mon), isFalse);
      expect(q(_thu) == q(_thu, m: TrendMetric.sleep), isFalse);
    });

    test('isCurrent: bugünü içeren dönem', () {
      final week = TrendQuery(
        metric: TrendMetric.steps,
        period: TrendPeriod.week,
        anchor: _mon,
      );
      expect(week.isCurrent(_thu), isTrue);
      expect(week.isCurrent(DateTime(2026, 11, 23)), isFalse);
      expect(week.isCurrent(DateTime(2026, 11, 15)), isFalse);
    });
  });

  group('trendStatsProvider', () {
    TrendQuery week(TrendMetric m) =>
        TrendQuery(metric: m, period: TrendPeriod.week, anchor: _thu);

    test('adım: tutan, tutmayan, verisiz ve gelecek gün; bugün tutturduysa tutar',
        () async {
      health.metrics = [
        metric(_mon, steps: 12000),
        metric(_tue, steps: 8000),
        metric(_thu, steps: 10500),
      ];
      final stats = await makeContainer()
          .read(trendStatsProvider(week(TrendMetric.steps)).future);

      expect(stats.days.map((d) => d.status), [
        DayStatus.hit,
        DayStatus.miss,
        DayStatus.noData,
        DayStatus.hit,
        DayStatus.future,
        DayStatus.future,
        DayStatus.future,
      ]);
      expect(stats.hitDays, 2);
      expect(stats.dataDays, 3);
      expect(stats.percent, closeTo(2 / 3, 1e-9));
      expect(stats.average, closeTo(10166.67, 0.01));
      expect(stats.currentStreak, 1);
      expect(stats.longestStreak, 1);
    });

    test('bugün hedefin altındaysa devam ediyor: paydada ve ortalamada yok',
        () async {
      health.metrics = [
        metric(_mon, steps: 12000),
        metric(_tue, steps: 8000),
        metric(_thu, steps: 4000),
      ];
      final stats = await makeContainer()
          .read(trendStatsProvider(week(TrendMetric.steps)).future);

      expect(stats.days[3].status, DayStatus.inProgress);
      expect(stats.hitDays, 1);
      expect(stats.dataDays, 2);
      expect(stats.average, 10000);
      expect(stats.currentStreak, 0);
    });

    test('sıfır adım ve sıfır uyku veri yok sayılır', () async {
      health.metrics = [metric(_mon, steps: 0, sleep: 0)];
      final container = makeContainer();
      final steps =
          await container.read(trendStatsProvider(week(TrendMetric.steps)).future);
      final sleep =
          await container.read(trendStatsProvider(week(TrendMetric.sleep)).future);

      for (final stats in [steps, sleep]) {
        expect(stats.days.first.status, DayStatus.noData);
        expect(stats.dataDays, 0);
        expect(stats.percent, isNull);
        expect(stats.average, isNull);
      }
    });

    test('uyku: hedefin %90\'ı tutar (405 dk), 404 dk tutmaz', () async {
      health.metrics = [
        metric(_mon, sleep: 405),
        metric(_tue, sleep: 404),
      ];
      final stats = await makeContainer()
          .read(trendStatsProvider(week(TrendMetric.sleep)).future);

      expect(stats.days[0].status, DayStatus.hit);
      expect(stats.days[1].status, DayStatus.miss);
    });

    test('kalori: yalnızca öğünü olan gün veridir; protein ayrı sayılır',
        () async {
      health.nutrition = [
        meals(_mon, 1900, 160),
        meals(_tue, 2300, 100),
        // Öğün kaydı yok (entryCount 0): veri değil.
        meals(DateTime(2026, 11, 18), 0, 0, entries: 0),
      ];
      final container = makeContainer();
      final q = week(TrendMetric.calories);
      final calories = await container.read(trendStatsProvider(q).future);
      final protein = await container.read(trendProteinStatsProvider(q).future);

      expect(calories.days[0].status, DayStatus.hit);
      expect(calories.days[1].status, DayStatus.miss);
      expect(calories.days[2].status, DayStatus.noData);
      expect(calories.dataDays, 2);
      expect(protein.days[0].status, DayStatus.hit);
      expect(protein.days[1].status, DayStatus.miss);
      expect(protein.hitDays, 1);
      expect(protein.dataDays, 2);
    });

    test('ay penceresi dönemin tüm günlerini verir, gelecek günler boş kalır',
        () async {
      final stats = await makeContainer().read(
        trendStatsProvider(
          TrendQuery(
            metric: TrendMetric.steps,
            period: TrendPeriod.month,
            anchor: _thu,
          ),
        ).future,
      );

      expect(stats.days, hasLength(30));
      expect(stats.days.first.day, DateTime(2026, 11, 1));
      expect(stats.days.last.day, DateTime(2026, 11, 30));
      expect(
        stats.days.where((d) => d.status == DayStatus.future),
        hasLength(11),
      );
    });

    test('geçmiş dönemde mevcut seri yok', () async {
      health.metrics = [metric(DateTime(2026, 11, 10), steps: 12000)];
      final stats = await makeContainer().read(
        trendStatsProvider(week(TrendMetric.steps).shifted(-1)).future,
      );

      expect(stats.currentStreak, isNull);
      expect(stats.longestStreak, 1);
    });
  });

  group('TrendScreen', () {
    testWidgets('perşembe + sahte veri: 2/3 gün ve yüzde görünür',
        (tester) async {
      health.metrics = [
        metric(_mon, steps: 12000),
        metric(_tue, steps: 8000),
        metric(_thu, steps: 10500),
      ];
      await pumpTrend(tester);

      expect(find.text('Trend'), findsOneWidget);
      expect(bigValue(tester, 'trend-hit-count'), '2/3');
      expect(find.text('%67'), findsOneWidget);
      expect(textOf(tester, 'trend-period-label'), '16–22 Kas 2026');
      expect(textOf(tester, 'trend-average'), '10.167');
      expect(textOf(tester, 'trend-streak'), '1 gün');
      expect(find.textContaining('1 gün veri yok'), findsOneWidget);
      expect(find.byType(TrendBarChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bugün hedefin altında: 1/2, devam ediyor notu',
        (tester) async {
      health.metrics = [
        metric(_mon, steps: 12000),
        metric(_tue, steps: 8000),
        metric(_thu, steps: 4000),
      ];
      await pumpTrend(tester);

      expect(bigValue(tester, 'trend-hit-count'), '1/2');
      expect(find.text('%50'), findsOneWidget);
      expect(find.text('Bugün devam ediyor, hesaba girmedi.'), findsOneWidget);
    });

    testWidgets('yalnızca bugün ve hedef altında: yüzde ve 0/0 yok',
        (tester) async {
      health.metrics = [metric(_thu, steps: 3000)];
      await pumpTrend(tester);

      expect(bigValue(tester, 'trend-hit-count'), '—');
      expect(find.byKey(const Key('trend-percent')), findsNothing);
      expect(find.text('Henüz değerlendirilen gün yok.'), findsOneWidget);
      expect(textOf(tester, 'trend-average'), '—');
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('0/0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('veri yokken boş durum metni; sahte övgü ve yüzde yok',
        (tester) async {
      await pumpTrend(tester, textScale: 1.3);

      expect(find.text('Bu dönemde veri yok'), findsOneWidget);
      expect(find.byKey(const Key('trend-hit-count')), findsNothing);
      expect(find.byType(TrendBarChart), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);

      await tapText(tester, 'Kalori');
      expect(find.text('Bu dönemde veri yok'), findsOneWidget);
      await tapText(tester, 'Ay');
      expect(find.text('Bu dönemde veri yok'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"sonraki" oku geçerli dönemde pasif, önceki dönemden dönünce açılır',
        (tester) async {
      health.metrics = [
        metric(_mon, steps: 12000),
        metric(DateTime(2026, 11, 10), steps: 11000),
      ];
      await pumpTrend(tester);

      expect(nextEnabled(tester), isFalse);
      expect(textOf(tester, 'trend-period-label'), '16–22 Kas 2026');

      await tester.tap(find.byKey(const Key('trend-prev')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'trend-period-label'), '9–15 Kas 2026');
      expect(nextEnabled(tester), isTrue);
      // Geçmiş dönemde mevcut seri gösterilmez, en uzun seri gösterilir.
      expect(find.text('Bu dönemin en uzun serisi'), findsOneWidget);
      expect(find.textContaining('Mevcut seri'), findsNothing);
      expect(bigValue(tester, 'trend-hit-count'), '1/1');

      await tester.tap(find.byKey(const Key('trend-next')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'trend-period-label'), '16–22 Kas 2026');
      expect(nextEnabled(tester), isFalse);
      expect(find.textContaining('Mevcut seri'), findsOneWidget);
    });

    testWidgets('ay görünümü: etiket ve gezinme, ay sınırında 28 günlük ay',
        (tester) async {
      health.metrics = [metric(_mon, steps: 12000)];
      await pumpTrend(tester);

      await tapText(tester, 'Ay');
      expect(textOf(tester, 'trend-period-label'), 'Kasım 2026');
      expect(nextEnabled(tester), isFalse);
      expect(bigValue(tester, 'trend-hit-count'), '1/1');

      // Şubat 2026: 28 gün; 9 ay geriye gidilir, veri yok.
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byKey(const Key('trend-prev')));
        await tester.pumpAndSettle();
      }
      expect(textOf(tester, 'trend-period-label'), 'Şubat 2026');
      expect(find.text('Bu dönemde veri yok'), findsOneWidget);
      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('hafta aralığı ay sınırını aşınca iki ay adı yazar',
        (tester) async {
      await pumpTrend(tester);
      // 16–22 Kas'tan 3 hafta geri: 26 Eki – 1 Kas.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('trend-prev')));
        await tester.pumpAndSettle();
      }
      expect(textOf(tester, 'trend-period-label'), '26 Eki – 1 Kas 2026');
    });

    testWidgets('kalori sekmesi: kalori bandı ve protein tutturulan gün satırı',
        (tester) async {
      health.nutrition = [
        meals(_mon, 1900, 160),
        meals(_tue, 2300, 100),
        meals(_thu, 1200, 80),
      ];
      await pumpTrend(tester, metric: TrendMetric.calories);

      // Pzt tutar (%95), Sal tutmaz (%115), bugün 1200 devam ediyor.
      expect(bigValue(tester, 'trend-hit-count'), '1/2');
      expect(textOf(tester, 'trend-average'), '2.100 kcal');
      expect(find.text('Protein hedefi'), findsOneWidget);
      expect(textOf(tester, 'trend-protein-days'), '1/2 gün');
      expect(
        find.textContaining('Bant: hedefin %85–%110\'u'),
        findsOneWidget,
      );
    });

    testWidgets(
        'protein hedefi 0 ise protein satırı gösterilmez (hedefsiz "0/2 gün" yok)',
        (tester) async {
      settingsRepo.settings =
          const UserSettings.defaults().copyWith(dailyProteinG: 0);
      health.nutrition = [meals(_mon, 1900, 120), meals(_tue, 2000, 130)];
      await pumpTrend(tester, metric: TrendMetric.calories);

      // Kalori bandı hâlâ çalışır; protein satırı ve çelişen sayı yok.
      expect(bigValue(tester, 'trend-hit-count'), '2/2');
      expect(find.text('Protein hedefi'), findsNothing);
      expect(find.byKey(const Key('trend-protein-days')), findsNothing);
      expect(find.textContaining('Günlük 0 g'), findsNothing);
    });

    testWidgets('adım ve uyku sekmelerinde protein satırı yok', (tester) async {
      health.metrics = [metric(_mon, steps: 12000, sleep: 450)];
      await pumpTrend(tester);

      expect(find.text('Protein hedefi'), findsNothing);
      await tapText(tester, 'Uyku');
      expect(find.text('Protein hedefi'), findsNothing);
      expect(bigValue(tester, 'trend-hit-count'), '1/1');
      expect(textOf(tester, 'trend-average'), '7 sa 30 dk');
      expect(find.textContaining('hedefin %90\'ı (6 sa 45 dk)'), findsOneWidget);
    });

    testWidgets('önceki döneme göre fark ortalamadan hesaplanır',
        (tester) async {
      health.metrics = [
        metric(DateTime(2026, 11, 9), steps: 9000),
        metric(_mon, steps: 12000),
        metric(_tue, steps: 8000),
        metric(_thu, steps: 10500),
      ];
      await pumpTrend(tester);

      // 10166,67 - 9000 = +1166,67
      expect(find.text('Önceki haftaya göre +1.167'), findsOneWidget);
    });

    testWidgets('uyku farkı süre olarak yazılır, başa "0 sa" konmaz',
        (tester) async {
      health.metrics = [
        metric(DateTime(2026, 11, 9), sleep: 450),
        metric(_mon, sleep: 472),
      ];
      await pumpTrend(tester, metric: TrendMetric.sleep);

      expect(find.text('Önceki haftaya göre +22 dk'), findsOneWidget);
    });

    testWidgets('önceki dönemle aynı ortalama "aynı" yazar', (tester) async {
      health.metrics = [
        metric(DateTime(2026, 11, 9), steps: 9000),
        metric(_mon, steps: 9000),
      ];
      await pumpTrend(tester);

      expect(find.text('Önceki haftayla aynı'), findsOneWidget);
    });

    testWidgets('önceki dönemde veri yoksa karşılaştırma satırı çıkmaz',
        (tester) async {
      health.metrics = [metric(_mon, steps: 12000)];
      await pumpTrend(tester);

      expect(find.textContaining('Önceki hafta'), findsNothing);
    });

    testWidgets('okuma hatasında hata metni, tekrar dene veriyi yükler',
        (tester) async {
      health.metrics = [metric(_mon, steps: 12000)];
      health.fetchError = Exception('ağ yok');
      await pumpTrend(tester);

      expect(find.text('Trend verisi yüklenemedi.'), findsOneWidget);
      health.fetchError = null;
      await tapText(tester, 'Tekrar dene');

      expect(find.text('Trend verisi yüklenemedi.'), findsNothing);
      expect(bigValue(tester, 'trend-hit-count'), '1/1');
    });

    testWidgets('gün değişimi: geçerli dönemdeyken öne gelince yeni haftaya geçer',
        (tester) async {
      health.metrics = [metric(_mon, steps: 12000)];
      await pumpTrend(tester);
      expect(textOf(tester, 'trend-period-label'), '16–22 Kas 2026');

      // Pazar gecesi geçilir; uygulama pazartesi sabahı öne gelir.
      _now = DateTime(2026, 11, 23, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(textOf(tester, 'trend-period-label'), '23–29 Kas 2026');
      expect(nextEnabled(tester), isFalse);
      expect(find.text('Bu dönemde veri yok'), findsOneWidget);
    });

    testWidgets('gün değişimi: geçmiş döneme bakan kullanıcı yerinde kalır',
        (tester) async {
      await pumpTrend(tester);
      await tester.tap(find.byKey(const Key('trend-prev')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'trend-period-label'), '9–15 Kas 2026');

      _now = DateTime(2026, 11, 23, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(textOf(tester, 'trend-period-label'), '9–15 Kas 2026');
      expect(nextEnabled(tester), isTrue);
    });

    for (final metric in TrendMetric.values) {
      testWidgets('375x667 ve 1.3 metin ölçeğinde taşmaz: ${metric.name}',
          (tester) async {
        health.metrics = [
          for (var i = 0; i < 19; i++)
            DailyHealthMetric(
              day: DateTime(2026, 11, 1 + i),
              steps: 6000 + i * 700,
              sleepMinutes: 380 + i * 8,
            ),
        ];
        health.nutrition = [
          for (var i = 0; i < 19; i++)
            meals(DateTime(2026, 11, 1 + i), 1500 + i * 90.0, 100 + i * 8.0),
        ];
        await pumpTrend(tester, metric: metric, textScale: 1.3);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byType(TrendBarChart));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tapText(tester, 'Ay');
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TrendBarChart));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Sayfanın sonuna kadar kaydır.
        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('açık temada da çizilir ve taşmaz', (tester) async {
      health.metrics = [metric(_mon, steps: 12000)];
      AppColors.palette = AppPalette.light;
      addTearDown(() => AppColors.palette = AppPalette.dark);
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 1334);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: makeContainer(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: const TrendScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(bigValue(tester, 'trend-hit-count'), '1/1');
      expect(tester.takeException(), isNull);
    });
  });

  group('TrendScreen.open', () {
    testWidgets('verilen metrik seçili açılır ve önbellek tazelenir',
        (tester) async {
      health.metrics = [metric(_mon, sleep: 450)];
      final container = makeContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => TrendScreen.open(context, TrendMetric.sleep),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      expect(find.text('Trend'), findsOneWidget);
      expect(bigValue(tester, 'trend-hit-count'), '1/1');
      expect(textOf(tester, 'trend-average'), '7 sa 30 dk');

      // Ekran kapanıp yeniden açılınca yeni veri görünür.
      await tester.pageBack();
      await tester.pumpAndSettle();
      health.metrics = [
        metric(_mon, sleep: 450),
        metric(_tue, sleep: 500),
      ];
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(bigValue(tester, 'trend-hit-count'), '2/2');
    });
  });
}
