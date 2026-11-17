import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_widgets.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_providers.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
import '../helpers/reports_fakes.dart';
import '../helpers/test_fonts.dart';

/// Okuma ve yazmaların sırasını tutan sağlık deposu.
class _LoggingHealthRepository extends FakeHealthRepository {
  final List<String> log = [];

  @override
  Future<List<WeightEntry>> fetchWeights(DateTime from, DateTime to) {
    log.add('weights');
    return super.fetchWeights(from, to);
  }

  @override
  Future<List<WorkoutLog>> fetchWorkouts(DateTime from, DateTime to) {
    log.add('workouts');
    return super.fetchWorkouts(from, to);
  }

  @override
  Future<List<NutritionLog>> fetchNutritionLogs(DateTime day) {
    log.add('meals');
    return super.fetchNutritionLogs(day);
  }

  @override
  Future<List<DailyHealthMetric>> fetchDailyMetrics(
    DateTime from,
    DateTime to, {
    HealthSourceKind? source,
  }) {
    log.add('metrics');
    return super.fetchDailyMetrics(from, to, source: source);
  }

  @override
  Future<void> upsertHealthMetrics(
    DateTime day,
    HealthSnapshot snapshot, {
    String? ownerId,
  }) {
    log.add('upsert');
    return super.upsertHealthMetrics(day, snapshot, ownerId: ownerId);
  }

  @override
  Future<void> upsertHealthDays(
    List<HealthDayReading> days, {
    String? ownerId,
  }) {
    log.add('upsert-days');
    return super.upsertHealthDays(days, ownerId: ownerId);
  }
}

