import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_source.dart'
    show MemoryAppleHealthConsentStore, appleHealthConsentStoreProvider;
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_screen.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_providers.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

/// supabase/schema.sql içindeki seed verisine yakın örnek rutinler.
List<Routine> sampleRoutines() => [
      Routine.fromMap(const {
        'id': 'r1',
        'title': 'Sabah tartı ve kilo kaydı',
        'category': 'beslenme',
        'time_of_day': '08:00:00',
      }),
      Routine.fromMap(const {
        'id': 'r2',
        'title': 'Sabah görev ve takvim kontrolü (plan, öncelik)',
        'category': 'operasyon',
        'time_of_day': '09:00:00',
      }),
      Routine.fromMap(const {
        'id': 'r3',
        'title': 'Ekip planı kontrolü (Ayşe, Can, Elif, Deniz)',
        'category': 'operasyon',
        'time_of_day': '09:30:00',
      }),
      Routine.fromMap(const {
        'id': 'r4',
        'title': 'Ağırlık antrenmanı',
        'category': 'spor',
        'time_of_day': '19:00:00',
      }),
      Routine.fromMap(const {
        'id': 'r5',
        'title': 'Saatsiz rutin',
        'category': 'kisisel',
        'time_of_day': null,
      }),
    ];

List<TaskItem> sampleReminders() => [
      TaskItem(
        id: 't1',
        title: 'Haftalık vardiya çizelgesini yayınla',
        category: 'Ekip',
        priority: 'high',
        status: 'todo',
        assignee: 'Ayşe',
        remindAt: DateTime(2099, 1, 5, 14, 30),
        dueAt: DateTime(2099, 1, 5, 15),
      ),
      TaskItem(
        id: 't2',
        title: 'Push bildirim performans raporunu hazırla ve ekip ile paylaş, '
            'ardından haftalık toplantıda sun',
        category: 'İş',
        priority: 'high',
        status: 'todo',
        dueAt: DateTime(2099, 1, 6, 12),
      ),
      TaskItem(
        id: 't3',
        title: 'Aylık gelir-gider tablosunu güncelle',
        category: 'Finans',
        priority: 'medium',
        status: 'todo',
        dueAt: DateTime(2099, 1, 9, 18),
      ),
    ];

const NutritionSummary sampleNutrition = NutritionSummary(
  calories: 1450,
  proteinG: 132,
  carbsG: 118,
  fatG: 47,
  entryCount: 5,
);

HealthSnapshot sampleHealth() => HealthSnapshot(
      status: HealthStatus.ok,
      steps: 8432,
      activeKcal: 512,
      sleepMinutes: 452,
      readAt: DateTime(2026, 11, 16, 10, 30),
    );

DateTime today() => AppDates.startOfDay(DateTime.now());

