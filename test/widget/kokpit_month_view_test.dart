import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_format.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_widgets.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

import '../helpers/kokpit_fakes.dart';
import '../helpers/test_fonts.dart';

DateTime today() => AppDates.startOfDay(DateTime.now());
DateTime thisMonth() => DateTime(today().year, today().month);

Routine monthly(String id, String title, int day, {int? hour}) => Routine(
      id: id,
      title: title,
      scope: Routine.scopeWork,
      category: 'finans',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: day,
      hour: hour,
      minute: hour == null ? null : 0,
    );

TaskItem task(
  String id,
  String title,
  DateTime at, {
  bool done = false,
  String? assignee,
}) =>
    TaskItem(
      id: id,
      title: title,
      category: 'Ekip',
      priority: 'medium',
      status: done ? 'done' : 'todo',
      assignee: assignee,
      dueAt: at,
    );

Finder dayCell(DateTime day) =>
    find.byKey(ValueKey('kokpit-day-${AppDates.ymd(day)}'));

Finder blanks() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('kokpit-blank-');
    });

Finder dayCells() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('kokpit-day-');
    });

Finder todayButton() => find.widgetWithText(TextButton, 'Bugün');

BoxDecoration cellDecoration(WidgetTester tester, DateTime day) => tester
    .widget<AnimatedContainer>(
      find.descendant(
        of: dayCell(day),
        matching: find.byType(AnimatedContainer),
      ),
    )
    .decoration! as BoxDecoration;

