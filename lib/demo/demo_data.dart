import '../core/utils/date_utils.dart';
import '../features/ai_quick_add/data/quick_add_repository.dart';
import '../features/ai_quick_add/domain/parsed_entry.dart';
import '../features/ai_quick_add/domain/quick_add_mode.dart';
import '../features/health/data/health_repository.dart';
import '../features/kokpit/domain/kokpit_models.dart';
import '../features/operations/domain/note_item.dart';
import '../features/operations/domain/task_item.dart';
import '../features/routines/domain/routine.dart';
import 'demo_backend.dart';

/// Tarayıcı demosunun bellekteki örnek verisi.
class DemoData {
  DemoData._({
    required this.routines,
    required this.tasks,
    required this.notes,
    required this.health,
    required this.kokpit,
    required this.settings,
  });

  final FakeRoutinesRepository routines;
  final FakeTasksRepository tasks;
  final FakeNotesRepository notes;
  final FakeHealthRepository health;
  final FakeKokpitRepository kokpit;
  final FakeSettingsRepository settings;

  int _seq = 0;
  String nextId(String prefix) => '$prefix-demo-${_seq++}';

  factory DemoData.seed(DateTime now) {
    final today = AppDates.startOfDay(now);
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    int dayIn(int offset) => (now.day + offset).clamp(1, lastDay);
    final created = DateTime(now.year, now.month - 2, 1);

    Routine weekly(String id, String title, String scope, String category,
            int hour, int minute,
            {List<int> days = Routine.everyDay}) =>
        Routine(
          id: id,
          title: title,
          scope: scope,
          category: category,
          daysOfWeek: days,
          hour: hour,
          minute: minute,
          createdAt: created,
        );
    Routine monthly(
            String id, String title, String scope, String category, int day) =>
        Routine(
          id: id,
          title: title,
          scope: scope,
          category: category,
          frequency: RoutineFrequency.monthly,
          dayOfMonth: day,
          hour: 10,
          minute: 0,
          createdAt: created,
        );
    TaskItem task(String id, String title, String category, String priority,
            DateTime due,
            {String? assignee}) =>
        TaskItem(
          id: id,
          title: title,
          category: category,
          priority: priority,
          status: 'todo',
          assignee: assignee,
          dueAt: due,
          remindAt: due.subtract(const Duration(minutes: 30)),
        );

    return DemoData._(
      routines: FakeRoutinesRepository(
        routines: [
          weekly(
              'r1', 'Sabah tartı ve kilo kaydı', 'Kişisel', 'beslenme', 8, 0),
          weekly('r2', 'Sabah push performans kontrolü', 'Pusholder',
              'operasyon', 9, 0),
          weekly(
              'r3', 'Editör vardiya kontrolü', 'Pusholder', 'operasyon', 9, 30),
          weekly('r4', 'Öğlen gündem ve push takvimi', 'Pusholder', 'operasyon',
              13, 0),
          weekly('r5', 'Ağırlık antrenmanı', 'Kişisel', 'spor', 19, 0,
              days: const [1, 2, 4, 5]),
          weekly('r6', 'Kickboks', 'Kişisel', 'spor', 19, 30, days: const [3]),
          weekly('r7', 'Koşu', 'Kişisel', 'spor', 10, 0, days: const [6]),
          weekly('r8', 'Halı saha', 'Kişisel', 'spor', 20, 0, days: const [7]),
          weekly('r9', 'Akşam operasyon kapanışı', 'Pusholder', 'operasyon', 22,
              0),
          monthly('m1', 'Maaş ödemeleri', 'Pusholder', 'finans', dayIn(2)),
          monthly('m2', 'Aylık push performans raporu', 'Pusholder',
              'operasyon', 1),
          monthly('m3', 'Kira ve faturalar', 'Kişisel', 'finans', dayIn(-3)),
        ],
        completions: [
          RoutineCompletionKey('r1', today, completedAt: now),
          RoutineCompletionKey('r2', today, completedAt: now),
          RoutineCompletionKey('r3', today, completedAt: now),
          RoutineCompletionKey(
            'm2',
            DateTime(now.year, now.month, 1),
            completedAt: DateTime(now.year, now.month, 1, 11),
          ),
        ],
      ),
      tasks: FakeTasksRepository(tasks: [
        task('t1', 'Duhan ile vardiya planı', 'Ekip', 'high',
            today.add(const Duration(days: 1, hours: 15)),
            assignee: 'Duhan'),
        task('t2', 'Dişçi randevusu', 'Kişisel', 'medium',
            today.add(const Duration(days: 3, hours: 14))),
        task('t3', 'Push performans raporunu hazırla', 'Pusholder', 'high',
            today.add(const Duration(days: 2, hours: 12))),
        task('t4', 'Aylık gelir-gider tablosu', 'Finans', 'medium',
            today.add(const Duration(days: 6, hours: 18))),
      ]),
      notes: FakeNotesRepository(notes: [
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
      health: FakeHealthRepository(
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
          WeightEntry(
            id: 'w1',
            weightKg: 84.5,
            loggedAt: DateTime(now.year, now.month, 1, 8),
          ),
          WeightEntry(
            id: 'w2',
            weightKg: 83.6,
            loggedAt: today.add(const Duration(hours: 8)),
          ),
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
      ),
      kokpit: FakeKokpitRepository(
        nutrition: const NutritionSummary(
          calories: 1240,
          proteinG: 96,
          carbsG: 118,
          fatG: 38,
          entryCount: 3,
        ),
      ),
      settings: FakeSettingsRepository(),
    );
  }
}

/// `quick_add_entries` yerine: kalemleri bellekteki depolara uygular.
class DemoQuickAddRepository implements QuickAddRepository {
  DemoQuickAddRepository(this._data);

  final DemoData _data;

  @override
  Future<QuickAddResult> saveAll(ParsedEntry entry) async {
    final saved = <SavedTask>[];
    for (final t in entry.tasks) {
      final id = _data.nextId('task');
      _data.tasks.tasks.add(
        TaskItem(
          id: id,
          title: t.title,
          description: t.description,
          category: t.category,
          priority: t.priority,
          status: 'todo',
          assignee: t.assignee,
          dueAt: t.dueAt?.toLocal(),
          remindAt: t.remindAt?.toLocal(),
        ),
      );
      saved.add(SavedTask(id: id, title: t.title, remindAt: t.remindAt));
    }
    for (final r in entry.routines) {
      _data.routines.routines.add(
        Routine(
          id: _data.nextId('routine'),
          title: r.title,
          scope: r.scope,
          category: r.category,
          frequency: r.frequency,
          daysOfWeek: r.daysOfWeek,
          dayOfMonth: r.dayOfMonth,
          hour: r.time?.hour,
          minute: r.time?.minute,
          createdAt: DateTime.now(),
        ),
      );
    }
    for (final n in entry.notes) {
      _data.notes.notes.add(
        NoteItem(
          id: _data.nextId('note'),
          title: n.title,
          content: n.content,
          category: n.category,
          createdAt: DateTime.now(),
        ),
      );
    }
    for (final w in entry.weights) {
      _data.health.weights.add(
        WeightEntry(
          id: _data.nextId('weight'),
          weightKg: w.weightKg,
          loggedAt: w.measuredAt?.toLocal() ?? DateTime.now(),
        ),
      );
    }
    if (entry.nutrition.isNotEmpty) {
      final old = _data.kokpit.nutrition;
      double sum(double start, double Function(ParsedNutrition) pick) =>
          entry.nutrition.fold(start, (total, n) => total + pick(n));
      _data.kokpit.nutrition = NutritionSummary(
        calories: sum(old.calories, (n) => n.calories),
        proteinG: sum(old.proteinG, (n) => n.proteinG),
        carbsG: sum(old.carbsG, (n) => n.carbsG),
        fatG: sum(old.fatG, (n) => n.fatG),
        entryCount: old.entryCount + entry.nutrition.length,
      );
    }
    return QuickAddResult(
      tasks: saved,
      nutritionCount: entry.nutrition.length,
      workoutCount: entry.workouts.length,
      weightCount: entry.weights.length,
      noteCount: entry.notes.length,
      routineCount: entry.routines.length,
    );
  }
}

/// Gemini yerine geçen basit kalıp eşleştirici. Yalnızca demo içindir;
/// gerçek uygulamada metni Gemini ayrıştırır.
ParsedEntry demoParse(String input, QuickAddMode mode, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = AppDates.startOfDay(current);
  final text = input.trim();
  final s = text.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  const foods = <String, List<num>>{
    // ad: [kcal, protein, karbonhidrat, yağ] / 100 g ya da adet
    'tavuk': [165, 31, 0, 3.6],
    'pilav': [130, 2.7, 28, 0.3],
    'yulaf': [380, 13, 67, 7],
    'yoğurt': [60, 3.5, 4.7, 3.3],
    'makarna': [158, 5.8, 31, 0.9],
    'ton balığı': [130, 28, 0, 1],
  };
  const pieces = <String, List<num>>{
    'ekme': [65, 2.5, 12, 0.8],
    'yumurta': [78, 6.3, 0.6, 5.3],
    'muz': [105, 1.3, 27, 0.4],
  };
  final hasFood = [...foods.keys, ...pieces.keys].any(s.contains) ||
      RegExp(r'\byedim\b|\biçtim\b|kahvaltı').hasMatch(s);
  final hasWorkout = RegExp(r'(\d+)\s*dk').hasMatch(s) &&
      RegExp(r'ağırlık|koş|kickboks|halı saha|antrenman|yürü').hasMatch(s);
  final hasWeight = RegExp(r'\d{2,3}[.,]\d\s*kilo').hasMatch(s);
  final looksWork = RegExp(
    r'toplantı|görüş|vardiya|ödeme|maaş|rapor|fatura|randevu|dişçi|hatırlat|fikir|not:',
  ).hasMatch(s);

  if (mode == QuickAddMode.health) {
    final nutrition = <Map<String, Object?>>[];
    final meal = s.contains('sabah') || s.contains('kahvaltı')
        ? 'breakfast'
        : s.contains('akşam')
            ? 'dinner'
            : s.contains('öğle')
                ? 'lunch'
                : 'snack';
    final at = today
        .add(Duration(
          hours: switch (meal) {
            'breakfast' => 8,
            'lunch' => 13,
            'dinner' => 19,
            _ => current.hour,
          },
        ))
        .toIso8601String();
    for (final entry in foods.entries) {
      if (!s.contains(entry.key)) continue;
      final match = RegExp('(\\d+)\\s*gr?\\w*\\s+(?:\\w+\\s+)?${entry.key}')
          .firstMatch(s);
      final grams = match == null ? 150 : int.parse(match.group(1)!);
      final v = entry.value;
      nutrition.add({
        'meal_type': meal,
        'food_name': entry.key == 'tavuk'
            ? 'Tavuk göğsü'
            : entry.key[0].toUpperCase() + entry.key.substring(1),
        'quantity_text': '$grams gr',
        'calories': v[0] * grams / 100,
        'protein_g': v[1] * grams / 100,
        'carbs_g': v[2] * grams / 100,
        'fat_g': v[3] * grams / 100,
        'eaten_at': at,
      });
    }
    for (final entry in pieces.entries) {
      if (!s.contains(entry.key)) continue;
      final match = RegExp(
              '(\\d+)\\s*(?:dilim|adet|tane)?\\s*(?:\\w+\\s+){0,2}${entry.key}')
          .firstMatch(s);
      final count = match == null ? 1 : int.parse(match.group(1)!);
      final v = entry.value;
      nutrition.add({
        'meal_type': meal,
        'food_name': switch (entry.key) {
          'ekme' => 'Tam çavdar ekmeği',
          'yumurta' => 'Yumurta',
          _ => 'Muz',
        },
        'quantity_text': entry.key == 'ekme' ? '$count dilim' : '$count adet',
        'calories': v[0] * count,
        'protein_g': v[1] * count,
        'carbs_g': v[2] * count,
        'fat_g': v[3] * count,
        'eaten_at': at,
      });
    }
    final workouts = <Map<String, Object?>>[];
    if (hasWorkout) {
      final minutes = int.parse(RegExp(r'(\d+)\s*dk').firstMatch(s)!.group(1)!);
      final type = s.contains('koş')
          ? 'running'
          : s.contains('kickboks')
              ? 'kickboxing'
              : s.contains('halı saha')
                  ? 'football'
                  : 'weights';
      workouts.add({
        'workout_type': type,
        'title': switch (type) {
          'running' => 'Koşu',
          'kickboxing' => 'Kickboks',
          'football' => 'Halı saha',
          _ => 'Ağırlık antrenmanı',
        },
        'duration_min': minutes,
        'performed_at': current.toIso8601String(),
      });
    }
    final weights = <Map<String, Object?>>[];
    final weight = RegExp(r'(\d{2,3})[.,](\d)\s*kilo').firstMatch(s);
    if (weight != null) {
      weights.add({
        'weight_kg': double.parse('${weight.group(1)}.${weight.group(2)}'),
        'measured_at': current.toIso8601String(),
      });
    }
    return ParsedEntry.fromJson({
      'nutrition': nutrition,
      'workouts': workouts,
      'weights': weights,
      'other_domain': looksWork,
      'other_domain_summary':
          looksWork ? 'Metinde iş ya da randevu kaydı var.' : null,
    });
  }

  // İş modu
  final routines = <Map<String, Object?>>[];
  final tasks = <Map<String, Object?>>[];
  final notes = <Map<String, Object?>>[];
  final time = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(s);
  final hhmm = time == null
      ? null
      : '${time.group(1)!.padLeft(2, '0')}:${time.group(2)}';
  String clean(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.isEmpty
        ? 'Yeni kayıt'
        : trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  final scope = RegExp(r'maaş|push|vardiya|editör|haber|rapor|ekip').hasMatch(s)
      ? 'Pusholder'
      : 'Kişisel';
  final category = RegExp(r'maaş|ödeme|fatura|kira|bütçe').hasMatch(s)
      ? 'finans'
      : (scope == 'Pusholder' ? 'operasyon' : 'kisisel');

  final monthlyMatch = RegExp(r"her ay(?:ın)?\s*(\d{1,2})").firstMatch(s);
  final noteMatch = RegExp(r'^\s*(fikir|not)\s*:\s*(.+)$', caseSensitive: false)
      .firstMatch(text);
  const weekdays = {
    'pazartesi': 1,
    'salı': 2,
    'çarşamba': 3,
    'perşembe': 4,
    'cuma': 5,
    'cumartesi': 6,
    'pazar': 7,
  };

  if (noteMatch != null) {
    final body = noteMatch.group(2)!.trim();
    notes.add({
      'title': clean(body.length > 60 ? body.substring(0, 60) : body),
      'content': body,
      'category':
          noteMatch.group(1)!.toLowerCase() == 'fikir' ? 'Fikir' : 'Kişisel',
    });
  } else if (monthlyMatch != null) {
    final title = text
        .replaceAll(
            RegExp(r"her ay(?:ın)?\s*\d{1,2}\S*", caseSensitive: false), '')
        .replaceAll(
            RegExp(r'\b(günü|gününde|ekle|saat)\b|\d{1,2}[:.]\d{2}\S*',
                caseSensitive: false),
            '');
    routines.add({
      'title': clean(title),
      'scope': scope,
      'category': category,
      'frequency': 'monthly',
      'day_of_month': int.parse(monthlyMatch.group(1)!),
      'time_of_day': hhmm,
    });
  } else if (s.contains('her gün') ||
      weekdays.keys.any((d) => s.contains('her $d'))) {
    final days = s.contains('her gün')
        ? const [1, 2, 3, 4, 5, 6, 7]
        : [
            for (final e in weekdays.entries)
              if (s.contains('her ${e.key}')) e.value,
          ];
    final title = text.replaceAll(
      RegExp(
        r'her (gün|pazartesi|salı|çarşamba|perşembe|cumartesi|cuma|pazar)\S*|\d{1,2}[:.]\d{2}\S*|\bsaat\b',
        caseSensitive: false,
      ),
      '',
    );
    routines.add({
      'title': clean(title),
      'scope': scope,
      'category': category,
      'frequency': 'weekly',
      'days_of_week': days,
      'time_of_day': hhmm,
    });
  } else if (!(hasFood || hasWorkout || hasWeight) || looksWork) {
    var day = today;
    if (s.contains('yarın')) day = today.add(const Duration(days: 1));
    for (final e in weekdays.entries) {
      if (RegExp('\\b${e.key}\\b').hasMatch(s)) {
        final ahead = (e.value - today.weekday + 7) % 7;
        day = today.add(Duration(days: ahead == 0 ? 7 : ahead));
      }
    }
    DateTime? due;
    if (time != null) {
      due = day.add(Duration(
        hours: int.parse(time.group(1)!),
        minutes: int.parse(time.group(2)!),
      ));
    } else if (day != today) {
      due = day.add(const Duration(hours: 9));
    }
    String? assignee;
    for (final name in const ['Duhan', 'İlhan', 'Mehmet', 'Sedat']) {
      if (text.toLowerCase().contains(name.toLowerCase())) assignee = name;
    }
    final title = text.replaceAll(
      RegExp(
        r"\b(yarın|bugün|saat)\b|\d{1,2}[:.]\d{2}(?:'?\w+)?|\b(pazartesi|salı|çarşamba|perşembe|cumartesi|cuma|pazar)\b",
        caseSensitive: false,
      ),
      '',
    );
    tasks.add({
      'title': clean(title),
      'category': assignee != null || s.contains('vardiya')
          ? 'Ekip'
          : category == 'finans'
              ? 'Finans'
              : scope == 'Pusholder'
                  ? 'Pusholder'
                  : 'Kişisel',
      'priority': RegExp(r'acil|önemli|hemen').hasMatch(s) ? 'high' : 'medium',
      'assignee': assignee,
      'due_at': due?.toIso8601String(),
      'remind_at': due?.toIso8601String(),
    });
  }

  final otherDomain = hasFood || hasWorkout || hasWeight;
  return ParsedEntry.fromJson({
    'tasks': tasks,
    'routines': routines,
    'notes': notes,
    'other_domain': otherDomain,
    'other_domain_summary':
        otherDomain ? 'Metinde beslenme ya da spor kaydı var.' : null,
  });
}
