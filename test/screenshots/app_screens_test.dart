// Önizleme için gerçek ekran görüntüleri üretir (örnek veriyle).
// Çalıştırma: flutter test --update-goldens test/screenshots/app_screens_test.dart
@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/quick_add_repository.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_quick_add_modal.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
import '../helpers/test_fonts.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  testWidgets('ekran görüntüleri', (tester) async {
    final now = DateTime.now();
    final today = AppDates.startOfDay(now);
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    int dayIn(int offset) => (now.day + offset).clamp(1, lastDay);
    final created = DateTime(now.year, now.month - 2, 1);

    Routine r(String id, String title, String scope, String cat, int h, int m,
            {List<int> days = Routine.everyDay}) =>
        Routine(
          id: id,
          title: title,
          scope: scope,
          category: cat,
          daysOfWeek: days,
          hour: h,
          minute: m,
          createdAt: created,
        );
    Routine monthly(String id, String title, String scope, String cat, int day) =>
        Routine(
          id: id,
          title: title,
          scope: scope,
          category: cat,
          frequency: RoutineFrequency.monthly,
          dayOfMonth: day,
          hour: 10,
          minute: 0,
          createdAt: created,
        );

    final routines = FakeRoutinesRepository(
      routines: [
        r('r1', 'Sabah tartı ve kilo kaydı', 'Kişisel', 'beslenme', 8, 0),
        r('r2', 'Sabah push performans kontrolü', 'Pusholder', 'operasyon', 9, 0),
        r('r3', 'Editör vardiya kontrolü', 'Pusholder', 'operasyon', 9, 30),
        r('r4', 'Öğlen gündem ve push takvimi', 'Pusholder', 'operasyon', 13, 0),
        r('r5', 'Ağırlık antrenmanı', 'Kişisel', 'spor', 19, 0,
            days: [now.weekday]),
        r('r6', 'Akşam operasyon kapanışı', 'Pusholder', 'operasyon', 22, 0),
        monthly('m1', 'Maaş ödemeleri', 'Pusholder', 'finans', dayIn(2)),
        monthly('m2', 'Aylık push performans raporu', 'Pusholder', 'operasyon', 1),
        monthly('m3', 'Kira ve faturalar', 'Kişisel', 'finans', dayIn(-3)),
      ],
      completions: [
        RoutineCompletionKey('r1', today, completedAt: now),
        RoutineCompletionKey('r2', today, completedAt: now),
        RoutineCompletionKey('r3', today, completedAt: now),
        RoutineCompletionKey('m2', DateTime(now.year, now.month, 1),
            completedAt: DateTime(now.year, now.month, 1, 11)),
      ],
    );

    TaskItem t(String id, String title, String cat, String prio, DateTime due,
            {String? who}) =>
        TaskItem(
          id: id,
          title: title,
          category: cat,
          priority: prio,
          status: 'todo',
          assignee: who,
          dueAt: due,
          remindAt: due.subtract(const Duration(minutes: 30)),
        );
    final tasks = FakeTasksRepository(tasks: [
      t('t1', 'Duhan ile vardiya planı', 'Ekip', 'high',
          today.add(const Duration(days: 1, hours: 15)),
          who: 'Duhan'),
      t('t2', 'Dişçi randevusu', 'Kişisel', 'medium',
          today.add(const Duration(days: 3, hours: 14))),
      t('t3', 'Push performans raporunu hazırla', 'Pusholder', 'high',
          today.add(const Duration(days: 2, hours: 12))),
      t('t4', 'Aylık gelir-gider tablosu', 'Finans', 'medium',
          today.add(const Duration(days: 6, hours: 18))),
    ]);

    final health = FakeHealthRepository(
      metrics: [
        for (var d = 1; d <= now.day; d++)
          DailyHealthMetric(
            day: DateTime(now.year, now.month, d),
            steps: 6200 + (d * 517) % 4800,
            activeKcal: 320 + (d * 37) % 260,
            sleepMinutes: 390 + (d * 23) % 90,
          ),
      ],
      weights: [
        WeightEntry(id: 'w1', weightKg: 84.5, loggedAt: DateTime(now.year, now.month, 1, 8)),
        WeightEntry(id: 'w2', weightKg: 83.6, loggedAt: today.add(const Duration(hours: 8))),
      ],
      nutrition: [
        for (var d = 1; d <= now.day; d++)
          DailyNutritionTotal(
            day: DateTime(now.year, now.month, d),
            calories: 1850 + (d * 61) % 320,
            proteinG: 150 + (d * 7) % 30,
            carbsG: 170,
            fatG: 60,
            entryCount: 4,
          ),
      ],
    );

    final parser = FakeGeminiParserService(
      (_) async => ParsedEntry.fromJson({
        'nutrition': [
          {
            'meal_type': 'lunch',
            'food_name': 'Tavuk göğsü',
            'quantity_text': '200 gr',
            'calories': 330,
            'protein_g': 62,
            'carbs_g': 0,
            'fat_g': 7,
            'eaten_at': today.add(const Duration(hours: 13)).toIso8601String(),
          },
          {
            'meal_type': 'lunch',
            'food_name': 'Tam çavdar ekmeği',
            'quantity_text': '2 dilim',
            'calories': 130,
            'protein_g': 5,
            'carbs_g': 24,
            'fat_g': 2,
            'eaten_at': today.add(const Duration(hours: 13)).toIso8601String(),
          },
        ],
      }),
    );

    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          geminiParserServiceProvider.overrideWith((ref, mode) => parser),
          quickAddRepositoryProvider
              .overrideWithValue(RecordingQuickAddRepository()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
          routinesRepositoryProvider.overrideWithValue(routines),
          tasksRepositoryProvider.overrideWithValue(tasks),
          notesRepositoryProvider.overrideWithValue(
            FakeNotesRepository(notes: [
              NoteItem(
                id: 'n1',
                title: 'Form hedefi',
                content: '84.5 kg → 78 kg. Kas kütlesini koru.',
                isPinned: true,
                createdAt: now,
              ),
              NoteItem(
                id: 'n2',
                title: 'Fikir: son dakika push şablonları',
                content: 'Sık kullanılan başlık kalıpları için hazır set.',
                category: 'Fikir',
                createdAt: now,
              ),
            ]),
          ),
          healthRepositoryProvider.overrideWithValue(health),
          kokpitRepositoryProvider.overrideWithValue(
            FakeKokpitRepository(
              nutrition: const NutritionSummary(
                calories: 1240,
                proteinG: 96,
                carbsG: 118,
                fatG: 38,
                entryCount: 3,
              ),
            ),
          ),
          healthServiceProvider.overrideWithValue(
            FakeHealthService(
              HealthSnapshot(
                status: HealthStatus.ok,
                steps: 6480,
                activeKcal: 412,
                sleepMinutes: 432,
                readAt: now,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('tr', 'TR')],
          locale: const Locale('tr', 'TR'),
          home: const RepaintBoundary(
            key: ValueKey('shot'),
            child: HomeShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/$name.png'),
      );
    }

    await shot('01_kokpit_gun');

    await tester.tap(find.text('Ay'));
    await shot('02_kokpit_ay');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -620));
    await shot('03_kokpit_ay_alt');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gün'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Yeni giriş'));
    await shot('04_giris_secimi');
    await tester.tap(find.text('Sağlık & beslenme girişi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AiQuickAddModal),
        matching: find.byType(TextField),
      ),
      'Öğlen 200 gr tavuk göğsü ve 2 dilim tam çavdar ekmeği yedim',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayrıştır'));
    await shot('05_saglik_girisi');
    await tester.tap(find.byTooltip('Kapat').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Operasyon'));
    await shot('06_operasyon_gorevler');
    await tester.tap(find.text('Sabitler'));
    await shot('07_operasyon_sabitler');

    await tester.tap(find.byTooltip('Kokpit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ayarlar'));
    await shot('08_ayarlar');
  });
}