/// Uygulama arka plandan öne geldiğinde (gün değişmiş, sunucu yeni veri
/// yazmış olabilir) ekranların yeniden okunduğunu sınar. Test saati
/// değiştiremediği için gün değişimi yerine, arka plandayken deponun
/// değişmesi kullanılır: önbellek yeniden okunmuyorsa ekran eski hâlinde kalır.
void main() {
  late FakeRoutinesRepository routines;
  late CountingTasksRepository tasks;
  late _LoggingHealthRepository health;
  late FakeReportsRepository reports;
  late FakeHealthService healthKit;
  late DateTime today;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    today = AppDates.startOfDay(DateTime.now());
    routines = FakeRoutinesRepository();
    tasks = CountingTasksRepository();
    health = _LoggingHealthRepository();
    reports = FakeReportsRepository();
    healthKit = FakeHealthService(
      HealthSnapshot(
        status: HealthStatus.ok,
        steps: 8432,
        activeKcal: 512,
        sleepMinutes: 452,
        readAt: DateTime.now(),
      ),
    );

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

  /// [clock] verilirse süreç o anda başlamış gibi olur (öne gelince saat
  /// bugüne ilerler).
  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    DateTime? clock,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        notesRepositoryProvider.overrideWithValue(FakeNotesRepository()),
        healthRepositoryProvider.overrideWithValue(health),
        kokpitRepositoryProvider.overrideWithValue(FakeKokpitRepository()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        reportsRepositoryProvider.overrideWithValue(reports),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        appleHealthConsentStoreProvider.overrideWithValue(
          MemoryAppleHealthConsentStore(grantAll: true),
        ),
        healthServiceProvider.overrideWithValue(healthKit),
      ],
    );
    addTearDown(container.dispose);
    if (clock != null) {
      container.read(kokpitClockProvider.notifier).state = clock;
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('tr', 'TR'),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  /// iOS'un arka plana alıp yeniden öne getirirken gönderdiği durum sırası.
  Future<void> backgroundAndResume(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  /// Ay görünümünde [title] satırındaki durum rozeti.
  OccurrenceStatus chipOf(WidgetTester tester, String title) {
    final row = find.ancestor(
      of: find.text(title),
      matching: find.byType(InkWell),
    );
    return tester
        .widget<KokpitStatusChip>(
          find.descendant(
            of: row.first,
            matching: find.byType(KokpitStatusChip),
          ),
        )
        .status;
  }

  HealthDayReading reading(DateTime day, {int steps = 0}) => (
        day: day,
        snapshot: HealthSnapshot(
          status: HealthStatus.ok,
          steps: steps,
          readAt: DateTime.now(),
        ),
      );

  int stepsOn(Iterable<DailyHealthMetric> days, DateTime day) =>
      days.firstWhere((m) => m.day == day).steps;

  testWidgets('öne gelince Ay özeti yeniden okunur, rozetler güncellenir',
      (tester) async {
    final now = DateTime.now();
    routines.routines = [
      const Routine(
        id: 'm1',
        title: 'Maaş ödemeleri',
        scope: Routine.scopeWork,
        category: 'finans',
        frequency: RoutineFrequency.monthly,
        dayOfMonth: 15,
      ),
    ];
    await pumpShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<KokpitView>),
        matching: find.text('Ay'),
      ),
    );
    await tester.pumpAndSettle();

    // fetchInRange'i yalnızca Ay özeti çağırır.
    final before = tasks.fetchInRangeCount;
    expect(before, greaterThan(0), reason: 'Ay özeti okundu');
    expect(chipOf(tester, 'Maaş ödemeleri'), isNot(OccurrenceStatus.done));

    routines.completions.add(
      RoutineCompletionKey(
        'm1',
        DateTime(now.year, now.month),
        completedAt: now,
      ),
    );
    await backgroundAndResume(tester);

    expect(
      tasks.fetchInRangeCount,
      greaterThan(before),
      reason: 'öne gelince yeniden okundu',
    );
    expect(chipOf(tester, 'Maaş ödemeleri'), OccurrenceStatus.done);
  });

  testWidgets(
      'öne gelince Sağlık sekmesinin verisi yeniden okunur; adım grafiği '
      'HealthKit yedeklendikten sonra', (tester) async {
    await pumpShell(tester);
    expect(
      find.byKey(const ValueKey('meal-gece'), skipOffstage: false),
      findsNothing,
    );

    health.nutritionLogs = [
      NutritionLog(id: 'gece', foodName: 'Yoğurt', eatenAt: DateTime.now()),
    ];
    health.log.clear();
    await backgroundAndResume(tester);

    int reads(String name) => health.log.where((e) => e == name).length;
    expect(reads('weights'), 1, reason: 'kilo serisi');
    expect(reads('workouts'), 2, reason: 'antrenman günlüğü + haftalık plan');
    expect(reads('meals'), 1, reason: 'bugünün öğünleri');
    expect(reads('metrics'), 1, reason: '7 günlük adım');
    expect(reads('upsert'), 1, reason: 'HealthKit yeniden okundu');
    expect(reads('upsert-days'), 1, reason: 'geçmiş günler yeniden yazıldı');
    expect(
      health.log.indexOf('upsert-days'),
      lessThan(health.log.indexOf('metrics')),
      reason: 'adım grafiği, HealthKit yedeği yazıldıktan sonra okunmalı',
    );
    // Sağlık sekmesi (arka planda kurulu) yeni kaydı gösteriyor.
    expect(
      find.byKey(const ValueKey('meal-gece'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
      'açılışta ve öne gelişte HealthKit\'in biten günleri gün sonu değeriyle '
      'tamamlanır; adım grafiği yeni değeri gösterir', (tester) async {
    final yesterday = AppDates.addDays(today, -1);
    // Dün uygulama son kez sabah açılmış: tabloda 700 adım kalmış.
    health.metrics = [DailyHealthMetric(day: yesterday, steps: 700)];
    healthKit.pastDays = [reading(yesterday, steps: 11000)];

    final container = await pumpShell(tester);

    expect(stepsOn(health.metrics, yesterday), 11000);
    expect(health.upsertedDays, [yesterday]);
    expect(
      stepsOn(container.read(weekStepsProvider).requireValue, yesterday),
      11000,
      reason: 'grafik, yedekleme bittikten sonra tazelenir',
    );
    // Bugünün satırı da yazıldı ve grafikte.
    expect(
      stepsOn(container.read(weekStepsProvider).requireValue, today),
      8432,
    );

    // Arka plandayken saat/Fitbit geç eşitlendi: gün sonu değeri büyüdü.
    healthKit.pastDays = [reading(yesterday, steps: 11450)];
    await backgroundAndResume(tester);

    expect(stepsOn(health.metrics, yesterday), 11450);
    expect(
      stepsOn(container.read(weekStepsProvider).requireValue, yesterday),
      11450,
    );
  });

  testWidgets('öne gelince sunucuda oluşan günlük rapor görünür',
      (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Raporlar');
    await tester.tap(find.text('Günlük'));
    await tester.pumpAndSettle();
    expect(find.text('Bu gün için rapor henüz oluşmadı'), findsOneWidget);

    // 23:45 zamanlayıcısı raporu yazdı.
    reports.daily = [dailyReport(today)];
    await backgroundAndResume(tester);

    expect(find.text('Bu gün için rapor henüz oluşmadı'), findsNothing);
    expect(find.text('Gün özeti.'), findsOneWidget);
  });

  testWidgets(
      'öne gelince geçen haftanın raporu ve "Geçmiş haftalar" tazelenir',
      (tester) async {
    final thisWeek = AppDates.weekStart(today);
    final lastWeek = AppDates.addDays(thisWeek, -7);
    // Süreç geçen hafta başlamış; Raporlar sekmesi hiç açılmamış (sekme yine
    // de kurulur ve boş sonucu önbelleğe alır).
    final container = await pumpShell(
      tester,
      clock: lastWeek.add(const Duration(days: 5, hours: 20)),
    );
    expect(container.read(weeklyReportListProvider).requireValue, isEmpty);

    // Pazartesi 07:00 zamanlayıcısı biten haftanın raporunu yazdı.
    reports.weekly = [weeklyReport(lastWeek)];
    await backgroundAndResume(tester);
    await selectTab(tester, 'Raporlar');

    expect(
      [
        for (final r in container.read(weeklyReportListProvider).requireValue)
          r.weekStart,
      ],
      [lastWeek],
      reason: 'Geçmiş haftalar listesi yeniden okundu',
    );
    await tester.tap(find.byTooltip('Önceki hafta'));
    await tester.pumpAndSettle();
    expect(find.text('Bu hafta için rapor henüz oluşmadı'), findsNothing);
    expect(find.text('Hafta özeti.'), findsOneWidget);
  });
}
