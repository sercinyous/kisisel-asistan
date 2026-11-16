// Bellekte çalışan depolar: tarayıcı demosu (lib/main_demo.dart) ve testler kullanır.
import 'dart:async';

import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/quick_add_repository.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

/// Gemini yerine geçen sahte ayrıştırıcı: [handler] ne dönerse o.
class FakeGeminiParserService implements GeminiParserService {
  FakeGeminiParserService(this.handler);

  Future<ParsedEntry> Function(String input) handler;
  final List<String> inputs = [];

  @override
  Future<ParsedEntry> parse(String input, {DateTime? now}) {
    inputs.add(input);
    return handler(input);
  }

  @override
  Future<String> generateWeeklySummary(Map<String, dynamic> metrics) async =>
      'özet';

  @override
  void dispose() {}
}

/// `quick_add_entries` RPC'sinin yerine geçer; kaydedilen girdiyi saklar.
class FakeQuickAddRepository implements QuickAddRepository {
  FakeQuickAddRepository({this.error, this.gate});

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
    );
  }
}

class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.permissionGranted = true});

  bool permissionGranted;

  /// İzin penceresinin kaç kez istendiği ([hasPermission] saymaz).
  int permissionRequests = 0;
  final List<ReminderSchedule> scheduled = [];
  final List<String> cancelled = [];
  int resyncCount = 0;

  /// Son [resync] çağrısına verilen listeler.
  List<RoutineSchedule> lastRoutines = const [];
  List<ReminderSchedule> lastReminders = const [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> scheduleReminder(ReminderSchedule reminder) async {
    scheduled.add(reminder);
  }

  @override
  Future<void> cancelReminder(String taskId) async {
    cancelled.add(taskId);
  }

  @override
  Future<void> resync({
    required List<RoutineSchedule> routines,
    required List<ReminderSchedule> reminders,
  }) async {
    resyncCount++;
    lastRoutines = routines;
    lastReminders = reminders;
  }
}

class FakeHealthService implements HealthService {
  FakeHealthService(this.snapshot);

  HealthSnapshot snapshot;

  @override
  bool get isSupported => snapshot.status != HealthStatus.unavailable;

  @override
  Future<bool> requestAccess() async => snapshot.status == HealthStatus.ok;

  @override
  Future<HealthSnapshot> readToday({DateTime? now}) async => snapshot;
}

/// Supabase'e gitmeyen Kokpit deposu (yalnızca günün beslenme özeti).
/// [health] verilirse özet o deponun öğün kayıtlarından hesaplanır; böylece
/// Sağlık sekmesinde eklenen öğün Kokpit'e de yansır (demo).
class FakeKokpitRepository implements KokpitRepository {
  FakeKokpitRepository({
    this.nutrition = const NutritionSummary(),
    this.error,
    this.health,
  });

  NutritionSummary nutrition;

  /// Doluysa okuma bu hatayı fırlatır.
  Object? error;

  FakeHealthRepository? health;

  @override
  Future<NutritionSummary> fetchNutritionFor(DateTime day) async {
    if (error != null) throw error!;
    final source = health;
    if (source == null) return nutrition;
    final logs = await source.fetchNutritionLogs(day);
    return NutritionSummary(
      calories: logs.fold<double>(0, (sum, l) => sum + l.calories),
      proteinG: logs.fold<double>(0, (sum, l) => sum + l.proteinG),
      carbsG: logs.fold<double>(0, (sum, l) => sum + l.carbsG),
      fatG: logs.fold<double>(0, (sum, l) => sum + l.fatG),
      entryCount: logs.length,
    );
  }
}

/// Bellekte çalışan rutin deposu. Yazmalar [routines] ve [completions]
/// üzerinde gerçekten uygulanır; sonraki okumalar güncel durumu görür.
class FakeRoutinesRepository implements RoutinesRepository {
  FakeRoutinesRepository({
    List<Routine>? routines,
    Iterable<RoutineCompletionKey>? completions,
  })  : routines = routines ?? [],
        completions = {...?completions};

  List<Routine> routines;
  Set<RoutineCompletionKey> completions;

  /// Doluysa okumalar bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa yazmalar (create/update/delete) bu hatayı fırlatır.
  Object? writeError;

  /// Doluysa [setCompleted] bu tamamlanana kadar bekler
  /// (hata ile tamamlanırsa çağrı da hata verir ve durum değişmez).
  Completer<void>? toggleGate;

