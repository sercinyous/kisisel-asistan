import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_format.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_day_view.dart';
import 'package:kisisel_asistan/features/settings/presentation/hesap_screen.dart';

import '../helpers/kokpit_fakes.dart';
import '../helpers/test_fonts.dart';

DateTime today() => AppDates.startOfDay(DateTime.now());
DateTime thisMonth() => DateTime(today().year, today().month);
int daysInThisMonth() => DateTime(today().year, today().month + 1, 0).day;

Routine daily(String id, String title, {String? time}) => Routine.fromMap({
      'id': id,
      'title': title,
      'category': 'operasyon',
      'time_of_day': time,
    });

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

void main() {
  late KokpitHarness harness;
  late bool realFonts;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  setUp(() {
    harness = KokpitHarness()..mockPlatformChannel();
    harness.routines.routines = [
      daily('r1', 'Sabah görev kontrolü', time: '09:00:00'),
      daily('r2', 'Gelen kutusu kontrolü'),
      monthly('m1', 'Maaş ödemeleri', today().day, hour: 10),
    ];
  });

  group('Bugünün rutinleri', () {
    testWidgets('aylık işler listelenmez ve sayaca girmez', (tester) async {
      await harness.pump(tester);

      expect(find.text('0 / 2'), findsOneWidget,
          reason: 'aylık iş günlük sayaca girmez');
      await harness.scrollThrough(tester);
      expect(find.text('Bugünün rutinleri'), findsOneWidget);
      expect(find.text('Sabah görev kontrolü'), findsOneWidget);
      expect(find.text('Gelen kutusu kontrolü'), findsOneWidget);
      expect(find.text('Maaş ödemeleri'), findsNothing);
      expect(find.text('Yaklaşan aylık işler'), findsNothing);
      expect(find.text('Tümünü gör (2)'), findsOneWidget);
    });

    testWidgets('bugünün gecikmiş görevi önce, yarınki ve dünkü yok',
        (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't0',
          title: 'Sabah toplantısı',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today(),
        ),
        TaskItem(
          id: 't1',
          title: 'Dünkü iş',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today().subtract(const Duration(hours: 5)),
        ),
        TaskItem(
          id: 't2',
          title: 'Yarınki iş',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today().add(const Duration(days: 1, hours: 9)),
        ),
      ];
      await harness.pump(tester);
      expect(find.text('0 / 3'), findsOneWidget);
      await harness.scrollThrough(tester);
      expect(find.text('Sabah toplantısı'), findsOneWidget);
      expect(find.text('Dünkü iş'), findsNothing);
      expect(find.text('Yarınki iş'), findsNothing);
      final first = tester.getTopLeft(find.text('Sabah toplantısı')).dy;
      final routine = tester.getTopLeft(find.text('Gelen kutusu kontrolü')).dy;
      expect(first, lessThan(routine), reason: 'gecikmiş kayıt en üstte');
    });

    test('sıralama: gecikmiş açıklar önce, sonra saat, saatsizler sonda', () {
      final now = DateTime(2026, 11, 18, 12);
      RoutineOccurrence occ(Routine r, {bool done = false}) =>
          RoutineOccurrence(
            routine: r,
            periodKey: AppDates.startOfDay(now),
            dueDate: AppDates.startOfDay(now),
            completed: done,
            status: done ? OccurrenceStatus.done : OccurrenceStatus.dueToday,
          );
      final items = kokpitTodayItems(
        routines: [
          occ(daily('a', 'Saatsiz')),
          occ(daily('b', 'Akşam', time: '19:00:00')),
          occ(daily('c', 'Sabah yapıldı', time: '08:00:00'), done: true),
          occ(daily('d', 'Sabah açık', time: '09:00:00')),
        ],
        tasks: const [],
        now: now,
      );
      expect(
        [
          for (final i in items)
            (i as KokpitRoutineItem).occurrence.routine.title,
        ],
        ['Sabah açık', 'Sabah yapıldı', 'Akşam', 'Saatsiz'],
      );
    });

    testWidgets('en fazla 5 satır; Tümünü gör toplamı gösterir',
        (tester) async {
      harness.routines.routines = [
        for (var i = 0; i < 7; i++) daily('r$i', 'Rutin $i'),
      ];
      await harness.pump(tester);
      await harness.scrollThrough(tester);
      expect(find.textContaining('Rutin '), findsNWidgets(5));
      expect(find.text('Tümünü gör (7)'), findsOneWidget);
    });

    testWidgets('rutin işaretlenince sayaç güncellenir', (tester) async {
      await harness.pump(tester);
      await harness.tapRow(tester, 'Gelen kutusu kontrolü');
      expect(harness.isChecked(tester, 'Gelen kutusu kontrolü'), isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('1 iş kaldı'), findsOneWidget);
    });
  });

  group('Ay görünümü (Kokpit dışında yeniden kullanılır)', () {
    testWidgets('aylık iş Ay görünümünden işaretlenir', (tester) async {
      await harness.pump(tester);
      await harness.showView(tester, 'Ay');
      expect(find.text('Aylık sabitler'), findsOneWidget);
      expect(find.text(KokpitFormat.monthTitle(thisMonth())), findsOneWidget);
      await harness.tapRow(tester, 'Maaş ödemeleri');
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);
      expect(harness.routines.toggles.single.periodKey, thisMonth());
    });
  });

  group('başlık', () {
    testWidgets('tek profil ikonu; ayrı Ayarlar ve görünüm seçici yok',
        (tester) async {
      await harness.pump(tester);
      expect(find.byTooltip('Hesap'), findsOneWidget);
      expect(find.byTooltip('Ayarlar'), findsNothing);
      expect(find.byTooltip('Arkadaşlar'), findsNothing);
      expect(find.text('Gün'), findsNothing);
    });

    testWidgets('profil ikonu Hesap ekranını açar', (tester) async {
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Hesap'));
      await tester.pumpAndSettle();
      expect(find.byType(HesapScreen), findsOneWidget);
    });
  });

  // Gerçek yazı tipi (Roboto) ile ölçülür; 375x667 = iPhone SE.
  group('Kokpit taşma yok', () {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('375x667, metin ölçeği $scale', (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        harness.routines.routines = [
          ...harness.routines.routines,
          daily(
            'r9',
            'Aylık faaliyet performans raporunun hazırlanması ve ekiple paylaşımı',
            time: '10:00:00',
          ),
        ];
        harness.tasks.tasks = [
          TaskItem(
            id: 't1',
            title: 'Push bildirim performans raporunu hazırla ve ekip ile '
                'paylaş, ardından haftalık toplantıda sun',
            category: 'İş',
            priority: 'high',
            status: 'todo',
            assignee: 'Elif',
            dueAt: today().add(const Duration(hours: 23, minutes: 59)),
          ),
        ];
        await harness.pump(tester, textScale: scale);
        expect(await harness.scrollThrough(tester), isEmpty);
      });
    }
  });
}