void main() {
  late FakeRoutinesRepository routines;
  late FakeTasksRepository tasks;
  late FakeKokpitRepository kokpit;
  late FakeHealthRepository healthStore;
  late FakeSettingsRepository settings;
  late FakeHealthService health;
  late bool realFonts;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  setUp(() {
    routines = FakeRoutinesRepository(routines: sampleRoutines());
    tasks = FakeTasksRepository(tasks: sampleReminders());
    kokpit = FakeKokpitRepository(nutrition: sampleNutrition);
    healthStore = FakeHealthRepository();
    settings = FakeSettingsRepository();
    health = FakeHealthService(sampleHealth());

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

  Future<ProviderContainer> pumpKokpit(
    WidgetTester tester, {
    Size size = const Size(375, 667),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        kokpitRepositoryProvider.overrideWithValue(kokpit),
        healthRepositoryProvider.overrideWithValue(healthStore),
        settingsRepositoryProvider.overrideWithValue(settings),
        appleHealthConsentStoreProvider.overrideWithValue(
          MemoryAppleHealthConsentStore(grantAll: true),
        ),
        healthServiceProvider.overrideWithValue(health),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: KokpitScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Listeyi sonuna kadar kaydırır; her adımda oluşan çizim hatalarını toplar.
  Future<List<Object>> scrollThrough(WidgetTester tester) async {
    final errors = <Object>[];
    void collect() {
      Object? e;
      while ((e = tester.takeException()) != null) {
        errors.add(e!);
      }
    }

    collect();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    while (scrollable.position.pixels < scrollable.position.maxScrollExtent) {
      scrollable.position.jumpTo(
        (scrollable.position.pixels + 300)
            .clamp(0, scrollable.position.maxScrollExtent)
            .toDouble(),
      );
      await tester.pumpAndSettle();
      collect();
    }
    return errors;
  }

  group('içerik', () {
    testWidgets('örnek veriyle tüm bölümler çizilir', (tester) async {
      await pumpKokpit(tester);

      // Tek Sağlık kartı: kalan halkası, yenen/hedef, adım çubuğu.
      expect(find.text('Sağlık'), findsOneWidget);
      expect(find.text('Kalan 550 kcal'), findsOneWidget);
      expect(find.text('1.450 / 2.000 kcal'), findsOneWidget);
      expect(find.text('8.432 / 8.000 adım'), findsOneWidget);
      expect(find.text('Protein'), findsNothing, reason: 'makro yok');
      expect(find.text('Uyku'), findsNothing,
          reason: 'adım/uyku kartları Sağlık kartına katıldı');

      expect(find.text('Günlük işler'), findsOneWidget);
      expect(find.text('0 / 5'), findsOneWidget);
      expect(find.text('5 iş kaldı'), findsOneWidget);
      expect(find.text('Su'), findsOneWidget);
      expect(healthStore.upsertedHealth, hasLength(1),
          reason: 'HealthKit özeti Supabase\'e yedeklenir');

      // Görünüm seçici ve ayrı arkadaş/ayarlar ikonları yok.
      expect(find.text('Gün'), findsNothing);
      expect(find.text('Ay'), findsNothing);
      expect(find.byTooltip('Ayarlar'), findsNothing);
      expect(find.byTooltip('Hesap'), findsOneWidget);

      await scrollThrough(tester);
      expect(find.text('Bugünün işleri'), findsOneWidget);
      expect(find.text('Sabah tartı ve kilo kaydı'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.textContaining('Tümünü gör'), findsNothing,
          reason: '5 kayıt sığar; kısayol yalnızca gizli satır varken');
      // Yarına ve sonrasına düşen görevler Kokpit'te listelenmez.
      expect(find.text('Haftalık vardiya çizelgesini yayınla'), findsNothing);
      expect(find.text('Bugün ve yaklaşanlar'), findsNothing);
    });

    testWidgets('bugüne düşen görev listeye ve sayaca girer; en fazla 5 satır',
        (tester) async {
      final now = DateTime.now();
      tasks.tasks = [
        ...sampleReminders(),
        TaskItem(
          id: 'today',
          title: 'Bugünkü görev',
          category: 'İş',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(now.year, now.month, now.day, 23, 59),
        ),
      ];
      await pumpKokpit(tester);
      expect(find.text('0 / 6'), findsOneWidget);
      await scrollThrough(tester);
      expect(find.text('Tümünü gör (6)'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(4),
          reason: '5 satır arası 4 ayraç');
    });

    testWidgets('kalori hedefi aşılınca "fazla" yazar', (tester) async {
      kokpit.nutrition = const NutritionSummary(calories: 2350);
      await pumpKokpit(tester);
      expect(find.text('350 kcal fazla'), findsOneWidget);
    });

    testWidgets('hedefler kullanıcı ayarlarından gelir', (tester) async {
      settings.settings = const UserSettings.defaults().copyWith(
        dailyCalories: 2500,
        dailySteps: 12000,
        sleepMinutes: 480,
      );
      await pumpKokpit(tester);

      expect(find.text('1.450 / 2.500 kcal'), findsOneWidget);
      expect(find.text('Kalan 1.050 kcal'), findsOneWidget);
      expect(find.text('8.432 / 12.000 adım'), findsOneWidget);
    });

    testWidgets('ayarlar okunamazsa varsayılan hedeflerle çizilir',
        (tester) async {
      settings.fetchError = Exception('ağ yok');
      await pumpKokpit(tester);
      expect(find.text('1.450 / 2.000 kcal'), findsOneWidget);
      expect(find.text('8.432 / 8.000 adım'), findsOneWidget);
    });

    testWidgets('aylık işler Kokpit sayacına ve listesine girmez',
        (tester) async {
      routines.routines = [
        ...sampleRoutines(),
        Routine(
          id: 'm1',
          title: 'Maaş ödemeleri',
          frequency: RoutineFrequency.monthly,
          dayOfMonth: DateTime.now().day,
        ),
      ];
      final container = await pumpKokpit(tester);

      expect(find.text('0 / 5'), findsOneWidget);
      await scrollThrough(tester);
      expect(find.text('Maaş ödemeleri'), findsNothing);
      final state = container.read(todayOccurrencesProvider).value!;
      expect(state.monthly.single.routine.id, 'm1');
    });

    testWidgets('boş veri: boş durum mesajları', (tester) async {
      routines.routines = [];
      tasks.tasks = [];
      health.snapshot = const HealthSnapshot(status: HealthStatus.unavailable);
      await pumpKokpit(tester);

      await scrollThrough(tester);
      expect(
        find.textContaining('Bugün için rutin ya da görev yok.'),
        findsOneWidget,
      );
      expect(find.textContaining('yalnızca iPhone\'da'), findsOneWidget);
      expect(healthStore.upsertedHealth, isEmpty);
    });

    testWidgets('HealthKit reddedilince Bağlan düğmesi çıkar', (tester) async {
      health.snapshot = const HealthSnapshot(status: HealthStatus.denied);
      await pumpKokpit(tester);
      expect(find.textContaining('HealthKit erişimi verilmedi'), findsOneWidget);
      expect(find.text('Bağlan'), findsOneWidget);
    });

    testWidgets('Tümünü gör İşler sekmesini Rutinler görünümüyle ister',
        (tester) async {
      final now = DateTime.now();
      tasks.tasks = [
        ...sampleReminders(),
        TaskItem(
          id: 'today',
          title: 'Bugünkü görev',
          category: 'İş',
          priority: 'medium',
          status: 'todo',
          dueAt: DateTime(now.year, now.month, now.day, 23, 59),
        ),
      ];
      final container = await pumpKokpit(tester);
      await scrollThrough(tester);
      await tester.tap(find.text('Tümünü gör (6)'));
      await tester.pump();
      expect(container.read(homeTabRequestProvider), 1);
      expect(container.read(opsSegmentProvider), OpsSegment.routines);
    });
  });

  // Taşma testleri gerçek yazı tipi (Roboto) ile ölçülür; iPhone'daki SF Pro
  // en az bu kadar geniştir. 375x667 = iPhone SE (2./3. nesil).
  const busyNutrition = NutritionSummary(
    calories: 2350,
    proteinG: 185,
    carbsG: 240,
    fatG: 92,
  );
  HealthSnapshot busyHealth() => HealthSnapshot(
        status: HealthStatus.ok,
        steps: 12345,
        activeKcal: 1050,
        sleepMinutes: 478,
        readAt: DateTime(2026, 11, 16, 22, 45),
      );

  Future<void> expectNoOverflow(
    WidgetTester tester, {
    required double textScale,
    bool busyDay = false,
  }) async {
    if (!realFonts) {
      markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
      return;
    }
    if (busyDay) {
      kokpit.nutrition = busyNutrition;
      health.snapshot = busyHealth();
    }
    await pumpKokpit(tester, textScale: textScale);
    final errors = await scrollThrough(tester);
    expect(errors, isEmpty);
  }

  group('taşma (RenderFlex overflow) yok', () {
    testWidgets('375x667, metin ölçeği 1.0', (tester) async {
      await expectNoOverflow(tester, textScale: 1.0);
    });

    group(
      'sağlık kartı satırı',
      () {
        testWidgets('375x667, metin ölçeği 1.0, yoğun bir gün', (tester) async {
          await expectNoOverflow(tester, textScale: 1.0, busyDay: true);
        });
        testWidgets('375x667, metin ölçeği 1.3', (tester) async {
          await expectNoOverflow(tester, textScale: 1.3);
        });
        testWidgets('375x667, metin ölçeği 1.3, yoğun bir gün', (tester) async {
          await expectNoOverflow(tester, textScale: 1.3, busyDay: true);
        });
      },
    );
  });

  group('rutin işaretleme', () {
    testWidgets('iyimser güncelleme, sunucu onayından önce görünür',
        (tester) async {
      routines.toggleGate = Completer<void>();
      final container = await pumpKokpit(tester);

      await tester.ensureVisible(find.text('Sabah tartı ve kilo kaydı'));
      await tester.pump();
      await tester.tap(find.text('Sabah tartı ve kilo kaydı'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(routines.toggles, [
        (routineId: 'r1', periodKey: today(), completed: true),
      ]);
      expect(find.text('1 / 5'), findsOneWidget);
      expect(
        container.read(todayOccurrencesProvider).value!.daily.first.completed,
        isTrue,
      );

      routines.toggleGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('ikinci dokunuş işareti kaldırır', (tester) async {
      await pumpKokpit(tester);
      await tester.ensureVisible(find.text('Ağırlık antrenmanı'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ağırlık antrenmanı'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ağırlık antrenmanı'));
      await tester.pumpAndSettle();

      expect(routines.toggles, [
        (routineId: 'r4', periodKey: today(), completed: true),
        (routineId: 'r4', periodKey: today(), completed: false),
      ]);
      expect(routines.completions, isEmpty);
      expect(find.text('0 / 5'), findsOneWidget);
    });

    testWidgets('sunucu hatasında geri alınır ve kullanıcı uyarılır',
        (tester) async {
      routines.toggleGate = Completer<void>();
      final container = await pumpKokpit(tester);

      await tester.ensureVisible(find.text('Sabah tartı ve kilo kaydı'));
      await tester.pump();
      await tester.tap(find.text('Sabah tartı ve kilo kaydı'));
      await tester.pump();
      expect(find.text('1 / 5'), findsOneWidget);

      routines.toggleGate!.completeError(Exception('ağ yok'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('0 / 5'), findsOneWidget);
      expect(
        container.read(todayOccurrencesProvider).value!.daily.first.completed,
        isFalse,
      );
      expect(find.text('Rutin güncellenemedi. Tekrar dene.'), findsOneWidget);
    });
  });

  group('yükleme hataları', () {
    testWidgets('rutinler yüklenemezse kart içinde hata ve Tekrar dene',
        (tester) async {
      routines
        ..routines = []
        ..fetchError = Exception('ağ yok');
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(750, 1334);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routinesRepositoryProvider.overrideWithValue(routines),
            tasksRepositoryProvider.overrideWithValue(tasks),
            kokpitRepositoryProvider.overrideWithValue(kokpit),
            healthRepositoryProvider.overrideWithValue(healthStore),
            settingsRepositoryProvider.overrideWithValue(settings),
            appleHealthConsentStoreProvider.overrideWithValue(
              MemoryAppleHealthConsentStore(grantAll: true),
            ),
            healthServiceProvider.overrideWithValue(health),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: KokpitScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rutinler yüklenemedi.'), findsOneWidget);

      routines.fetchError = null;
      final retry = find.descendant(
        of: find.ancestor(
          of: find.text('Rutinler yüklenemedi.'),
          matching: find.byType(Row),
        ),
        matching: find.text('Tekrar dene'),
      );
      await tester.ensureVisible(retry.first);
      await tester.pumpAndSettle();
      await tester.tap(retry.first);
      await tester.pumpAndSettle();
      expect(find.text('Rutinler yüklenemedi.'), findsNothing);
      expect(
        find.textContaining('Bugün için rutin ya da görev yok.'),
        findsOneWidget,
      );
    });
  });
}