  final List<({String routineId, DateTime periodKey, bool completed})> toggles =
      [];
  int fetchActiveCount = 0;
  int _nextId = 1;

  @override
  Future<List<Routine>> fetchActive() async {
    fetchActiveCount++;
    if (fetchError != null) throw fetchError!;
    return routines.where((r) => r.isActive).toList();
  }

  @override
  Future<List<Routine>> fetchAll() async {
    if (fetchError != null) throw fetchError!;
    return List.of(routines);
  }

  @override
  Future<Set<RoutineCompletionKey>> fetchCompletions(
    DateTime from,
    DateTime to,
  ) async {
    if (fetchError != null) throw fetchError!;
    final start = AppDates.startOfDay(from);
    final end = AppDates.startOfDay(to);
    return {
      for (final c in completions)
        if (!c.periodKey.isBefore(start) && !c.periodKey.isAfter(end)) c,
    };
  }

  @override
  Future<void> setCompleted({
    required String routineId,
    required DateTime periodKey,
    required bool completed,
  }) async {
    final key = RoutineCompletionKey(
      routineId,
      periodKey,
      completedAt: DateTime.now(),
    );
    toggles.add(
      (routineId: routineId, periodKey: key.periodKey, completed: completed),
    );
    if (toggleGate != null) await toggleGate!.future;
    completions.remove(key);
    if (completed) completions.add(key);
  }

  @override
  Future<Routine> create(Routine routine) async {
    if (writeError != null) throw writeError!;
    final created = routine.copyWith(id: 'routine-${_nextId++}');
    routines = [...routines, created];
    return created;
  }

  @override
  Future<Routine> update(Routine routine) async {
    if (writeError != null) throw writeError!;
    routines = [
      for (final r in routines) r.id == routine.id ? routine : r,
    ];
    return routine;
  }

  @override
  Future<void> delete(String id) async {
    if (writeError != null) throw writeError!;
    routines = routines.where((r) => r.id != id).toList();
    completions.removeWhere((c) => c.routineId == id);
  }
}

/// Bellekte çalışan görev deposu.
class FakeTasksRepository implements TasksRepository {
  FakeTasksRepository({List<TaskItem>? tasks}) : tasks = tasks ?? [];

  List<TaskItem> tasks;

  /// Doluysa okumalar bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa yazmalar bu hatayı fırlatır.
  Object? writeError;

  final List<String> completedIds = [];
  final List<String> reopenedIds = [];
  final List<String> deletedIds = [];
  int _nextId = 1;

  @override
  Future<List<TaskItem>> fetchOpen() async {
    if (fetchError != null) throw fetchError!;
    final open = tasks.where((t) => !t.isDone).toList();
    int rank(TaskItem t) => t.dueAt == null ? 1 : 0;
    open.sort((a, b) {
      if (rank(a) != rank(b)) return rank(a).compareTo(rank(b));
      return a.dueAt == null ? 0 : a.dueAt!.compareTo(b.dueAt!);
    });
    return open;
  }

  @override
  Future<List<TaskItem>> fetchInRange(DateTime from, DateTime to) async {
    if (fetchError != null) throw fetchError!;
    final hits = [
      for (final t in tasks)
        if (t.scheduledAt != null &&
            !t.scheduledAt!.isBefore(from) &&
            t.scheduledAt!.isBefore(to))
          t,
    ]..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return hits;
  }

  @override
  Future<List<TaskItem>> fetchUpcoming({DateTime? from, int limit = 6}) async {
    if (fetchError != null) throw fetchError!;
    final now = from ?? DateTime.now();
    bool upcoming(DateTime? t) => t != null && !t.isBefore(now);
    final hits = [
      for (final t in tasks)
        if (!t.isDone && (upcoming(t.remindAt) || upcoming(t.dueAt))) t,
    ]..sort((a, b) => a.nextTime(now)!.compareTo(b.nextTime(now)!));
    return hits.take(limit).toList();
  }

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
    if (writeError != null) throw writeError!;
    final task = TaskItem(
      id: 'task-${_nextId++}',
      title: title,
      description: description,
      category: category,
      priority: priority,
      status: 'todo',
      assignee: assignee,
      dueAt: dueAt,
      remindAt: remindAt,
      notify: notify,
    );
    tasks = [...tasks, task];
    return task;
  }

  @override
  Future<TaskItem> update(TaskItem task) async {
    if (writeError != null) throw writeError!;
    tasks = [for (final t in tasks) t.id == task.id ? task : t];
    return task;
  }

  @override
  Future<void> complete(String id) async {
    if (writeError != null) throw writeError!;
    completedIds.add(id);
    tasks = [
      for (final t in tasks)
        t.id == id
            ? t.copyWith(status: 'done', completedAt: DateTime.now())
            : t,
    ];
  }

  @override
  Future<void> reopen(String id) async {
    if (writeError != null) throw writeError!;
    reopenedIds.add(id);
    tasks = [
      for (final t in tasks)
        t.id == id ? t.copyWith(status: 'todo', clearCompletedAt: true) : t,
    ];
  }

  @override
  Future<void> delete(String id) async {
    if (writeError != null) throw writeError!;
    deletedIds.add(id);
    tasks = tasks.where((t) => t.id != id).toList();
  }
}

