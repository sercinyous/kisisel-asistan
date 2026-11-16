import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_screen.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_widgets.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

import 'fakes.dart';

/// Kokpit widget testlerinin ortak kurulumu: sahte depolar + ekranı pompalama.
class KokpitHarness {
  KokpitHarness()
      : routines = FakeRoutinesRepository(),
        tasks = FakeTasksRepository(),
        kokpit = FakeKokpitRepository(
          nutrition: const NutritionSummary(
            calories: 1450,
            proteinG: 132,
            carbsG: 118,
            fatG: 47,
            entryCount: 5,
          ),
        ),
        healthStore = FakeHealthRepository(),
        settings = FakeSettingsRepository(),
        health = FakeHealthService(
          HealthSnapshot(
            status: HealthStatus.ok,
            steps: 8432,
            activeKcal: 512,
            sleepMinutes: 452,
            readAt: DateTime(2026, 11, 16, 10, 30),
          ),
        ),
        notifications = FakeNotificationService();

  final FakeRoutinesRepository routines;
  final FakeTasksRepository tasks;
  final FakeKokpitRepository kokpit;
  final FakeHealthRepository healthStore;
  final FakeSettingsRepository settings;
  final FakeHealthService health;
  final FakeNotificationService notifications;

  /// Dokunuş titreşimi (HapticFeedback) platform kanalını susturur.
  void mockPlatformChannel() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  /// Ekranı kurar. [month] verilirse Ay görünümü o ayla açılır.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(375, 667),
    double textScale = 1.0,
    DateTime? month,
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
        healthServiceProvider.overrideWithValue(health),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    if (month != null) {
      container.read(kokpitViewProvider.notifier).state = KokpitView.month;
      container.read(kokpitMonthProvider.notifier).state =
          DateTime(month.year, month.month);
    }

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

  /// Gün | Ay seçicisinden görünüm değiştirir.
  Future<void> showView(WidgetTester tester, String label) async {
    final segment = find.descendant(
      of: find.byType(SegmentedButton<KokpitView>),
      matching: find.text(label),
    );
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
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

  /// [title] başlıklı satırı görünür yapıp dokunur.
  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  /// [title] başlıklı rutin/aylık iş satırındaki kutunun işaretli olup olmadığı.
  bool isChecked(WidgetTester tester, String title) {
    final row = find.ancestor(
      of: find.text(title),
      matching: find.byType(InkWell),
    );
    return tester
        .widget<KokpitCheckBox>(
          find.descendant(
            of: row.first,
            matching: find.byType(KokpitCheckBox),
          ),
        )
        .checked;
  }
}
