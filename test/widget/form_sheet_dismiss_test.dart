import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
import '../helpers/test_fonts.dart';

/// Yazmalar bu tamamlanana kadar bekler (yavaş bağlantı). Test gövdesinde
/// (sahte zaman bölgesinde) oluşturulur; yoksa `pump` devamını çalıştırmaz.
late Completer<void> gate;

class _GatedTasks extends FakeTasksRepository {
  @override
  Future<TaskItem> create({
    required String title,
    String? description,
    String category = 'Kişisel',
    String priority = 'medium',
    String? assignee,
    DateTime? dueAt,
    DateTime? remindAt,
    bool notify = true,
  }) async {
    await gate.future;
    return super.create(title: title, category: category, priority: priority);
  }
}

class _GatedRoutines extends FakeRoutinesRepository {
  @override
  Future<Routine> create(Routine routine) async {
    await gate.future;
    return super.create(routine);
  }
}

class _GatedNotes extends FakeNotesRepository {
  @override
  Future<NoteItem> create({
    required String title,
    String content = '',
    String category = 'Kişisel',
    bool isPinned = false,
  }) async {
    await gate.future;
    return super.create(title: title, content: content, category: category);
  }
}

class _GatedHealth extends FakeHealthRepository {
  @override
  Future<NutritionLog> createNutritionLog(NutritionLog log) async {
    await gate.future;
    return super.createNutritionLog(log);
  }

  @override
  Future<WorkoutLog> createWorkout(WorkoutLog workout) async {
    await gate.future;
    return super.createWorkout(workout);
  }

  @override
  Future<WeightEntry> addWeight(double weightKg, {DateTime? at}) async {
    await gate.future;
    return super.addWeight(weightKg, at: at);
  }
}