/// Bellekte çalışan not deposu.
class FakeNotesRepository implements NotesRepository {
  FakeNotesRepository({List<NoteItem>? notes}) : notes = notes ?? [];

  List<NoteItem> notes;

  /// Doluysa okumalar bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa yazmalar bu hatayı fırlatır.
  Object? writeError;

  final List<String> deletedIds = [];
  int _nextId = 1;

  @override
  Future<List<NoteItem>> fetchAll({String? category}) async {
    if (fetchError != null) throw fetchError!;
    final epoch = DateTime(2000);
    final hits = [
      for (final n in notes)
        if (category == null || n.category == category) n,
    ]..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return (b.updatedAt ?? epoch).compareTo(a.updatedAt ?? epoch);
      });
    return hits;
  }

  @override
  Future<NoteItem> create({
    required String title,
    String content = '',
    String category = 'Kişisel',
    bool isPinned = false,
  }) async {
    if (writeError != null) throw writeError!;
    final now = DateTime.now();
    final note = NoteItem(
      id: 'note-${_nextId++}',
      title: title,
      content: content,
      category: category,
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
    );
    notes = [...notes, note];
    return note;
  }

  @override
  Future<NoteItem> update(NoteItem note) async {
    if (writeError != null) throw writeError!;
    notes = [for (final n in notes) n.id == note.id ? note : n];
    return note;
  }

  @override
  Future<void> delete(String id) async {
    if (writeError != null) throw writeError!;
    deletedIds.add(id);
    notes = notes.where((n) => n.id != id).toList();
  }
}

/// Bellekte çalışan sağlık deposu. Yazmalar [nutritionLogs], [workouts] ve
/// [weights] üzerinde gerçekten uygulanır; sonraki okumalar güncel durumu görür.
class FakeHealthRepository implements HealthRepository {
  FakeHealthRepository({
    List<DailyHealthMetric>? metrics,
    List<WeightEntry>? weights,
    List<DailyNutritionTotal>? nutrition,
    List<NutritionLog>? nutritionLogs,
    List<WorkoutLog>? workouts,
  })  : metrics = metrics ?? [],
        weights = weights ?? [],
        nutrition = nutrition ?? [],
        nutritionLogs = nutritionLogs ?? [],
        workouts = workouts ?? [];

  List<DailyHealthMetric> metrics;
  List<WeightEntry> weights;

  /// Hazır gün toplamları (kalem kalem kaydı olmayan geçmiş günler için).
  /// [fetchNutritionTotals] bunlara [nutritionLogs]'un toplamını ekler.
  List<DailyNutritionTotal> nutrition;
  List<NutritionLog> nutritionLogs;
  List<WorkoutLog> workouts;

  /// Doluysa okumalar bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa yazmalar (öğün, antrenman, kilo) bu hatayı fırlatır.
  Object? writeError;

  /// Doluysa [upsertHealthMetrics] bu hatayı fırlatır.
  Object? upsertError;

  final List<HealthSnapshot> upsertedHealth = [];
  final List<String> deletedIds = [];
  int _nextId = 1;

