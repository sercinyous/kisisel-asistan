import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/demo/demo_reminders.dart';
import 'package:kisisel_asistan/features/reminders/data/reminders_repository.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/core/widgets/item_actions.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/meal_form_sheet.dart';
import 'package:kisisel_asistan/features/health/presentation/meals_section.dart';
import 'package:kisisel_asistan/features/health/presentation/workout_form_sheet.dart';
import 'package:kisisel_asistan/features/health/presentation/workouts_section.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_providers.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_screen.dart';
import 'package:kisisel_asistan/features/operations/presentation/routine_form_sheet.dart';
import 'package:kisisel_asistan/features/operations/presentation/task_form_sheet.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

import '../helpers/fakes.dart';
import '../helpers/kokpit_fakes.dart';
import '../helpers/test_fonts.dart';

DateTime today() => AppDates.startOfDay(DateTime.now());

/// Snackbar zamanlayıcısı test bitmeden kapansın.
Future<void> drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> pumpPlain(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(750, 1334);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child)),
  );
  await tester.pumpAndSettle();
}

Future<void> confirmInDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Sil'));
  await tester.pumpAndSettle();
}

Future<void> cancelInDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Vazgeç'));
  await tester.pumpAndSettle();
}

Future<void> longPressRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> swipeRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.drag(find.text(title), const Offset(-500, 0));
  await tester.pumpAndSettle();
}

