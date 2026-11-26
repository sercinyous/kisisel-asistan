import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/health_source.dart'
    show MemoryAppleHealthConsentStore, appleHealthConsentStoreProvider;
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/quick_add_repository.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

import 'fakes.dart';

/// `quick_add_entries` yerine geçer; gerçek RPC gibi `routine_count` da döner.
class RecordingQuickAddRepository implements QuickAddRepository {
  /// Doluysa [saveAll] bu hatayı fırlatır.
  Object? error;

  /// Doluysa [saveAll] bu tamamlanana kadar bekler.
  Completer<void>? gate;

  /// `true`: RPC kalemleri yazılır, hatırlatıcılar yazılamaz (bir kez).
  bool failReminders = false;

  final List<ParsedEntry> saved = [];

  /// Her denemenin kayıt anahtarı (hatalı denemeler dahil).
  final List<String?> opKeys = [];

  @override
  Future<QuickAddResult> saveAll(ParsedEntry entry, {String? opKey}) async {
    opKeys.add(opKey);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    if (failReminders && entry.reminders.isNotEmpty) {
      failReminders = false;
      final rpcOnly = ParsedEntry(
        tasks: entry.tasks,
        nutrition: entry.nutrition,
        workouts: entry.workouts,
        weights: entry.weights,
        notes: entry.notes,
        routines: entry.routines,
      );
      saved.add(rpcOnly);
      throw QuickAddPartialSaveException(
        _resultFor(rpcOnly),
        StateError('reminders insert'),
      );
    }
    saved.add(entry);
    return _resultFor(entry);
  }

  QuickAddResult _resultFor(ParsedEntry entry) {
    return QuickAddResult(
      tasks: [
        for (final (i, t) in entry.tasks.indexed)
          SavedTask(
            id: 'task-$i',
            title: t.title,
            dueAt: t.dueAt,
            remindAt: t.remindAt,
          ),
      ],
      nutritionCount: entry.nutrition.length,
      workoutCount: entry.workouts.length,
      weightCount: entry.weights.length,
      noteCount: entry.notes.length,
      routineCount: entry.routines.length,
      reminderCount: entry.reminders.length,
    );
  }
}

/// Okuma sayısını tutan beslenme deposu (tazelemenin gerçekleştiğini görmek için).
class CountingKokpitRepository implements KokpitRepository {
  int fetchCount = 0;

  @override
  Future<NutritionSummary> fetchNutritionFor(DateTime day) async {
    fetchCount++;
    return const NutritionSummary();
  }
}

/// Okuma sayılarını tutan görev deposu.
class CountingTasksRepository extends FakeTasksRepository {
  int fetchKokpitDayCount = 0;
  int fetchInRangeCount = 0;

  @override
  Future<List<TaskItem>> fetchKokpitDay(DateTime now, {int lookbackDays = 30}) {
    fetchKokpitDayCount++;
    return super.fetchKokpitDay(now, lookbackDays: lookbackDays);
  }

  @override
  Future<List<TaskItem>> fetchInRange(DateTime from, DateTime to) {
    fetchInRangeCount++;
    return super.fetchInRange(from, to);
  }
}

/// AI giriş akışının dokunduğu tüm bağımlılıkların sahteleri.
class QuickAddHarness {
  QuickAddHarness({
    Future<ParsedEntry> Function(String input)? work,
    Future<ParsedEntry> Function(String input)? health,
    FakeNotificationService? notifications,
  })  : notifications = notifications ?? FakeNotificationService(),
        work = FakeGeminiParserService(work ?? _empty),
        health = FakeGeminiParserService(health ?? _empty);

  static Future<ParsedEntry> _empty(String _) async => const ParsedEntry();

  final FakeGeminiParserService work;
  final FakeGeminiParserService health;
  final RecordingQuickAddRepository repository = RecordingQuickAddRepository();
  final FakeNotificationService notifications;
  final FakeSettingsRepository settings = FakeSettingsRepository();
  final FakeRoutinesRepository routines = FakeRoutinesRepository();
  final CountingTasksRepository tasks = CountingTasksRepository();
  final FakeNotesRepository notes = FakeNotesRepository();
  final FakeHealthRepository healthData = FakeHealthRepository();
  final CountingKokpitRepository kokpit = CountingKokpitRepository();

  FakeGeminiParserService parserFor(QuickAddMode mode) =>
      mode == QuickAddMode.work ? work : health;

  List<Override> get overrides => [
        geminiParserServiceProvider
            .overrideWith((ref, mode) => parserFor(mode)),
        quickAddRepositoryProvider.overrideWithValue(repository),
        notificationServiceProvider.overrideWithValue(notifications),
        settingsRepositoryProvider.overrideWithValue(settings),
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        notesRepositoryProvider.overrideWithValue(notes),
        healthRepositoryProvider.overrideWithValue(healthData),
        kokpitRepositoryProvider.overrideWithValue(kokpit),
        appleHealthConsentStoreProvider.overrideWithValue(
          MemoryAppleHealthConsentStore(grantAll: true),
        ),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(
            const HealthSnapshot(status: HealthStatus.unavailable),
          ),
        ),
      ];
}
