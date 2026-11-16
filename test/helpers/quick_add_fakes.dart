import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
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

  final List<ParsedEntry> saved = [];

  @override
  Future<QuickAddResult> saveAll(ParsedEntry entry) async {
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    saved.add(entry);
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
  int fetchUpcomingCount = 0;
  int fetchInRangeCount = 0;

  @override
  Future<List<TaskItem>> fetchUpcoming({DateTime? from, int limit = 6}) {
    fetchUpcomingCount++;
    return super.fetchUpcoming(from: from, limit: limit);
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
  })  : work = FakeGeminiParserService(work ?? _empty),
        health = FakeGeminiParserService(health ?? _empty);

  static Future<ParsedEntry> _empty(String _) async => const ParsedEntry();

  final FakeGeminiParserService work;
  final FakeGeminiParserService health;
  final RecordingQuickAddRepository repository = RecordingQuickAddRepository();
  final FakeNotificationService notifications = FakeNotificationService();
  final FakeSettingsRepository settings = FakeSettingsRepository();
  final FakeRoutinesRepository routines = FakeRoutinesRepository();
  final CountingTasksRepository tasks = CountingTasksRepository();
  final FakeNotesRepository notes = FakeNotesRepository();
  final FakeHealthRepository healthData = FakeHealthRepository();
  final CountingKokpitRepository kokpit = CountingKokpitRepository();

  FakeGeminiParserService parserFor(QuickAddMode mode) =>
      mode == QuickAddMode.work ? work : health;

  List<Override> get overrides => [
        geminiParserServiceProvider.overrideWith((ref, mode) => parserFor(mode)),
        quickAddRepositoryProvider.overrideWithValue(repository),
        notificationServiceProvider.overrideWithValue(notifications),
        settingsRepositoryProvider.overrideWithValue(settings),
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        notesRepositoryProvider.overrideWithValue(notes),
        healthRepositoryProvider.overrideWithValue(healthData),
        kokpitRepositoryProvider.overrideWithValue(kokpit),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(
            const HealthSnapshot(status: HealthStatus.unavailable),
          ),
        ),
      ];
}