void main() {
  late bool realFonts;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  group('ItemActions', () {
    testWidgets('uzun basış alt sayfada Düzenle ve Sil gösterir',
        (tester) async {
      await pumpPlain(
        tester,
        ItemActions(
          title: 'Haftalık rapor',
          onEdit: () {},
          onDelete: () {},
          child: const ListTile(title: Text('Haftalık rapor')),
        ),
      );
      expect(find.text('Düzenle'), findsNothing);

      await tester.longPress(find.text('Haftalık rapor'));
      await tester.pumpAndSettle();

      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      // Başlık hem satırda hem alt sayfada.
      expect(find.text('Haftalık rapor'), findsNWidgets(2));
    });

    testWidgets('Sil → onay → onDelete bir kez çağrılır', (tester) async {
      var deleted = 0;
      await pumpPlain(
        tester,
        ItemActions(
          title: 'Haftalık rapor',
          onEdit: () {},
          onDelete: () => deleted++,
          child: const ListTile(title: Text('Haftalık rapor')),
        ),
      );

      await tester.longPress(find.text('Haftalık rapor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.text('Silinsin mi?'), findsOneWidget);
      expect(find.text('"Haftalık rapor" kalıcı olarak silinecek.'),
          findsOneWidget);
      expect(deleted, 0, reason: 'onaydan önce silinmez');

      await confirmInDialog(tester);
      expect(deleted, 1);
      expect(find.text('Silinsin mi?'), findsNothing);
    });

    testWidgets('Vazgeç onDelete çağırmaz', (tester) async {
      var deleted = 0;
      await pumpPlain(
        tester,
        ItemActions(
          title: 'Haftalık rapor',
          confirmTitle: 'Görev silinsin mi?',
          confirmMessage: 'Özel mesaj.',
          onEdit: () {},
          onDelete: () => deleted++,
          child: const ListTile(title: Text('Haftalık rapor')),
        ),
      );

      await tester.longPress(find.text('Haftalık rapor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      expect(find.text('Özel mesaj.'), findsOneWidget);

      await cancelInDialog(tester);
      expect(deleted, 0);
      expect(find.text('Haftalık rapor'), findsOneWidget);
    });

    testWidgets('Düzenle onEdit çağırır, onay sormaz', (tester) async {
      var edited = 0;
      var deleted = 0;
      await pumpPlain(
        tester,
        ItemActions(
          title: 'Haftalık rapor',
          onEdit: () => edited++,
          onDelete: () => deleted++,
          child: const ListTile(title: Text('Haftalık rapor')),
        ),
      );

      await tester.longPress(find.text('Haftalık rapor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();

      expect(edited, 1);
      expect(deleted, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('kısa dokunuş çocuğun kendi eylemini çalıştırır',
        (tester) async {
      var taps = 0;
      await pumpPlain(
        tester,
        ItemActions(
          title: 'Satır',
          onEdit: () {},
          onDelete: () {},
          child: ListTile(title: const Text('Satır'), onTap: () => taps++),
        ),
      );

      await tester.tap(find.text('Satır'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.text('Düzenle'), findsNothing);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('uzun başlık 375x667, metin ölçeği $scale taşmaz',
          (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        const title = 'Push bildirim performans raporunu hazırla ve ekip ile '
            'paylaş, ardından haftalık toplantıda sun ve kararları not al';
        await pumpPlain(
          tester,
          ItemActions(
            title: title,
            onEdit: () {},
            onDelete: () {},
            child: const ListTile(title: Text(title)),
          ),
          textScale: scale,
        );
        await tester.longPress(find.text(title));
        await tester.pumpAndSettle();
        expect(find.text('Sil'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Sil'));
        await tester.pumpAndSettle();
        expect(find.text('Silinsin mi?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SwipeToDelete', () {
    Widget row(
      String title, {
      required void Function() onDelete,
      Object itemKey = 'swipe-1',
    }) =>
        SwipeToDelete(
          itemKey: ValueKey(itemKey),
          confirmTitle: 'Görev silinsin mi?',
          confirmMessage: '"$title" kalıcı olarak silinecek.',
          onDelete: onDelete,
          child: ListTile(title: Text(title)),
        );

    testWidgets('sola kaydırma onay sorar; onayda onDelete bir kez çağrılır '
        've satır kalkar', (tester) async {
      var deleted = 0;
      await pumpPlain(tester, row('Satır', onDelete: () => deleted++));

      await tester.drag(find.text('Satır'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      expect(find.text('"Satır" kalıcı olarak silinecek.'), findsOneWidget);
      expect(deleted, 0);

      await confirmInDialog(tester);
      expect(deleted, 1);
      expect(find.text('Satır'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Vazgeç: onDelete çağrılmaz, satır yerine geri gelir',
        (tester) async {
      var deleted = 0;
      await pumpPlain(tester, row('Satır', onDelete: () => deleted++));
      final home = tester.getTopLeft(find.text('Satır'));

      await tester.drag(find.text('Satır'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await cancelInDialog(tester);

      expect(deleted, 0);
      expect(find.text('Satır'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Satır')), home);
    });

    testWidgets('sağa kaydırma bir şey yapmaz', (tester) async {
      var deleted = 0;
      await pumpPlain(tester, row('Satır', onDelete: () => deleted++));

      await tester.drag(find.text('Satır'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(deleted, 0);
      expect(find.text('Satır'), findsOneWidget);
    });

    testWidgets('silme hata verirse satır geri gelir', (tester) async {
      await pumpPlain(
        tester,
        SwipeToDelete(
          itemKey: const ValueKey('swipe-1'),
          confirmTitle: 'Silinsin mi?',
          confirmMessage: 'Silinecek.',
          onDelete: () => throw const ItemDeleteFailed(),
          child: const ListTile(title: Text('Satır')),
        ),
      );
      final home = tester.getTopLeft(find.text('Satır'));

      await tester.drag(find.text('Satır'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);

      expect(find.text('Satır'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Satır')), home);
      expect(tester.takeException(), isNull);
    });

    testWidgets('silinen satırın gizli durumu bir sonraki satıra geçmez',
        (tester) async {
      late StateSetter rebuild;
      var items = ['A', 'B', 'C'];
      await pumpPlain(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: [
                for (final id in items)
                  // Anahtarsız sarmalayıcı: durum konumla eşleşir.
                  ItemRowActions(
                    itemKey: ValueKey('swipe-$id'),
                    title: 'Kayıt $id',
                    confirmTitle: 'Silinsin mi?',
                    confirmMessage: 'Kayıt $id silinecek.',
                    onEdit: () {},
                    onDelete: () async {
                      rebuild(() => items = [...items]..remove(id));
                      return true;
                    },
                    child: ListTile(title: Text('Kayıt $id')),
                  ),
              ],
            );
          },
        ),
      );

      await tester.drag(find.text('Kayıt A'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);

      expect(find.text('Kayıt A'), findsNothing);
      expect(find.text('Kayıt B'), findsOneWidget);
      expect(find.text('Kayıt C'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'onay açıkken liste kayarsa onaylanan kayıt silinir, komşusu değil',
        (tester) async {
      late StateSetter rebuild;
      var items = ['A', 'B', 'C'];
      final deleted = <String>[];
      await pumpPlain(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: [
                for (final id in items)
                  // Anahtarsız sarmalayıcı: durum kayıtla değil konumla eşleşir.
                  ItemRowActions(
                    itemKey: ValueKey('swipe-$id'),
                    title: 'Kayıt $id',
                    confirmTitle: 'Silinsin mi?',
                    confirmMessage: '"Kayıt $id" silinecek.',
                    onEdit: () {},
                    onDelete: () async {
                      deleted.add(id);
                      return true;
                    },
                    child: ListTile(title: Text('Kayıt $id')),
                  ),
              ],
            );
          },
        ),
      );

      await tester.drag(find.text('Kayıt B'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('"Kayıt B" silinecek.'), findsOneWidget);

      // Onay açıkken A listeden çıkar (başka yerde tamamlandı); B artık
      // 0. konumda, C 1. konumda.
      rebuild(() => items = ['B', 'C']);
      await tester.pumpAndSettle();

      await confirmInDialog(tester);

      expect(deleted, ['B'], reason: 'onaylanan kayıt B; C silinmemeli');
      expect(tester.takeException(), isNull);
    });
  });

  group('ItemRowActions', () {
    Widget rowWith(Future<bool> Function() onDelete, {void Function()? onEdit}) =>
        ItemRowActions(
          itemKey: const ValueKey('swipe-1'),
          title: 'Kayıt',
          confirmTitle: 'Kayıt silinsin mi?',
          confirmMessage: '"Kayıt" silinecek.',
          onEdit: onEdit ?? () {},
          onDelete: onDelete,
          child: const ListTile(title: Text('Kayıt')),
        );

    testWidgets('uzun basış ve kaydırma aynı silme eylemine bağlanır',
        (tester) async {
      var deleted = 0;
      Future<bool> remove() async {
        deleted++;
        return false; // silinemedi: satır yerinde kalır
      }

      await pumpPlain(tester, rowWith(remove));

      await tester.longPress(find.text('Kayıt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);
      expect(deleted, 1);

      await tester.drag(find.text('Kayıt'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);
      expect(deleted, 2);
      // Silme başarısız (false): satır geri gelir.
      expect(find.text('Kayıt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('başarılı silmeden sonra satır gizlenir', (tester) async {
      await pumpPlain(tester, rowWith(() async => true));

      await tester.drag(find.text('Kayıt'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);

      expect(find.text('Kayıt'), findsNothing);
    });
  });

  group('Kokpit', () {
    late KokpitHarness harness;

    Routine daily(String id, String title, {String? time}) => Routine.fromMap({
          'id': id,
          'title': title,
          'category': 'operasyon',
          'time_of_day': time,
        });

    setUp(() {
      harness = KokpitHarness()..mockPlatformChannel();
      harness.routines.routines = [
        daily('r1', 'Sabah görev kontrolü'),
        // Saatli rutin bildirim planına girer.
        daily('r2', 'Gelen kutusu kontrolü', time: '23:30:00'),
        Routine(
          id: 'm1',
          title: 'Maaş ödemeleri',
          scope: Routine.scopeWork,
          category: 'finans',
          frequency: RoutineFrequency.monthly,
          dayOfMonth: today().day,
          hour: 10,
          minute: 0,
        ),
      ];
    });

    testWidgets('rutin satırında uzun basış menüsü açılır, kısa dokunuş '
        'hâlâ tamamlar', (tester) async {
      await harness.pump(tester);

      await longPressRow(tester, 'Sabah görev kontrolü');
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      expect(harness.isChecked(tester, 'Sabah görev kontrolü'),
          isFalse,
          reason: 'uzun basış işaretlemez');

      // Alt sayfayı dışına dokunarak kapat.
      await tester.tapAt(const Offset(187, 20));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsNothing);

      await harness.tapRow(tester, 'Sabah görev kontrolü');
      expect(harness.isChecked(tester, 'Sabah görev kontrolü'),
          isTrue);
      expect(harness.routines.toggles, hasLength(1));
    });

    testWidgets('rutin: Düzenle formu mevcut kaydı açar', (tester) async {
      await harness.pump(tester);

      await longPressRow(tester, 'Gelen kutusu kontrolü');
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();

      final sheet = find.byType(RoutineFormSheet);
      expect(sheet, findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.descendant(of: sheet, matching: find.byType(TextFormField)),
            )
            .controller!
            .text,
        'Gelen kutusu kontrolü',
      );
    });

    testWidgets('Kokpit\'ten rutin silince bildirim planı yeniden kurulur ve '
        'Kokpit sağlayıcısı tazelenir', (tester) async {
      final container = await harness.pump(tester);
      // Ana kabuk bu sağlayıcıyı dinler; testte aynı durum kurulur.
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = harness.notifications.resyncCount;
      expect(resyncBefore, greaterThan(0));
      expect(
        harness.notifications.lastRoutines.any((r) => r.routineId == 'r2'),
        isTrue,
      );
      expect(
        container.read(todayOccurrencesProvider).requireValue.daily,
        hasLength(2),
      );

      await longPressRow(tester, 'Gelen kutusu kontrolü');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Rutin silinsin mi?'), findsOneWidget);
      expect(
        find.text('"Gelen kutusu kontrolü" ve tamamlanma geçmişi kalıcı '
            'olarak silinecek.'),
        findsOneWidget,
      );
      await confirmInDialog(tester);

      expect(harness.routines.routines.map((r) => r.id), ['r1', 'm1']);
      expect(find.text('Gelen kutusu kontrolü'), findsNothing);
      expect(find.text('Rutin silindi.'), findsOneWidget);
      expect(harness.notifications.resyncCount, greaterThan(resyncBefore),
          reason: 'bildirim planı yeniden kurulmalı');
      expect(
        harness.notifications.lastRoutines.any((r) => r.routineId == 'r2'),
        isFalse,
      );
      expect(
        container.read(todayOccurrencesProvider).requireValue.daily,
        hasLength(1),
      );
      expect(find.text('0 / 1'), findsOneWidget);
      await drain(tester);
    });

    testWidgets('rutin: Vazgeç silmez ve bildirimi tazelemez', (tester) async {
      final container = await harness.pump(tester);
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = harness.notifications.resyncCount;

      await longPressRow(tester, 'Gelen kutusu kontrolü');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await cancelInDialog(tester);

      expect(harness.routines.routines, hasLength(3));
      expect(find.text('Gelen kutusu kontrolü'), findsOneWidget);
      expect(harness.notifications.resyncCount, resyncBefore);
    });

    testWidgets('rutin satırı sola kaydırılarak silinir', (tester) async {
      final container = await harness.pump(tester);
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = harness.notifications.resyncCount;

      await swipeRow(tester, 'Sabah görev kontrolü');
      expect(find.text('Rutin silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);

      expect(harness.routines.routines.map((r) => r.id), ['r2', 'm1']);
      expect(find.text('Sabah görev kontrolü'), findsNothing);
      expect(harness.notifications.resyncCount, greaterThan(resyncBefore));
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('aylık iş satırı (Ay görünümü): uzun basış menüsü ve silme',
        (tester) async {
      final container = await harness.pump(tester);
      await harness.showView(tester, 'Ay');
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = harness.notifications.resyncCount;

      await longPressRow(tester, 'Maaş ödemeleri');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);

      expect(harness.routines.routines.map((r) => r.id), ['r1', 'r2']);
      expect(find.text('Maaş ödemeleri'), findsNothing);
      expect(harness.notifications.resyncCount, greaterThan(resyncBefore));
      await drain(tester);
    });

    testWidgets('hatırlatma: görev silinince bildirim planı ve Kokpit '
        'listesi tazelenir', (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't1',
          title: 'Rapor gönder',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(today().year, today().month, today().day, 23, 59),
        ),
      ];
      final container = await harness.pump(tester);
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = harness.notifications.resyncCount;
      expect(
        container.read(upcomingRemindersProvider).requireValue,
        hasLength(1),
      );

      await longPressRow(tester, 'Rapor gönder');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);
      await tester.pumpAndSettle();

      expect(harness.tasks.deletedIds, ['t1']);
      expect(find.text('Rapor gönder'), findsNothing);
      expect(find.text('Görev silindi.'), findsOneWidget);
      expect(harness.notifications.resyncCount, greaterThan(resyncBefore));
      expect(container.read(upcomingRemindersProvider).requireValue, isEmpty);
      await drain(tester);
    });

    testWidgets('hatırlatma: sola kaydırma silme onayı sorar, Vazgeç geri '
        'getirir', (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't1',
          title: 'Rapor gönder',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(today().year, today().month, today().day, 23, 59),
        ),
      ];
      await harness.pump(tester);

      await swipeRow(tester, 'Rapor gönder');
      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      await cancelInDialog(tester);
      expect(harness.tasks.deletedIds, isEmpty);
      expect(find.text('Rapor gönder'), findsOneWidget);

      await swipeRow(tester, 'Rapor gönder');
      await confirmInDialog(tester);
      expect(harness.tasks.deletedIds, ['t1']);
      expect(find.text('Rapor gönder'), findsNothing);
      await drain(tester);
    });

    testWidgets('hatırlatma: Düzenle görev formunu açar', (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't1',
          title: 'Rapor gönder',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(today().year, today().month, today().day, 23, 59),
        ),
      ];
      await harness.pump(tester);

      await longPressRow(tester, 'Rapor gönder');
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskFormSheet), findsOneWidget);
    });

    testWidgets('Ay görünümü: aylık sabit ve randevu satırlarında menü',
        (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't9',
          title: 'Muhasebe randevusu',
          category: 'Finans',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(today().year, today().month, today().day, 12),
        ),
      ];
      await harness.pump(tester, month: DateTime.now());

      await longPressRow(tester, 'Maaş ödemeleri');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutineFormSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      await longPressRow(tester, 'Muhasebe randevusu');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);
      expect(harness.tasks.deletedIds, ['t9']);
      await drain(tester);
    });

    testWidgets('Ay görünümü: seçili gün listesindeki satırlar da menü açar',
        (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't9',
          title: 'Muhasebe randevusu',
          category: 'Finans',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(today().year, today().month, today().day, 12),
        ),
      ];
      final container = await harness.pump(tester, month: DateTime.now());
      container.read(kokpitSelectedDayProvider.notifier).state = today();
      await tester.pumpAndSettle();

      final panel = find.byKey(const ValueKey('kokpit-selected-day'));
      expect(panel, findsOneWidget);
      final line = find.descendant(
        of: panel,
        matching: find.text('Muhasebe randevusu'),
      );
      await tester.ensureVisible(line);
      await tester.pumpAndSettle();
      await tester.longPress(line);
      await tester.pumpAndSettle();

      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('menü ve onay 375x667, metin ölçeği $scale taşmaz',
          (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        await harness.pump(tester, textScale: scale);

        await longPressRow(tester, 'Sabah görev kontrolü');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Sil'));
        await tester.pumpAndSettle();
        expect(find.text('Rutin silinsin mi?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cancelInDialog(tester);

        await swipeRow(tester, 'Sabah görev kontrolü');
        expect(find.text('Rutin silinsin mi?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await cancelInDialog(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Operasyon', () {
    late FakeTasksRepository tasks;
    late FakeRoutinesRepository routines;
    late FakeNotesRepository notes;
    late FakeNotificationService notifications;

    setUp(() {
      tasks = FakeTasksRepository(
        tasks: const [
          TaskItem(
            id: 't2',
            title: 'Fatura ödemesi',
            category: 'Finans',
            priority: 'medium',
            status: 'todo',
          ),
        ],
      );
      routines = FakeRoutinesRepository(
        routines: const [
          Routine(
            id: 'r2',
            title: 'Ağırlık antrenmanı',
            category: 'spor',
            daysOfWeek: [1, 3, 5],
            hour: 19,
            minute: 0,
          ),
        ],
      );
      notes = FakeNotesRepository(
        notes: [
          NoteItem(
            id: 'n2',
            title: 'Yeni kampanya fikri',
            category: 'Fikir',
            updatedAt: DateTime(2026, 11, 9),
          ),
        ],
      );
      notifications = FakeNotificationService();
    });

    Future<ProviderContainer> pumpOps(
      WidgetTester tester, {
      double textScale = 1.0,
    }) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 1334);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = ProviderContainer(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(tasks),
          routinesRepositoryProvider.overrideWithValue(routines),
          notesRepositoryProvider.overrideWithValue(notes),
          healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
          notificationServiceProvider.overrideWithValue(notifications),
          remindersRepositoryProvider
              .overrideWithValue(MemoryRemindersRepository(userId: 'u1')),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: OperationsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> openSegment(WidgetTester tester, String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    testWidgets('görev: üç nokta menüsü yok; uzun basış ve kaydırma '
        'çalışır', (tester) async {
      final container = await pumpOps(tester);
      container.listen(notificationSyncProvider, (_, __) {});
      await tester.pumpAndSettle();
      final resyncBefore = notifications.resyncCount;

      expect(find.byTooltip('Seçenekler'), findsNothing);

      await longPressRow(tester, 'Fatura ödemesi');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskFormSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      await swipeRow(tester, 'Fatura ödemesi');
      expect(find.text('Görev silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);

      expect(tasks.deletedIds, ['t2']);
      expect(find.text('Fatura ödemesi'), findsNothing);
      expect(notifications.resyncCount, greaterThan(resyncBefore));
      await drain(tester);
    });

    testWidgets(
        'görev: onay açıkken liste kayarsa onaylanan görev silinir, komşusu değil',
        (tester) async {
      const a = TaskItem(
        id: 'a',
        title: 'Görev A',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      const b = TaskItem(
        id: 'b',
        title: 'Görev B',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      const c = TaskItem(
        id: 'c',
        title: 'Görev C',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      tasks.tasks = [a, b, c];
      final container = await pumpOps(tester);

      await swipeRow(tester, 'Görev B');
      expect(find.text('Görev silinsin mi?'), findsOneWidget);

      // Onay açıkken A başka yerde tamamlanır; liste yeniden okunur.
      tasks.tasks = [b, c];
      container.invalidate(opsTasksProvider);
      await tester.pumpAndSettle();

      await confirmInDialog(tester);

      expect(tasks.deletedIds, ['b'], reason: 'onaylanan görev B; C silinmemeli');
      expect(find.text('Görev C'), findsOneWidget);
      await drain(tester);
    });

    testWidgets(
        'görev: uzun basış onayı açıkken liste kayarsa seçim sessizce düşmez',
        (tester) async {
      const a = TaskItem(
        id: 'a',
        title: 'Görev A',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      const b = TaskItem(
        id: 'b',
        title: 'Görev B',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      const c = TaskItem(
        id: 'c',
        title: 'Görev C',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
      );
      tasks.tasks = [a, b, c];
      final container = await pumpOps(tester);

      await longPressRow(tester, 'Görev B');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Görev silinsin mi?'), findsOneWidget);

      tasks.tasks = [b, c];
      container.invalidate(opsTasksProvider);
      await tester.pumpAndSettle();

      await confirmInDialog(tester);

      expect(tasks.deletedIds, ['b'],
          reason: 'satır kayınca durum kayda bağlı kalır; seçim düşmez');
      await drain(tester);
    });

    testWidgets('rutin: uzun basışla silinince tamamlama geçmişi de gider',
        (tester) async {
      routines.completions = {
        RoutineCompletionKey('r2', today()),
      };
      final container = await pumpOps(tester);
      container.listen(notificationSyncProvider, (_, __) {});
      await openSegment(tester, 'Rutinler');
      final resyncBefore = notifications.resyncCount;

      await longPressRow(tester, 'Ağırlık antrenmanı');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(
        find.text('"Ağırlık antrenmanı" ve tamamlanma geçmişi kalıcı olarak '
            'silinecek.'),
        findsOneWidget,
      );
      await confirmInDialog(tester);

      expect(routines.routines, isEmpty);
      expect(routines.completions, isEmpty);
      expect(find.text('Ağırlık antrenmanı'), findsNothing);
      expect(notifications.resyncCount, greaterThan(resyncBefore));
      await drain(tester);
    });

    testWidgets('not: uzun basış ve kaydırma; üç nokta menüsü yok',
        (tester) async {
      await pumpOps(tester);
      await openSegment(tester, 'Notlar');
      expect(find.byTooltip('Seçenekler'), findsNothing);

      await longPressRow(tester, 'Yeni kampanya fikri');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Not silinsin mi?'), findsOneWidget);
      await cancelInDialog(tester);
      expect(notes.deletedIds, isEmpty);

      await swipeRow(tester, 'Yeni kampanya fikri');
      await confirmInDialog(tester);
      expect(notes.deletedIds, ['n2']);
      expect(find.text('Yeni kampanya fikri'), findsNothing);
      await drain(tester);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('üç liste 375x667, metin ölçeği $scale taşmaz',
          (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        await pumpOps(tester, textScale: scale);
        await swipeRow(tester, 'Fatura ödemesi');
        expect(tester.takeException(), isNull);
        await cancelInDialog(tester);

        await openSegment(tester, 'Rutinler');
        await longPressRow(tester, 'Ağırlık antrenmanı');
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(187, 20));
        await tester.pumpAndSettle();

        await openSegment(tester, 'Notlar');
        await swipeRow(tester, 'Yeni kampanya fikri');
        expect(tester.takeException(), isNull);
        await cancelInDialog(tester);
      });
    }
  });

  group('Sağlık', () {
    late FakeHealthRepository health;

    setUp(() {
      final day = today();
      health = FakeHealthRepository(
        nutritionLogs: [
          NutritionLog(
            id: 'n1',
            mealType: 'breakfast',
            foodName: 'Yulaf ezmesi',
            calories: 300,
            proteinG: 12,
            carbsG: 50,
            fatG: 6,
            eatenAt: day.add(const Duration(minutes: 1)),
          ),
        ],
        workouts: [
          WorkoutLog(
            id: 'k1',
            workoutType: 'kickboxing',
            durationMin: 60,
            caloriesBurned: 540,
            loggedAt: day.add(const Duration(minutes: 3)),
          ),
        ],
      );
    });

    Future<void> pumpSections(WidgetTester tester, {double scale = 1.0}) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 1334);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [healthRepositoryProvider.overrideWithValue(health)],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [MealsSection(), WorkoutsSection()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('öğün: uzun basış menüsü, onaydan sonra silme', (tester) async {
      await pumpSections(tester);
      expect(find.byTooltip('Seçenekler'), findsNWidgets(2),
          reason: 'üç nokta menüleri kalır (öğün + antrenman)');

      await longPressRow(tester, 'Yulaf ezmesi');
      expect(find.text('Düzenle'), findsOneWidget);
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Kayıt silinsin mi?'), findsOneWidget);
      await cancelInDialog(tester);
      expect(health.deletedIds, isEmpty);

      await longPressRow(tester, 'Yulaf ezmesi');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await confirmInDialog(tester);

      expect(health.deletedIds, ['n1']);
      expect(find.text('Yulaf ezmesi'), findsNothing);
      await drain(tester);
    });

    testWidgets('öğün: Düzenle formu açar, kaydırarak silinir',
        (tester) async {
      await pumpSections(tester);

      await longPressRow(tester, 'Yulaf ezmesi');
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(MealFormSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      await swipeRow(tester, 'Yulaf ezmesi');
      expect(find.text('Kayıt silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);
      expect(health.deletedIds, ['n1']);
      expect(find.text('Yulaf ezmesi'), findsNothing);
      await drain(tester);
    });

    testWidgets('antrenman: uzun basış, Düzenle ve kaydırarak silme',
        (tester) async {
      await pumpSections(tester);
      final title = find.textContaining('Kickboks');

      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.longPress(title);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutFormSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      await tester.drag(title, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Antrenman silinsin mi?'), findsOneWidget);
      await confirmInDialog(tester);

      expect(health.deletedIds, ['k1']);
      expect(find.textContaining('Kickboks'), findsNothing);
      await drain(tester);
    });

    testWidgets('silme hata verirse satır yerinde kalır ve uyarı çıkar',
        (tester) async {
      await pumpSections(tester);
      health.writeError = Exception('ağ yok');

      await swipeRow(tester, 'Yulaf ezmesi');
      await confirmInDialog(tester);

      expect(find.text('Yulaf ezmesi'), findsOneWidget);
      expect(find.text(
          'Silinemedi. Bağlantını kontrol edip tekrar dene.'), findsOneWidget);
      expect(health.deletedIds, isEmpty);
      await drain(tester);
    });

    for (final scale in const [1.0, 1.3]) {
      testWidgets('öğün ve antrenman satırları 375x667, ölçek $scale taşmaz',
          (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        await pumpSections(tester, scale: scale);
        await longPressRow(tester, 'Yulaf ezmesi');
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(187, 20));
        await tester.pumpAndSettle();
        await swipeRow(tester, 'Yulaf ezmesi');
        expect(tester.takeException(), isNull);
        await cancelInDialog(tester);
      });
    }
  });
}
