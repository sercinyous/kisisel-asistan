import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_motion.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_day_view.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_widgets.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_providers.dart';
import 'package:kisisel_asistan/features/operations/presentation/routine_form_sheet.dart';
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

TaskItem dueToday(String id) => TaskItem(
      id: id,
      title: 'Görev $id',
      category: 'Ekip',
      priority: 'medium',
      status: 'todo',
      dueAt: today().add(const Duration(hours: 23)),
    );

/// Yazma başarılı döner ama okunan durum değişmez (gecikmeli eşitleme).
class _StaleRoutines extends FakeRoutinesRepository {
  _StaleRoutines({super.routines});

  @override
  Future<void> setCompleted({
    required String routineId,
    required DateTime periodKey,
    required bool completed,
  }) async {
    toggles.add(
      (routineId: routineId, periodKey: periodKey, completed: completed),
    );
  }
}

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

  group('Bugünün işleri', () {
    testWidgets('aylık işler listelenmez ve sayaca girmez', (tester) async {
      await harness.pump(tester);

      expect(find.text('0 / 2'), findsOneWidget,
          reason: 'aylık iş günlük sayaca girmez');
      await harness.scrollThrough(tester);
      expect(find.text('Bugünün işleri'), findsOneWidget);
      expect(find.text('Sabah görev kontrolü'), findsOneWidget);
      expect(find.text('Gelen kutusu kontrolü'), findsOneWidget);
      expect(find.text('Maaş ödemeleri'), findsNothing);
      expect(find.text('Yaklaşan aylık işler'), findsNothing);
      expect(find.textContaining('Tümünü gör'), findsNothing,
          reason: 'tüm satırlar görünüyorsa kısayol yok');
    });

    testWidgets('gecikmiş görevler (dünkü dahil) önce, yarınki yok',
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
      expect(find.text('0 / 4'), findsOneWidget);
      await harness.scrollThrough(tester);
      expect(find.text('Sabah toplantısı'), findsOneWidget);
      expect(find.text('Dünkü iş'), findsOneWidget,
          reason: 'önceki günden kalan açık görev kaybolmaz');
      expect(find.text('Yarınki iş'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Dünkü iş')).dy,
        lessThan(tester.getTopLeft(find.text('Sabah toplantısı')).dy),
      );
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

    test('hatırlatması bugün, son tarihi ileride görev listelenir', () {
      final now = DateTime(2026, 11, 26, 8);
      final remind = DateTime(2026, 11, 26, 10);
      final items = kokpitTodayItems(
        routines: const [],
        tasks: [
          TaskItem(
            id: 'r1',
            title: 'Rapor',
            category: 'Ekip',
            priority: 'medium',
            status: 'todo',
            dueAt: DateTime(2026, 12, 4, 17),
            remindAt: remind,
          ),
        ],
        now: now,
      );
      expect(items, hasLength(1));
      expect(items.single.time, remind);
    });

    testWidgets('bugün 8 görev: sayılar kesilmez, 5 satır görünür',
        (tester) async {
      harness.routines.routines = [];
      harness.tasks.tasks = [for (var i = 0; i < 8; i++) dueToday('g$i')];
      await harness.pump(tester);
      expect(find.text('0 / 8'), findsOneWidget);
      await harness.scrollThrough(tester);
      expect(find.text('Tümünü gör (8)'), findsOneWidget);
    });

    testWidgets('bugün tamamlanan görev ilerlemeye sayılır', (tester) async {
      harness.routines.routines = [];
      harness.tasks.tasks = [
        dueToday('a'),
        dueToday('b').copyWith(
          status: 'done',
          completedAt: DateTime.now(),
        ),
        dueToday('c').copyWith(
          status: 'done',
          completedAt: today().subtract(const Duration(hours: 2)),
        ),
      ];
      await harness.pump(tester);
      expect(find.text('1 / 2'), findsOneWidget,
          reason: 'dün tamamlanan sayılmaz');
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

    testWidgets('Tümünü gör: gizlilerin çoğu görevse Görevler, filtreler sıfır',
        (tester) async {
      harness.routines.routines = [
        for (var i = 0; i < 4; i++) daily('r$i', 'Rutin $i', time: '00:0$i:00'),
      ];
      harness.tasks.tasks = [for (var i = 0; i < 4; i++) dueToday('t$i')];
      final container = await harness.pump(tester);
      container.read(routineScopeFilterProvider.notifier).state = 'is';
      container.read(taskCategoryFilterProvider.notifier).state = 'Ekip';
      container.read(opsSegmentProvider.notifier).state = OpsSegment.notes;
      await tester
          .ensureVisible(find.byKey(const ValueKey('kokpit-today-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('kokpit-today-all')));
      await tester.pumpAndSettle();
      expect(container.read(opsSegmentProvider), OpsSegment.tasks);
      expect(container.read(routineScopeFilterProvider), isNull);
      expect(container.read(taskCategoryFilterProvider), isNull);
    });

    testWidgets('Tümünü gör: gizliler rutinse Rutinler açılır', (tester) async {
      harness.routines.routines = [
        for (var i = 0; i < 7; i++) daily('r$i', 'Rutin $i'),
      ];
      final container = await harness.pump(tester);
      container.read(routineScopeFilterProvider.notifier).state = 'is';
      await tester
          .ensureVisible(find.byKey(const ValueKey('kokpit-today-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('kokpit-today-all')));
      await tester.pumpAndSettle();
      expect(container.read(opsSegmentProvider), OpsSegment.routines);
      expect(container.read(routineScopeFilterProvider), isNull);
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

    testWidgets('rutin işaretlenince kutu kutlama darbesi oynatır',
        (tester) async {
      await harness.pump(tester);
      await harness.tapRow(tester, 'Gelen kutusu kontrolü');
      final row = find.ancestor(
        of: find.text('Gelen kutusu kontrolü'),
        matching: find.byType(InkWell),
      );
      final state = tester.state<KokpitCelebrateState>(
        find.descendant(of: row.first, matching: find.byType(KokpitCelebrate)),
      );
      expect(state.celebrations, 1);
      expect(state.playing, isFalse);
    });
  });

  group('İşler › Rutinler tamamlama kutusu', () {
    Finder check(String id) => find.byKey(ValueKey('ops-routine-check-$id'));

    Future<void> tapCheck(WidgetTester tester, String id) async {
      await tester.ensureVisible(check(id));
      await tester.pumpAndSettle();
      await tester.tap(check(id));
      await tester.pumpAndSettle();
    }

    bool checked(WidgetTester tester, String id) => tester
        .widget<KokpitCheckBox>(
          find.descendant(of: check(id), matching: find.byType(KokpitCheckBox)),
        )
        .checked;

    testWidgets('Bugün grubundaki rutin kutudan tamamlanır', (tester) async {
      await harness.pump(tester);
      await harness.showView(tester, 'Rutinler');
      expect(check('r1'), findsOneWidget);
      expect(checked(tester, 'r1'), isFalse);

      await tapCheck(tester, 'r1');
      expect(checked(tester, 'r1'), isTrue);
      final toggle = harness.routines.toggles.single;
      expect(toggle.routineId, 'r1');
      expect(toggle.periodKey, today());
      expect(toggle.completed, isTrue);
    });

    testWidgets('Aylık iş kutudan tamamlanır ve geri alınır', (tester) async {
      await harness.pump(tester);
      await harness.showView(tester, 'Rutinler');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ops-group-routines-monthly')),
          matching: check('m1'),
        ),
        findsOneWidget,
      );

      await tapCheck(tester, 'm1');
      expect(checked(tester, 'm1'), isTrue);
      expect(harness.routines.toggles.single.periodKey, thisMonth());

      await tapCheck(tester, 'm1');
      expect(checked(tester, 'm1'), isFalse);
      expect(harness.routines.toggles.last.completed, isFalse);
    });

    testWidgets(
        'aylık iş yazımı başarılı ama durum değişmese de kutu kilitlenmez',
        (tester) async {
      harness.routines = _StaleRoutines(routines: harness.routines.routines);
      await harness.pump(tester);
      await harness.showView(tester, 'Rutinler');
      await tapCheck(tester, 'm1');
      expect(harness.routines.toggles, hasLength(1));
      expect(checked(tester, 'm1'), isFalse);
      await tapCheck(tester, 'm1');
      expect(harness.routines.toggles, hasLength(2),
          reason: 'bekleyen durum temizlenmeli, ikinci dokunuş işlenmeli');
    });

    testWidgets('satıra dokunmak formu açar, kutu tamamlamaz', (tester) async {
      await harness.pump(tester);
      await harness.showView(tester, 'Rutinler');
      await tester.tap(find.text('Gelen kutusu kontrolü'));
      await tester.pumpAndSettle();
      expect(harness.routines.toggles, isEmpty);
      expect(find.byType(RoutineFormSheet), findsOneWidget);
    });

    testWidgets('pasif rutin Bugün yerine Pasif grubunda, kutusuz',
        (tester) async {
      harness.routines.routines = [
        ...harness.routines.routines,
        daily('r3', 'Eski rutin').copyWith(isActive: false),
      ];
      await harness.pump(tester);
      await harness.showView(tester, 'Rutinler');
      final passive = find.byKey(const ValueKey('ops-group-routines-passive'));
      await tester.ensureVisible(passive);
      expect(
        find.descendant(of: passive, matching: find.text('Eski rutin')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ops-group-routines-today')),
          matching: find.text('Eski rutin'),
        ),
        findsNothing,
      );
      expect(check('r3'), findsNothing);
    });
  });

  group('başlık', () {
    testWidgets('tek profil ikonu; ayrı Ayarlar ve görünüm seçici yok',
        (tester) async {
      await harness.pump(tester);
      expect(find.byTooltip('Hesap ve ayarlar'), findsOneWidget);
      expect(find.byTooltip('Ayarlar'), findsNothing);
      expect(find.byTooltip('Arkadaşlar'), findsNothing);
      expect(find.text('Gün'), findsNothing);
    });

    testWidgets('profil ikonu Hesap ekranını açar', (tester) async {
      await harness.pump(tester);
      await tester.tap(find.byTooltip('Hesap ve ayarlar'));
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