void main() {
  late KokpitHarness harness;
  late bool realFonts;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  setUp(() {
    harness = KokpitHarness()..mockPlatformChannel();
  });

  group('takvim ızgarası', () {
    /// Hücre, verilen hafta günü başlığının (Pzt…Paz) tam altında mı?
    void expectUnder(WidgetTester tester, DateTime day, String weekday) {
      expect(
        tester.getCenter(dayCell(day)).dx,
        moreOrLessEquals(tester.getCenter(find.text(weekday)).dx, epsilon: 0.5),
        reason: '${AppDates.ymd(day)} → $weekday',
      );
    }

    testWidgets('Pazar başlayan, artık olmayan Şubat 2026', (tester) async {
      await harness.pump(tester, month: DateTime(2026, 2));

      expect(find.text('Şubat 2026'), findsOneWidget);
      for (final label in const ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(dayCells(), findsNWidgets(28));
      expect(dayCell(DateTime(2026, 2, 28)), findsOneWidget);
      expect(find.byKey(const ValueKey('kokpit-day-2026-02-29')), findsNothing);
      expect(blanks(), findsNWidgets(7), reason: '6 baştaki + 1 sondaki boş');

      expectUnder(tester, DateTime(2026, 2, 1), 'Paz');
      expectUnder(tester, DateTime(2026, 2, 2), 'Pzt');
      expectUnder(tester, DateTime(2026, 2, 28), 'Cmt');
      // 1'i ilk satırın sonunda, 2'si ikinci satırın başında.
      final first = tester.getTopLeft(dayCell(DateTime(2026, 2, 1)));
      final second = tester.getTopLeft(dayCell(DateTime(2026, 2, 2)));
      expect(second.dy, greaterThan(first.dy));
      expect(second.dx, lessThan(first.dx));
    });

    testWidgets('Pazartesi başlayan 28 günlük Şubat 2027: boş hücre yok',
        (tester) async {
      await harness.pump(tester, month: DateTime(2027, 2));
      expect(find.text('Şubat 2027'), findsOneWidget);
      expect(dayCells(), findsNWidgets(28));
      expect(blanks(), findsNothing);
      expectUnder(tester, DateTime(2027, 2, 1), 'Pzt');
      expectUnder(tester, DateTime(2027, 2, 28), 'Paz');
    });

    testWidgets('artık yıl Şubatı 2028: 29 gün', (tester) async {
      await harness.pump(tester, month: DateTime(2028, 2));
      expect(dayCells(), findsNWidgets(29));
      expectUnder(tester, DateTime(2028, 2, 1), 'Sal');
      expectUnder(tester, DateTime(2028, 2, 29), 'Sal');
    });

    testWidgets('altı haftaya yayılan ay (Mart 2026, Pazar başlar)',
        (tester) async {
      await harness.pump(tester, month: DateTime(2026, 3));
      expect(dayCells(), findsNWidgets(31));
      expect(blanks(), findsNWidgets(11));
      expectUnder(tester, DateTime(2026, 3, 1), 'Paz');
      expectUnder(tester, DateTime(2026, 3, 30), 'Pzt');
      expectUnder(tester, DateTime(2026, 3, 31), 'Sal');
      // Altıncı satır beşincinin altında.
      expect(
        tester.getTopLeft(dayCell(DateTime(2026, 3, 30))).dy,
        greaterThan(tester.getTopLeft(dayCell(DateTime(2026, 3, 29))).dy),
      );
    });

    testWidgets('bugün vurgulanır; aylık iş sarı, görev mavi nokta alır',
        (tester) async {
      final now = today();
      harness.routines.routines = [monthly('m1', 'Maaş ödemeleri', now.day)];
      // Görev ayın başka bir gününde: noktalar ayrı hücrelerde sınanır.
      final other = now.day == 1 ? 2 : 1;
      harness.tasks.tasks = [
        task('t1', 'Bayi toplantısı', DateTime(now.year, now.month, other, 14)),
      ];
      await harness.pump(tester, month: thisMonth());

      final decoration = cellDecoration(tester, now);
      expect((decoration.border! as Border).top.color, AppColors.accent);
      final plain = cellDecoration(tester, DateTime(now.year, now.month, other));
      expect((plain.border! as Border).top.color, Colors.transparent);

      final monthlyDot = find.byKey(ValueKey('kokpit-dot-monthly-${now.day}'));
      final taskDot = find.byKey(ValueKey('kokpit-dot-task-$other'));
      expect(monthlyDot, findsOneWidget);
      expect(taskDot, findsOneWidget);
      expect(
        (tester.widget<Container>(monthlyDot).decoration! as BoxDecoration).color,
        AppColors.warning,
      );
      expect(
        (tester.widget<Container>(taskDot).decoration! as BoxDecoration).color,
        AppColors.ops,
      );
      expect(find.byKey(ValueKey('kokpit-dot-task-${now.day}')), findsNothing);
      expect(todayButton(), findsNothing,
          reason: 'içinde bulunulan ayda kısayol gerekmez');
    });
  });

  group('gün seçimi', () {
    testWidgets('güne dokununca altında o günün listesi açılır',
        (tester) async {
      harness.routines.routines = [monthly('m1', 'Maaş ödemeleri', 15, hour: 10)];
      harness.tasks.tasks = [
        task('t1', 'Bayi toplantısı', DateTime(2026, 2, 15, 14, 30)),
        task('t2', 'Rapor teslimi', DateTime(2026, 2, 15, 9), done: true),
      ];
      await harness.pump(tester, month: DateTime(2026, 2));
      final panel = find.byKey(const ValueKey('kokpit-selected-day'));
      expect(panel, findsNothing);

      await tester.tap(dayCell(DateTime(2026, 2, 15)));
      await tester.pumpAndSettle();

      expect(panel, findsOneWidget);
      Finder inPanel(Finder finder) =>
          find.descendant(of: panel, matching: finder);
      expect(inPanel(find.text('15 Şubat Pazar')), findsOneWidget);
      expect(inPanel(find.text('Maaş ödemeleri')), findsOneWidget);
      expect(inPanel(find.text('Yapılmadı')), findsOneWidget);
      expect(inPanel(find.text('Bayi toplantısı')), findsOneWidget);
      expect(inPanel(find.text('14:30')), findsOneWidget);
      // Saat sırası: 09:00 önce.
      expect(
        tester.getTopLeft(inPanel(find.text('Rapor teslimi'))).dy,
        lessThan(tester.getTopLeft(inPanel(find.text('Bayi toplantısı'))).dy),
      );
      final selected = cellDecoration(tester, DateTime(2026, 2, 15));
      expect(selected.color, AppColors.surfaceHigh);

      // Kayıtsız gün.
      await tester.tap(dayCell(DateTime(2026, 2, 3)));
      await tester.pumpAndSettle();
      expect(inPanel(find.text('3 Şubat Salı')), findsOneWidget);
      expect(inPanel(find.text('Bu gün için kayıt yok.')), findsOneWidget);
      expect(inPanel(find.text('Maaş ödemeleri')), findsNothing);

      // Aynı güne ikinci dokunuş seçimi kaldırır.
      await tester.tap(dayCell(DateTime(2026, 2, 3)));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });

    testWidgets('ay değişince seçim temizlenir', (tester) async {
      final container = await harness.pump(tester, month: DateTime(2026, 2));
      await tester.tap(dayCell(DateTime(2026, 2, 10)));
      await tester.pumpAndSettle();
      expect(container.read(kokpitSelectedDayProvider), DateTime(2026, 2, 10));

      await tester.tap(find.byTooltip('Sonraki ay'));
      await tester.pumpAndSettle();
      expect(find.text('Mart 2026'), findsOneWidget);
      expect(container.read(kokpitSelectedDayProvider), isNull);
      expect(find.byKey(const ValueKey('kokpit-selected-day')), findsNothing);
    });
  });

  group('ay değiştirici', () {
    testWidgets('önceki / sonraki ay ve yıl sınırı', (tester) async {
      await harness.pump(tester, month: DateTime(2026, 12));
      expect(find.text('Aralık 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Sonraki ay'));
      await tester.pumpAndSettle();
      expect(find.text('Ocak 2027'), findsOneWidget);
      expect(dayCell(DateTime(2027, 1, 31)), findsOneWidget);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
      expect(find.text('Kasım 2026'), findsOneWidget);
      expect(dayCells(), findsNWidgets(30));
    });

    testWidgets('"Bugün" kısayolu başka aydayken görünür ve bugüne döner',
        (tester) async {
      final container = await harness.pump(tester, month: thisMonth());
      expect(todayButton(), findsNothing);

      await tester.tap(find.byTooltip('Önceki ay'));
      await tester.pumpAndSettle();
      expect(todayButton(), findsOneWidget);
      expect(dayCell(today()), findsNothing);

      await tester.tap(todayButton());
      await tester.pumpAndSettle();
      expect(find.text(KokpitFormat.monthTitle(thisMonth())), findsOneWidget);
      expect(todayButton(), findsNothing);
      expect(container.read(kokpitMonthProvider), thisMonth());
      expect(container.read(kokpitSelectedDayProvider), today());
      expect(find.byKey(const ValueKey('kokpit-selected-day')), findsOneWidget);
    });
  });

  group('aylık sabitler', () {
    testWidgets('geçmiş ay salt okunur: Yapıldı / Yapılmadı', (tester) async {
      harness.routines.routines = [
        monthly('m1', 'Maaş ödemeleri', 15, hour: 10),
        monthly('m2', 'Aylık push performans raporu', 1),
      ];
      harness.routines.completions = {
        RoutineCompletionKey('m2', DateTime(2026, 2)),
      };
      await harness.pump(tester, month: DateTime(2026, 2));

      expect(find.text('Aylık sabitler'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Yapıldı'), findsOneWidget);
      expect(find.text('Yapılmadı'), findsOneWidget);
      expect(find.text('15 Şubat · 10:00 · Pusholder'), findsOneWidget);
      expect(harness.isChecked(tester, 'Aylık push performans raporu'), isTrue);

      await harness.tapRow(tester, 'Maaş ödemeleri');
      await harness.tapRow(tester, 'Aylık push performans raporu');
      expect(harness.routines.toggles, isEmpty);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('31\'i olan iş Şubat\'ta ayın son gününe düşer', (tester) async {
      harness.routines.routines = [monthly('m1', 'Ay sonu kapanışı', 31)];
      await harness.pump(tester, month: DateTime(2026, 2));
      expect(find.byKey(const ValueKey('kokpit-dot-monthly-28')), findsOneWidget);
      expect(find.text('28 Şubat · Pusholder'), findsOneWidget);
    });

    testWidgets('içinde bulunulan ayın durum rozetleri', (tester) async {
      final now = today();
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      harness.routines.routines = [
        monthly('m1', 'Bugünkü iş', now.day),
        if (now.day > 1) monthly('m2', 'Geciken iş', now.day - 1),
        if (now.day < lastDay) monthly('m3', 'Bekleyen iş', now.day + 1),
      ];
      await harness.pump(tester, month: thisMonth());

      Finder chipIn(String title) => find.descendant(
            of: find
                .ancestor(of: find.text(title), matching: find.byType(InkWell))
                .first,
            matching: find.byType(KokpitStatusChip),
          );
      expect(tester.widget<KokpitStatusChip>(chipIn('Bugünkü iş')).status,
          OccurrenceStatus.dueToday);
      expect(
        find.descendant(of: chipIn('Bugünkü iş'), matching: find.text('Bugün')),
        findsOneWidget,
      );
      if (now.day > 1) {
        expect(
          find.descendant(of: chipIn('Geciken iş'), matching: find.text('Gecikti')),
          findsOneWidget,
        );
      }
      if (now.day < lastDay) {
        expect(
          find.descendant(
            of: chipIn('Bekleyen iş'),
            matching: find.text('Bekliyor'),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('Ay görünümünden işaretleme: iyimser, sonra Gün görünümünde de '
        'işaretli', (tester) async {
      harness.routines.routines = [monthly('m1', 'Maaş ödemeleri', today().day)];
      harness.routines.toggleGate = Completer<void>();
      await harness.pump(tester, month: thisMonth());
      expect(find.text('0 / 1'), findsOneWidget);

      await tester.ensureVisible(find.text('Maaş ödemeleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maaş ödemeleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.routines.toggles, [
        (routineId: 'm1', periodKey: thisMonth(), completed: true),
      ]);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue,
          reason: 'sunucu onayı beklenmeden');
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Yapıldı'), findsOneWidget);

      // Yazma sürerken ikinci dokunuş yok sayılır.
      await tester.tap(find.text('Maaş ödemeleri'));
      await tester.pump();
      expect(harness.routines.toggles, hasLength(1));

      harness.routines.toggleGate!.complete();
      await tester.pumpAndSettle();
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);
      expect(find.byType(SnackBar), findsNothing);

      await harness.showView(tester, 'Gün');
      expect(find.text('Yaklaşan aylık işler'), findsOneWidget);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);

      // Gün görünümünden geri al → Ay görünümü de güncellenir.
      harness.routines.toggleGate = null;
      await harness.tapRow(tester, 'Maaş ödemeleri');
      await harness.showView(tester, 'Ay');
      expect(find.text('0 / 1'), findsOneWidget);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
    });

    testWidgets('sunucu hatasında geri alınır ve kullanıcı uyarılır',
        (tester) async {
      harness.routines.routines = [monthly('m1', 'Maaş ödemeleri', today().day)];
      harness.routines.toggleGate = Completer<void>();
      await harness.pump(tester, month: thisMonth());

      await tester.ensureVisible(find.text('Maaş ödemeleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maaş ödemeleri'));
      await tester.pump();
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);

      harness.routines.toggleGate!.completeError(Exception('ağ yok'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
      expect(find.text('0 / 1'), findsOneWidget);
      expect(find.text('Aylık iş güncellenemedi. Tekrar dene.'), findsOneWidget);
    });

    testWidgets('aylık sabit yoksa boş durum', (tester) async {
      await harness.pump(tester, month: DateTime(2026, 2));
      expect(find.text('Bu ay için aylık sabit yok.'), findsOneWidget);
      expect(find.text('Bu ay için randevu ya da görev yok.',
          skipOffstage: false), findsOneWidget);
    });
  });

  group('bu ayın randevuları', () {
    testWidgets('liste, tamamlananlar üstü çizili; geçmiş ayda tamamla yok',
        (tester) async {
      harness.tasks.tasks = [
        task('t1', 'Bayi toplantısı', DateTime(2026, 2, 18, 14, 30),
            assignee: 'Duhan'),
        task('t2', 'Rapor teslimi', DateTime(2026, 2, 5, 9), done: true),
        task('t3', 'Mart işi', DateTime(2026, 3, 1, 9)),
      ];
      await harness.pump(tester, month: DateTime(2026, 2));
      await harness.scrollThrough(tester);

      expect(find.text('Bu ayın randevuları'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Bayi toplantısı'), findsOneWidget);
      expect(find.text('14:30 · Ekip · Duhan'), findsOneWidget);
      expect(find.text('Mart işi'), findsNothing);
      expect(
        tester.widget<Text>(find.text('Rapor teslimi')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.byTooltip('Tamamlandı olarak işaretle'), findsNothing);
    });

    testWidgets('içinde bulunulan ayda görev tamamlanır', (tester) async {
      final now = today();
      harness.tasks.tasks = [
        task('t1', 'Bayi toplantısı',
            DateTime(now.year, now.month, now.day, 23, 59)),
      ];
      await harness.pump(tester, month: thisMonth());
      expect(find.text('0 / 1', skipOffstage: false), findsOneWidget);

      final button = find.byTooltip('Tamamlandı olarak işaretle');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(harness.tasks.completedIds, ['t1']);
      expect(find.text('Tamamlandı: Bayi toplantısı'), findsOneWidget);
      expect(find.text('1 / 1', skipOffstage: false), findsWidgets);
      expect(find.byTooltip('Tamamlandı olarak işaretle'), findsNothing);
    });
  });

  group('ay özeti', () {
    testWidgets('sağlık verisiyle', (tester) async {
      harness.routines.routines = [
        Routine.fromMap(const {'id': 'r1', 'title': 'Günlük kontrol'}),
      ];
      harness.routines.completions = {
        for (var d = 1; d <= 14; d++)
          RoutineCompletionKey('r1', DateTime(2026, 2, d)),
      };
      harness.tasks.tasks = [
        task('t1', 'Bayi toplantısı', DateTime(2026, 2, 18, 14)),
        task('t2', 'Rapor teslimi', DateTime(2026, 2, 5, 9), done: true),
      ];
      harness.healthStore
        ..metrics = [
          DailyHealthMetric(
            day: DateTime(2026, 2, 3),
            steps: 8000,
            sleepMinutes: 420,
          ),
          DailyHealthMetric(
            day: DateTime(2026, 2, 4),
            steps: 10000,
            sleepMinutes: 480,
          ),
        ]
        ..nutrition = [
          DailyNutritionTotal(
            day: DateTime(2026, 2, 3),
            calories: 1800,
            proteinG: 150,
            entryCount: 3,
          ),
          DailyNutritionTotal(
            day: DateTime(2026, 2, 4),
            calories: 2000,
            proteinG: 170,
            entryCount: 4,
          ),
        ]
        ..weights = [
          WeightEntry(
            id: 'w1',
            weightKg: 84.5,
            loggedAt: DateTime(2026, 2, 1, 8),
          ),
          WeightEntry(
            id: 'w2',
            weightKg: 83.3,
            loggedAt: DateTime(2026, 2, 27, 8),
          ),
        ];
      await harness.pump(tester, month: DateTime(2026, 2));
      await harness.scrollThrough(tester);

      expect(find.text('Ay özeti'), findsOneWidget);
      expect(find.text('Rutinler'), findsOneWidget);
      // Rutinler 14/28, görevler 1/2: ikisi de %50.
      expect(find.text('%50'), findsNWidgets(2));
      expect(find.text('14 / 28 tamamlandı'), findsOneWidget);
      expect(find.text('Görevler'), findsOneWidget);
      expect(find.text('1 / 2 tamamlandı'), findsOneWidget);
      expect(find.text('Ort. adım'), findsOneWidget);
      expect(find.text('9.000'), findsOneWidget);
      expect(find.text('Hedef 10.000'), findsOneWidget);
      expect(find.text('Ort. uyku'), findsOneWidget);
      expect(find.text('7 sa 30 dk'), findsOneWidget);
      expect(find.text('Hedef 7 sa 30 dk'), findsOneWidget);
      expect(find.text('Ort. kalori'), findsOneWidget);
      expect(find.text('1.900 kcal'), findsOneWidget);
      expect(find.text('Hedef 2.000 kcal'), findsOneWidget);
      expect(find.text('Kilo değişimi'), findsOneWidget);
      expect(find.text('−1,2 kg'), findsOneWidget);
      expect(find.text('84,5 → 83,3 kg'), findsOneWidget);
      expect(find.text('Bu ay için sağlık ve beslenme verisi yok.'), findsNothing);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('sağlık verisi olmadan: tire ve açıklama', (tester) async {
      await harness.pump(tester, month: DateTime(2026, 2));
      await harness.scrollThrough(tester);

      expect(find.text('Ay özeti'), findsOneWidget);
      // Rutin, görev, adım, uyku, kalori, kilo: altısı da veri yok.
      expect(find.text('—'), findsNWidgets(6));
      expect(find.text('Planlanan rutin yok'), findsOneWidget);
      expect(find.text('Görev yok'), findsOneWidget);
      expect(find.text('Ölçüm yok'), findsOneWidget);
      expect(find.text('Hedef 10.000'), findsOneWidget);
      expect(
        find.text('Bu ay için sağlık ve beslenme verisi yok.'),
        findsOneWidget,
      );
    });
  });

  group('yükleme hatası', () {
    testWidgets('ay verisi yüklenemezse takvim durur, Tekrar dene çalışır',
        (tester) async {
      harness.tasks.fetchError = Exception('ağ yok');
      await harness.pump(tester, month: DateTime(2026, 2));

      expect(dayCells(), findsNWidgets(28));
      expect(find.text('Ay verisi yüklenemedi.'), findsOneWidget);

      harness.tasks.fetchError = null;
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(find.text('Ay verisi yüklenemedi.'), findsNothing);
      expect(find.text('Aylık sabitler'), findsOneWidget);
    });
  });

  // Gerçek yazı tipi (Roboto) ile ölçülür; 375x667 = iPhone SE.
  group('Ay görünümü taşma yok', () {
    void fillBusyMonth(DateTime month) {
      harness.routines.routines = [
        Routine.fromMap(const {'id': 'r1', 'title': 'Günlük kontrol'}),
        monthly(
          'm1',
          'Aylık push performans raporunun hazırlanması ve ekiple paylaşımı',
          15,
          hour: 10,
        ),
        monthly('m2', 'Maaş ödemeleri', 15, hour: 10),
        monthly('m3', 'Ay sonu kapanışı', 31),
      ];
      harness.routines.completions = {
        RoutineCompletionKey('m2', month),
        for (var d = 1; d <= 28; d++)
          RoutineCompletionKey('r1', DateTime(month.year, month.month, d)),
      };
      harness.tasks.tasks = [
        task(
          't1',
          'Push bildirim performans raporunu hazırla ve ekip ile paylaş, '
              'ardından haftalık toplantıda sun',
          DateTime(month.year, month.month, 15, 14, 30),
          assignee: 'Mehmet',
        ),
        task('t2', 'Rapor teslimi', DateTime(month.year, month.month, 15, 9),
            done: true),
        task('t3', 'Bayi toplantısı', DateTime(month.year, month.month, 28, 23)),
      ];
      harness.healthStore
        ..metrics = [
          DailyHealthMetric(
            day: DateTime(month.year, month.month, 3),
            steps: 12345,
            sleepMinutes: 478,
          ),
        ]
        ..nutrition = [
          DailyNutritionTotal(
            day: DateTime(month.year, month.month, 3),
            calories: 2350,
            proteinG: 185,
            entryCount: 4,
          ),
        ]
        ..weights = [
          WeightEntry(
            id: 'w1',
            weightKg: 104.5,
            loggedAt: DateTime(month.year, month.month, 1, 8),
          ),
          WeightEntry(
            id: 'w2',
            weightKg: 93.3,
            loggedAt: DateTime(month.year, month.month, 27, 8),
          ),
        ];
    }

    final months = <String, DateTime Function()>{
      'Şubat 2026 (geçmiş, 5 hafta)': () => DateTime(2026, 2),
      'Mart 2026 (6 hafta)': () => DateTime(2026, 3),
      'içinde bulunulan ay': thisMonth,
      'gelecek ay': () => DateTime(today().year, today().month + 1),
    };

    for (final scale in const [1.0, 1.3]) {
      for (final entry in months.entries) {
        testWidgets('375x667, metin ölçeği $scale, ${entry.key}',
            (tester) async {
          if (!realFonts) {
            markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
            return;
          }
          final month = entry.value();
          fillBusyMonth(month);
          await harness.pump(tester, month: month, textScale: scale);
          expect(tester.takeException(), isNull);

          // Seçili gün paneli açıkken (uzun başlıklar + rozetler).
          await tester.tap(dayCell(DateTime(month.year, month.month, 15)));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('kokpit-selected-day')),
              findsOneWidget);
          expect(await harness.scrollThrough(tester), isEmpty);
        });
      }

      testWidgets('375x667, metin ölçeği $scale, boş ay', (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        await harness.pump(tester, month: DateTime(2026, 2), textScale: scale);
        expect(await harness.scrollThrough(tester), isEmpty);
      });
    }
  });
}
