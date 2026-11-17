import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_screen.dart';
import 'package:kisisel_asistan/features/operations/presentation/routine_form_sheet.dart';
import 'package:kisisel_asistan/features/operations/presentation/task_form_sheet.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

void main() {
  late FakeTasksRepository tasks;
  late FakeRoutinesRepository routines;
  late FakeNotesRepository notes;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    tasks = FakeTasksRepository(
      tasks: [
        TaskItem(
          id: 't1',
          title: 'Haftalık vardiya çizelgesini yayınla ve ekibe duyur',
          category: 'Ekip',
          priority: 'high',
          status: 'todo',
          assignee: 'Ayşe',
          dueAt: DateTime(2099, 1, 5, 15),
          remindAt: DateTime(2099, 1, 5, 14, 30),
        ),
        const TaskItem(
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
          id: 'r1',
          title: 'Sabah görev ve takvim kontrolü (plan, öncelik)',
          scope: Routine.scopeWork,
          category: 'operasyon',
          hour: 9,
          minute: 0,
        ),
        Routine(
          id: 'r2',
          title: 'Ağırlık antrenmanı',
          category: 'spor',
          daysOfWeek: [1, 3, 5],
          hour: 19,
          minute: 0,
          notify: false,
        ),
        Routine(
          id: 'r3',
          title: 'Maaş ödemeleri',
          scope: Routine.scopeWork,
          category: 'finans',
          frequency: RoutineFrequency.monthly,
          dayOfMonth: 15,
          hour: 10,
          minute: 0,
        ),
      ],
    );
    notes = FakeNotesRepository(
      notes: [
        NoteItem(
          id: 'n1',
          title: 'Pazartesi toplantı notları ve alınan kararlar',
          content: 'Push saatleri yeniden planlanacak. ' * 6,
          category: 'Toplantı',
          isPinned: true,
          updatedAt: DateTime(2026, 11, 10),
        ),
        NoteItem(
          id: 'n2',
          title: 'Yeni kampanya fikri',
          category: 'Fikir',
          updatedAt: DateTime(2026, 11, 9),
        ),
      ],
    );
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(tasks),
          routinesRepositoryProvider.overrideWithValue(routines),
          notesRepositoryProvider.overrideWithValue(notes),
          healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: OperationsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Snackbar zamanlayıcısı test bitmeden kapansın.
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('üç bölüm 375x667 ve 1.3 metin ölçeğinde taşmadan çizilir',
      (tester) async {
    await pumpScreen(tester, textScale: 1.3);
    expect(find.text('Fatura ödemesi'), findsOneWidget);
    expect(find.text('Ekle'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Sabitler').first);
    await tester.pumpAndSettle();
    expect(find.text('Günlük ve haftalık'), findsOneWidget);
    expect(find.text('Aylık'), findsOneWidget);
    expect(find.text('Maaş ödemeleri'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Notlar').first);
    await tester.pumpAndSettle();
    expect(find.text('Yeni kampanya fikri'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formdan aylık sabit eklenir: frequency monthly + seçilen gün',
      (tester) async {
    await pumpScreen(tester, textScale: 1.3);
    await tester.tap(find.text('Sabitler').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    final sheet = find.byType(RoutineFormSheet);
    expect(sheet, findsOneWidget);
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(TextFormField)),
      'Kira ödemesi',
    );
    final monthly = find.descendant(of: sheet, matching: find.text('Aylık'));
    await tester.ensureVisible(monthly);
    await tester.pumpAndSettle();
    await tester.tap(monthly);
    await tester.pumpAndSettle();

    final day = find.byKey(const ValueKey('dom-28'));
    await tester.ensureVisible(day);
    await tester.pumpAndSettle();
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    final created = routines.routines.last;
    expect(created.title, 'Kira ödemesi');
    expect(created.frequency, RoutineFrequency.monthly);
    expect(created.dayOfMonth, 28);
    expect(find.text('Kira ödemesi'), findsOneWidget);
    await drainSnackBar(tester);
  });

  testWidgets('görev tamamlanınca depo çağrılır, geri alınabilir',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('task-check-t2')));
    await tester.pumpAndSettle();
    expect(tasks.completedIds, ['t2']);

    // Tamamlanan görev listede kalır; kutuya yeniden dokununca geri alınır.
    await tester.tap(find.byKey(const ValueKey('task-check-t2')));
    await tester.pumpAndSettle();
    expect(tasks.reopenedIds, ['t2']);
    await drainSnackBar(tester);
  });

  testWidgets('"Hatırlat" kapatılan görev notify = false ve hatırlatmasız kaydedilir',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(
      find.text('Haftalık vardiya çizelgesini yayınla ve ekibe duyur'),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('task-remind'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    final saved = tasks.tasks.firstWhere((t) => t.id == 't1');
    expect(saved.notify, isFalse);
    expect(saved.remindAt, isNull);
    expect(saved.dueAt, DateTime(2099, 1, 5, 15));

    // Yeniden açıldığında anahtar kapalı görünür.
    await tester.tap(
      find.text('Haftalık vardiya çizelgesini yayınla ve ekibe duyur'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await drainSnackBar(tester);
  });

  testWidgets(
      'spor sabiti eklenip silinince haftalık antrenman planı tazelenir',
      (tester) async {
    await pumpScreen(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OperationsScreen)),
    );
    // Sağlık sekmesi açıkmış gibi: haftalık plan dinleniyor.
    container.listen(weekWorkoutPlanProvider, (_, __) {});
    await tester.pumpAndSettle();
    // r2: Pzt, Çar, Cum.
    expect(
      container.read(weekWorkoutPlanProvider).requireValue.plannedCount,
      3,
    );

    await tester.tap(find.text('Sabitler').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();
    final sheet = find.byType(RoutineFormSheet);
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(TextFormField)),
      'Akşam koşusu',
    );
    final spor = find.descendant(of: sheet, matching: find.text('Spor'));
    await tester.ensureVisible(spor);
    await tester.pumpAndSettle();
    await tester.tap(spor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(routines.routines.last.category, 'spor');
    // Her gün planlı yeni spor sabiti: 3 + 7.
    expect(
      container.read(weekWorkoutPlanProvider).requireValue.plannedCount,
      10,
    );
    await drainSnackBar(tester);

    // Silme de aynı sağlayıcıyı tazeler.
    final row = find.ancestor(
      of: find.text('Ağırlık antrenmanı'),
      matching: find.byType(InkWell),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.byTooltip('Seçenekler')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sil'));
    await tester.pumpAndSettle();
    expect(
      container.read(weekWorkoutPlanProvider).requireValue.plannedCount,
      7,
    );
    await drainSnackBar(tester);
  });

  testWidgets(
      'bu oturumda tamamlanan görev düzenlenince satır yeni başlığı gösterir',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('task-check-t2')));
    await tester.pumpAndSettle();
    await drainSnackBar(tester);

    await tester.tap(find.text('Fatura ödemesi'));
    await tester.pumpAndSettle();
    final sheet = find.byType(TaskFormSheet);
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(TextFormField)).first,
      'Fatura ödemesi (Kasım)',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(
      tasks.tasks.firstWhere((t) => t.id == 't2').title,
      'Fatura ödemesi (Kasım)',
    );
    expect(find.text('Fatura ödemesi (Kasım)'), findsOneWidget);
    expect(find.text('Fatura ödemesi'), findsNothing);
    // Görev hâlâ tamamlanmış görünür ve geri alınabilir.
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('task-check-t2')))
          .value,
      isTrue,
    );
    await drainSnackBar(tester);

    // Form yeniden açıldığında kayıtlı (yeni) değerlerle başlar.
    await tester.tap(find.text('Fatura ödemesi (Kasım)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find
                .descendant(of: sheet, matching: find.byType(TextFormField))
                .first,
          )
          .controller!
          .text,
      'Fatura ödemesi (Kasım)',
    );
  });
}
