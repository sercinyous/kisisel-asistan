import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_widgets.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
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
    DateTime to,
  ) {
    log.add('metrics');
    return super.fetchDailyMetrics(from, to);
  }

  @override
  Future<void> upsertHealthMetrics(DateTime day, HealthSnapshot snapshot) {
    log.add('upsert');
    return super.upsertHealthMetrics(day, snapshot);
  }
}

/// Uygulama arka plandan öne geldiğinde (gün değişmiş olabilir) "bugün"e göre
/// hesaplanan verinin yeniden okunduğunu sınar. Test saati değiştiremediği
/// için gün değişimi yerine, arka plandayken deponun değişmesi kullanılır:
/// önbellek yeniden okunmuyorsa ekran eski hâlinde kalır.
void main() {
  late FakeRoutinesRepository routines;
  late CountingTasksRepository tasks;
  late _LoggingHealthRepository health;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    routines = FakeRoutinesRepository();
    tasks = CountingTasksRepository();
    health = _LoggingHealthRepository();

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

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routinesRepositoryProvider.overrideWithValue(routines),
          tasksRepositoryProvider.overrideWithValue(tasks),
          notesRepositoryProvider.overrideWithValue(FakeNotesRepository()),
          healthRepositoryProvider.overrideWithValue(health),
          kokpitRepositoryProvider.overrideWithValue(FakeKokpitRepository()),
          settingsRepositoryProvider
              .overrideWithValue(FakeSettingsRepository()),
          reportsRepositoryProvider.overrideWithValue(FakeReportsRepository()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          healthServiceProvider.overrideWithValue(
            FakeHealthService(
              HealthSnapshot(
                status: HealthStatus.ok,
                steps: 8432,
                activeKcal: 512,
                sleepMinutes: 452,
                readAt: DateTime.now(),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('tr', 'TR'),
          home: const HomeShell(),
        ),
      ),
    );
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
    expect(tasks.fetchInRangeCount, 1, reason: 'Ay özeti bir kez okundu');
    expect(chipOf(tester, 'Maaş ödemeleri'), isNot(OccurrenceStatus.done));

    routines.completions.add(
      RoutineCompletionKey(
        'm1',
        DateTime(now.year, now.month),
        completedAt: now,
      ),
    );
    await backgroundAndResume(tester);

    expect(tasks.fetchInRangeCount, 2, reason: 'öne gelince yeniden okundu');
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
    expect(
      health.log.indexOf('upsert'),
      lessThan(health.log.indexOf('metrics')),
      reason: 'adım grafiği, bugünün satırı yazıldıktan sonra okunmalı',
    );
    // Sağlık sekmesi (arka planda kurulu) yeni kaydı gösteriyor.
    expect(
      find.byKey(const ValueKey('meal-gece'), skipOffstage: false),
      findsOneWidget,
    );
  });
}