void main() {
  late QuickAddHarness harness;
  late _GatedTasks tasks;
  late _GatedRoutines routines;
  late _GatedNotes notes;
  late _GatedHealth health;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    harness = QuickAddHarness(
      work: (_) async => ParsedEntry.fromJson(const {
        'tasks': [
          {'title': 'Fatura öde', 'category': 'Finans', 'priority': 'medium'},
        ],
      }),
    );
    tasks = _GatedTasks();
    routines = _GatedRoutines();
    notes = _GatedNotes();
    health = _GatedHealth();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<void> pumpShell(WidgetTester tester, String tab) async {
    gate = Completer<void>();
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...harness.overrides,
          tasksRepositoryProvider.overrideWithValue(tasks),
          routinesRepositoryProvider.overrideWithValue(routines),
          notesRepositoryProvider.overrideWithValue(notes),
          healthRepositoryProvider.overrideWithValue(health),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('tr', 'TR'),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tab));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Dönen gösterge yüzünden pumpAndSettle kullanılamaz.
  Future<void> pumpFor(WidgetTester tester, int ms) async {
    for (var elapsed = 0; elapsed < ms; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Sayfayı tutamağından aşağı fırlatır (kullanıcının kaydırarak kapatması).
  Future<void> flingSheetDown(WidgetTester tester) async {
    final sheet = find.byType(BottomSheet);
    final top = tester.getTopLeft(sheet);
    await tester.flingFrom(
      Offset(top.dx + tester.getSize(sheet).width / 2, top.dy + 20),
      const Offset(0, 300),
      2500,
    );
  }

  /// Formu doldurup Kaydet'e basar; yazma [gate] yüzünden askıda kalır.
  Future<void> startSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Kaydet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  }

  void expectShellAlive() {
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byTooltip('Yeni giriş'), findsOneWidget);
  }

  final forms = <String, (String, Future<void> Function(WidgetTester), int Function())>{
    'görev': (
      'Operasyon',
      (tester) async {
        await tapVisible(tester, find.text('Ekle'));
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Başlık'), 'Yeni iş');
      },
      () => tasks.tasks.length,
    ),
    'sabit': (
      'Operasyon',
      (tester) async {
        await tapVisible(tester, find.text('Sabitler'));
        await tapVisible(tester, find.text('Ekle'));
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Başlık'), 'Rapor');
      },
      () => routines.routines.length,
    ),
    'not': (
      'Operasyon',
      (tester) async {
        await tapVisible(tester, find.text('Notlar'));
        await tapVisible(tester, find.text('Ekle'));
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Başlık'), 'Not');
      },
      () => notes.notes.length,
    ),
    'öğün': (
      'Sağlık',
      (tester) async {
        await tapVisible(tester, find.text('Öğün ekle'));
        await tester.enterText(find.byKey(const Key('meal-name')), 'Tavuk');
      },
      () => health.nutritionLogs.length,
    ),
    'antrenman': (
      'Sağlık',
      (tester) async {
        await tapVisible(tester, find.widgetWithText(TextButton, 'Ekle').last);
        await tester.enterText(
            find.byKey(const Key('workout-duration')), '30');
      },
      () => health.workouts.length,
    ),
    'kilo': (
      'Sağlık',
      (tester) async {
        await tapVisible(tester, find.text('Kilo ekle'));
        await tester.enterText(find.byKey(const Key('weight-kg')), '82,9');
      },
      () => health.weights.length,
    ),
  };

  for (final MapEntry(key: name, value: (tab, open, savedCount))
      in forms.entries) {
    testWidgets(
        '$name formu kayıt sürerken kaydırılarak kapatılırsa ana kabuk kapanmaz',
        (tester) async {
      await pumpShell(tester, tab);
      await open(tester);
      await startSave(tester);

      await flingSheetDown(tester);
      await pumpFor(tester, 1000);
      expect(find.byType(BottomSheet), findsNothing);
      expectShellAlive();

      gate.complete();
      await pumpFor(tester, 1000);
      expect(savedCount(), 1, reason: 'kayıt yine de yazılır');
      expectShellAlive();
    });

    testWidgets(
        '$name formu: kayıt kapanış animasyonu sürerken biterse ana kabuk kapanmaz',
        (tester) async {
      await pumpShell(tester, tab);
      await open(tester);
      await startSave(tester);

      await flingSheetDown(tester);
      await tester.pump(const Duration(milliseconds: 16));
      // Rota kapandı ama sayfa hâlâ ağaçta (State.mounted == true).
      expect(find.byType(BottomSheet), findsOneWidget);

      gate.complete();
      await pumpFor(tester, 1000);
      expect(savedCount(), 1);
      expect(find.byType(BottomSheet), findsNothing);
      expectShellAlive();
    });
  }

  testWidgets('not formu kayıt sürerken dışına dokunularak kapatılırsa ana kabuk kapanmaz',
      (tester) async {
    await pumpShell(tester, 'Operasyon');
    await forms['not']!.$2(tester);
    await startSave(tester);

    final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
    expect(top, greaterThan(40), reason: 'bariyer görünür olmalı');
    await tester.tapAt(Offset(195, top / 2));
    await pumpFor(tester, 1000);
    expect(find.byType(BottomSheet), findsNothing);

    gate.complete();
    await pumpFor(tester, 1000);
    expect(notes.notes, hasLength(1));
    expectShellAlive();
  });

  testWidgets(
      'AI giriş: kayıt, sayfa kapanırken biterse ana kabuk kapanmaz',
      (tester) async {
    await pumpShell(tester, 'Operasyon');
    harness.repository.gate = gate;
    await tester.tap(find.byTooltip('Yeni giriş'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fatura öde');
    await tester.pump();
    await tester.tap(find.text('Ayrıştır'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 kaydı kaydet'));
    await tester.pump();
    expect(find.text('Kaydediliyor…'), findsOneWidget);

    // Dışına dokun: rota kapanır, çıkış animasyonu sürer.
    await tester.tapAt(const Offset(195, 20));
    await tester.pump(const Duration(milliseconds: 16));
    gate.complete();
    await pumpFor(tester, 1000);

    expect(harness.repository.saved, hasLength(1));
    expectShellAlive();
  });

  testWidgets('kapatılmayan form kayıt bitince kendisi kapanır (kontrol)',
      (tester) async {
    await pumpShell(tester, 'Operasyon');
    await forms['görev']!.$2(tester);
    await startSave(tester);

    gate.complete();
    await pumpFor(tester, 1000);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Görev eklendi.'), findsOneWidget);
    expectShellAlive();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