  @override
  Future<List<DailyHealthMetric>> fetchDailyMetrics(
    DateTime from,
    DateTime to,
  ) async {
    if (fetchError != null) throw fetchError!;
    final start = AppDates.startOfDay(from);
    final end = AppDates.startOfDay(to);
    return [
      for (final m in metrics)
        if (!m.day.isBefore(start) && !m.day.isAfter(end)) m,
    ]..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<List<WeightEntry>> fetchWeights(DateTime from, DateTime to) async {
    if (fetchError != null) throw fetchError!;
    return [
      for (final w in weights)
        if (!w.loggedAt.isBefore(from) && w.loggedAt.isBefore(to)) w,
    ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  }

  @override
  Future<List<DailyNutritionTotal>> fetchNutritionTotals(
    DateTime from,
    DateTime to,
  ) async {
    if (fetchError != null) throw fetchError!;
    final byDay = <DateTime, DailyNutritionTotal>{
      for (final n in nutrition)
        if (!n.day.isBefore(AppDates.startOfDay(from)) && n.day.isBefore(to))
          n.day: n,
    };
    for (final log in nutritionLogs) {
      if (log.eatenAt.isBefore(from) || !log.eatenAt.isBefore(to)) continue;
      final day = AppDates.startOfDay(log.eatenAt);
      final sum = byDay[day] ?? DailyNutritionTotal(day: day);
      byDay[day] = DailyNutritionTotal(
        day: day,
        calories: sum.calories + log.calories,
        proteinG: sum.proteinG + log.proteinG,
        carbsG: sum.carbsG + log.carbsG,
        fatG: sum.fatG + log.fatG,
        entryCount: sum.entryCount + 1,
      );
    }
    return byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<List<NutritionLog>> fetchNutritionLogs(DateTime day) async {
    if (fetchError != null) throw fetchError!;
    final start = AppDates.startOfDay(day);
    final end = AppDates.endOfDay(day);
    return [
      for (final log in nutritionLogs)
        if (!log.eatenAt.isBefore(start) && log.eatenAt.isBefore(end)) log,
    ]..sort((a, b) => a.eatenAt.compareTo(b.eatenAt));
  }

  @override
  Future<NutritionLog> createNutritionLog(NutritionLog log) async {
    if (writeError != null) throw writeError!;
    final created = log.copyWith(id: 'nutrition-${_nextId++}', source: 'manual');
    nutritionLogs = [...nutritionLogs, created];
    return created;
  }

  @override
  Future<NutritionLog> updateNutritionLog(NutritionLog log) async {
    if (writeError != null) throw writeError!;
    nutritionLogs = [
      for (final l in nutritionLogs) l.id == log.id ? log : l,
    ];
    return log;
  }

  @override
  Future<void> deleteNutritionLog(String id) async {
    if (writeError != null) throw writeError!;
    deletedIds.add(id);
    nutritionLogs = nutritionLogs.where((l) => l.id != id).toList();
  }

  @override
  Future<List<WorkoutLog>> fetchWorkouts(DateTime from, DateTime to) async {
    if (fetchError != null) throw fetchError!;
    return [
      for (final w in workouts)
        if (!w.loggedAt.isBefore(from) && w.loggedAt.isBefore(to)) w,
    ]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  @override
  Future<WorkoutLog> createWorkout(WorkoutLog workout) async {
    if (writeError != null) throw writeError!;
    final created =
        workout.copyWith(id: 'workout-${_nextId++}', source: 'manual');
    workouts = [...workouts, created];
    return created;
  }

  @override
  Future<WorkoutLog> updateWorkout(WorkoutLog workout) async {
    if (writeError != null) throw writeError!;
    workouts = [for (final w in workouts) w.id == workout.id ? workout : w];
    return workout;
  }

  @override
  Future<void> deleteWorkout(String id) async {
    if (writeError != null) throw writeError!;
    deletedIds.add(id);
    workouts = workouts.where((w) => w.id != id).toList();
  }

  @override
  Future<WeightEntry> addWeight(double weightKg, {DateTime? at}) async {
    if (writeError != null) throw writeError!;
    final entry = WeightEntry(
      id: 'weight-${_nextId++}',
      weightKg: weightKg,
      loggedAt: at ?? DateTime.now(),
    );
    weights = [...weights, entry];
    return entry;
  }

  @override
  Future<void> deleteWeight(String id) async {
    if (writeError != null) throw writeError!;
    deletedIds.add(id);
    weights = weights.where((w) => w.id != id).toList();
  }

  @override
  Future<void> upsertHealthMetrics(
      DateTime day, HealthSnapshot snapshot) async {
    if (upsertError != null) throw upsertError!;
    upsertedHealth.add(snapshot);
  }
}

/// Bellekte çalışan ayar deposu. [settings] boşsa ilk okuma varsayılanı
/// "oluşturur" (gerçek deponun satır yokken yaptığı gibi).
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.settings});

  UserSettings? settings;

  /// Doluysa [fetch] bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa [save] bu hatayı fırlatır.
  Object? saveError;

  /// Doluysa [save] bu tamamlanana kadar bekler.
  Completer<void>? saveGate;

  final List<UserSettings> saved = [];
  int fetchCount = 0;

  @override
  Future<UserSettings> fetch() async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    return settings ??= const UserSettings.defaults();
  }

  @override
  Future<UserSettings> save(UserSettings value) async {
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) throw saveError!;
    saved.add(value);
    settings = value;
    return value;
  }
}

/// Bellekte çalışan rapor deposu. Gerçekte raporları sunucu üretir; burada
/// [regenerate], [weeklyBuilder] / [dailyBuilder] verilmişse onların ürettiği
/// raporu listeye yazar (yoksa yalnızca çağrıyı kaydeder).
class FakeReportsRepository implements ReportsRepository {
  FakeReportsRepository({
    List<WeeklyReport>? weekly,
    List<DailyReport>? daily,
    this.weeklyBuilder,
    this.dailyBuilder,
    this.regenerateDelay = Duration.zero,
  })  : weekly = weekly ?? [],
        daily = daily ?? [];

  List<WeeklyReport> weekly;
  List<DailyReport> daily;

  /// [regenerate] sırasında haftanın (Pazartesi) raporunu üretir.
  WeeklyReport Function(DateTime weekStart)? weeklyBuilder;

  /// [regenerate] sırasında günün raporunu üretir.
  DailyReport Function(DateTime day)? dailyBuilder;

  /// [regenerate] bu kadar bekler; demoda butonun meşgul hâli görünsün diye.
  final Duration regenerateDelay;

  /// Doluysa okumalar bu hatayı fırlatır.
  Object? fetchError;

  /// Doluysa [regenerate] bu hatayı fırlatır (rapor değişmez).
  Object? regenerateError;

  /// Doluysa [regenerate] bu tamamlanana kadar bekler.
  Completer<void>? regenerateGate;

  /// [regenerate] çağrıları; `date` haftalıkta Pazartesi'ye indirgenmiştir.
  final List<({ReportKind kind, DateTime date})> regenerated = [];

  @override
  Future<WeeklyReport?> fetchWeekly(DateTime weekStart) async {
    if (fetchError != null) throw fetchError!;
    final monday = AppDates.weekStart(weekStart);
    for (final report in weekly) {
      if (report.weekStart == monday) return report;
    }
    return null;
  }

  @override
  Future<List<WeeklyReport>> fetchWeeklyList({int limit = 12}) async {
    if (fetchError != null) throw fetchError!;
    final sorted = [...weekly]
      ..sort((a, b) => b.weekStart.compareTo(a.weekStart));
    return sorted.take(limit).toList();
  }

  @override
  Future<DailyReport?> fetchDaily(DateTime day) async {
    if (fetchError != null) throw fetchError!;
    final target = AppDates.startOfDay(day);
    for (final report in daily) {
      if (report.reportDate == target) return report;
    }
    return null;
  }

  @override
  Future<List<DailyReport>> fetchDailyList(DateTime from, DateTime to) async {
    if (fetchError != null) throw fetchError!;
    final start = AppDates.startOfDay(from);
    final end = AppDates.startOfDay(to);
    return [
      for (final report in daily)
        if (!report.reportDate.isBefore(start) &&
            !report.reportDate.isAfter(end))
          report,
    ]..sort((a, b) => b.reportDate.compareTo(a.reportDate));
  }

  @override
  Future<void> regenerate({
    required ReportKind kind,
    required DateTime date,
  }) async {
    final target = kind == ReportKind.weekly
        ? AppDates.weekStart(date)
        : AppDates.startOfDay(date);
    regenerated.add((kind: kind, date: target));
    if (regenerateGate != null) await regenerateGate!.future;
    if (regenerateDelay > Duration.zero) {
      await Future<void>.delayed(regenerateDelay);
    }
    if (regenerateError != null) throw regenerateError!;
    switch (kind) {
      case ReportKind.weekly:
        final build = weeklyBuilder;
        if (build == null) return;
        weekly = [
          for (final r in weekly)
            if (r.weekStart != target) r,
          build(target),
        ];
      case ReportKind.daily:
        final build = dailyBuilder;
        if (build == null) return;
        daily = [
          for (final r in daily)
            if (r.reportDate != target) r,
          build(target),
        ];
    }
  }
}
