/// Gemini'nin doğal dil girdisinden ürettiği yapılandırılmış sonuç.
///
/// `fromJson` model çıktısına karşı toleranslıdır (eksik/yanlış tipli
/// alanlar güvenli varsayılanlara düşer); `toJson` ise Supabase'deki
/// `quick_add_entries` RPC'sinin beklediği sütun adlarını üretir.
library;

import '../../../core/config/app_targets.dart';
import '../../reminders/domain/reminder.dart';
import '../../routines/domain/routine.dart';
import '../../settings/domain/user_settings.dart';
import 'quick_add_mode.dart';

DateTime? _parseDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
}

double _parseDouble(Object? value) {
  double result = 0;
  if (value is num) {
    result = value.toDouble();
  } else if (value is String) {
    result = double.tryParse(value.replaceAll(',', '.')) ?? 0;
  }
  return result.isFinite ? result : 0;
}

/// Kod noktasına göre kırpar (Postgres char_length ile aynı sayım;
/// emoji gibi çiftleri ortadan bölmez).
String _truncate(String text, int max) => text.runes.length <= max
    ? text
    : String.fromCharCodes(text.runes.take(max));

/// Yalnızca tarih verilmiş (saat 00:00) bir görev için anlamlı bir saat:
/// o gün 09:00; bugünse ve 09:00 geçtiyse şu andan bir saat sonrası.
DateTime _defaultTimeForDateOnly(DateTime due) {
  final local = due.toLocal();
  if (local.hour != 0 || local.minute != 0 || local.second != 0) return due;
  var fixed = DateTime(local.year, local.month, local.day, 9);
  final now = DateTime.now();
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (isToday && !fixed.isAfter(now)) {
    fixed = now.add(const Duration(hours: 1));
  }
  return fixed;
}

int? _parseInt(Object? value) {
  if (value is num) return value.isFinite ? value.round() : null;
  if (value is String) return int.tryParse(value);
  return null;
}

String? _parseText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Türkçe i/ı ayrımını yok sayan karşılaştırma anahtarı
/// ("TOPLANTI", "toplantı", "Kişisel", "KİŞİSEL" eşleşsin).
String _foldTr(String text) => text
    .replaceAll('İ', 'i')
    .replaceAll('I', 'i')
    .replaceAll('ı', 'i')
    .toLowerCase();

/// Eski komut ya da yanıtlardaki 'Pusholder' (büyük/küçük harf fark etmez)
/// 'İş'e eşlenir (geçiş uyumu); diğer değerler olduğu gibi döner.
Object? _legacyWork(Object? value) {
  final text = _parseText(value);
  if (text != null &&
      _foldTr(text) == _foldTr(AppTargets.legacyWorkCategory)) {
    return AppTargets.workCategory;
  }
  return value;
}

String _oneOf(Object? value, List<String> allowed, String fallback) {
  final text = _parseText(value);
  if (text == null) return fallback;
  final wanted = _foldTr(text);
  for (final option in allowed) {
    if (_foldTr(option) == wanted) return option;
  }
  return fallback;
}

List<T> _parseList<T>(Object? value, T? Function(Map<String, dynamic>) map) {
  if (value is! List) return <T>[];
  final result = <T>[];
  for (final item in value) {
    if (item is Map) {
      final parsed = map(Map<String, dynamic>.from(item));
      if (parsed != null) result.add(parsed);
    }
  }
  return result;
}

String? _utcIso(DateTime? value) => value?.toUtc().toIso8601String();

/// Model haftanın günlerini ISO dışı da yazabilir (Pazar = 0, tekrar, sırasız);
/// tablo kısıtı 1..7 ister. Geçerli gün kalmazsa "her gün" varsayılır.
List<int> _parseWeekdays(Object? value) {
  if (value is! List) return Routine.everyDay;
  final days = <int>{};
  for (final item in value) {
    final number = _parseInt(item);
    if (number == null) continue;
    final iso = number == 0 ? 7 : number;
    if (iso >= 1 && iso <= 7) days.add(iso);
  }
  if (days.isEmpty) return Routine.everyDay;
  return days.toList()..sort();
}

final RegExp _clockPattern = RegExp(r'^(\d{1,2})[:.](\d{2})(?::\d{2})?$');

/// "HH:MM" (ya da "H:MM", "HH.MM", "HH:MM:SS"); geçersiz saat `null`.
TimeOfDayValue? _parseClock(Object? value) {
  final text = _parseText(value);
  if (text == null) return null;
  final match = _clockPattern.firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return TimeOfDayValue(hour, minute);
}

class ParsedTask {
  const ParsedTask({
    required this.title,
    required this.category,
    required this.priority,
    this.description,
    this.assignee,
    this.dueAt,
    this.remindAt,
  });

  static const categories = AppTargets.taskCategories;
  static const priorities = ['low', 'medium', 'high'];

  final String title;
  final String? description;
  final String category;
  final String priority;
  final String? assignee;
  final DateTime? dueAt;
  final DateTime? remindAt;

  /// [allowed]: kullanıcının açık kategorileri; model başka bir değer
  /// yazarsa 'Kişisel' (açıksa) ya da ilk açık kategori seçilir.
  static ParsedTask? fromJson(
    Map<String, dynamic> json, {
    List<String> allowed = categories,
  }) {
    final options = allowed.isEmpty ? categories : allowed;
    final fallback = options.contains('Kişisel') ? 'Kişisel' : options.first;
    final title = _parseText(json['title']);
    if (title == null) return null;
    var dueAt = _parseDate(json['due_at']);
    var explicitRemind = _parseDate(json['remind_at']);
    // Terminle aynı an, modelin termini yinelemesidir; kullanıcı ayrı bir
    // hatırlatma zamanı söylememiştir. Boş bırakılır ki ayarlardaki
    // "randevu kaç dk önce" süresi uygulansın.
    if (dueAt != null &&
        explicitRemind != null &&
        explicitRemind.isAtSameMomentAs(dueAt)) {
      explicitRemind = null;
    }
    if (dueAt != null && explicitRemind == null) {
      dueAt = _defaultTimeForDateOnly(dueAt);
    }
    return ParsedTask(
      title: _truncate(title, 300),
      description: _parseText(json['description']),
      category: _oneOf(_legacyWork(json['category']), options, fallback),
      priority: _oneOf(json['priority'], priorities, 'medium'),
      assignee: _parseText(json['assignee']),
      dueAt: dueAt,
      remindAt: explicitRemind,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'category': category,
        'priority': priority,
        'assignee': assignee,
        'due_at': _utcIso(dueAt),
        'remind_at': _utcIso(remindAt),
      };
}

class ParsedNutrition {
  const ParsedNutrition({
    required this.mealType,
    required this.foodName,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.quantityText,
    this.eatenAt,
  });

  static const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

  final String mealType;
  final String foodName;
  final String? quantityText;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final DateTime? eatenAt;

  String get mealLabel => switch (mealType) {
        'breakfast' => 'Kahvaltı',
        'lunch' => 'Öğle',
        'dinner' => 'Akşam',
        _ => 'Ara öğün',
      };

  static ParsedNutrition? fromJson(Map<String, dynamic> json) {
    final name = _parseText(json['food_name']);
    if (name == null) return null;
    return ParsedNutrition(
      mealType: _oneOf(json['meal_type'], mealTypes, 'snack'),
      foodName: _truncate(name, 200),
      quantityText: _parseText(json['quantity_text']),
      calories: _parseDouble(json['calories']).clamp(0, 5000).toDouble(),
      proteinG: _parseDouble(json['protein_g']).clamp(0, 500).toDouble(),
      carbsG: _parseDouble(json['carbs_g']).clamp(0, 800).toDouble(),
      fatG: _parseDouble(json['fat_g']).clamp(0, 400).toDouble(),
      eatenAt: _parseDate(json['eaten_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'meal_type': mealType,
        'food_name': foodName,
        'quantity_text': quantityText,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'eaten_at': _utcIso(eatenAt),
      };
}

class ParsedWorkout {
  const ParsedWorkout({
    required this.workoutType,
    required this.title,
    this.durationMin,
    this.distanceKm,
    this.caloriesBurned,
    this.notes,
    this.performedAt,
  });

  static const workoutTypes = [
    'weights',
    'kickboxing',
    'running',
    'football',
    'other',
  ];

  final String workoutType;
  final String title;
  final int? durationMin;
  final double? distanceKm;
  final int? caloriesBurned;
  final String? notes;
  final DateTime? performedAt;

  String get typeLabel => switch (workoutType) {
        'weights' => 'Ağırlık',
        'kickboxing' => 'Kickboks',
        'running' => 'Koşu',
        'football' => 'Halı saha',
        _ => 'Antrenman',
      };

  static ParsedWorkout? fromJson(Map<String, dynamic> json) {
    final type = _oneOf(json['workout_type'], workoutTypes, 'other');
    final duration = _parseInt(json['duration_min']);
    final distance = _parseDouble(json['distance_km']);
    final kcal = _parseInt(json['calories_burned']);
    final ParsedWorkout workout = ParsedWorkout(
      workoutType: type,
      title: _truncate(_parseText(json['title']) ?? 'Antrenman', 200),
      durationMin:
          duration != null && duration >= 1 && duration <= 600 ? duration : null,
      distanceKm: distance > 0 && distance <= 1000 ? distance : null,
      caloriesBurned: kcal != null && kcal >= 0 && kcal <= 20000 ? kcal : null,
      notes: _parseText(json['notes']),
      performedAt: _parseDate(json['performed_at']),
    );
    return workout;
  }

  Map<String, dynamic> toJson() => {
        'workout_type': workoutType,
        'title': title,
        'duration_min': durationMin,
        'distance_km': distanceKm,
        'calories_burned':
            caloriesBurned != null && caloriesBurned! >= 0 ? caloriesBurned : null,
        'notes': notes,
        'performed_at': _utcIso(performedAt),
      };
}

class ParsedWeight {
  const ParsedWeight({required this.weightKg, this.measuredAt});

  final double weightKg;
  final DateTime? measuredAt;

  static ParsedWeight? fromJson(Map<String, dynamic> json) {
    final kg = _parseDouble(json['weight_kg']);
    if (kg < 30 || kg > 250) return null;
    return ParsedWeight(
      weightKg: kg,
      measuredAt: _parseDate(json['measured_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'weight_kg': weightKg,
        'measured_at': _utcIso(measuredAt),
      };
}

class ParsedNote {
  const ParsedNote({
    required this.title,
    required this.content,
    required this.category,
  });

  static const categories = AppTargets.noteCategories;

  final String title;
  final String content;
  final String category;

  static ParsedNote? fromJson(Map<String, dynamic> json) {
    final content = _parseText(json['content']);
    final title = _parseText(json['title']) ?? content;
    if (title == null) return null;
    return ParsedNote(
      title: _truncate(title, 200),
      content: content ?? '',
      category: _oneOf(_legacyWork(json['category']), categories, 'Kişisel'),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'category': category,
      };
}

/// Tekrarlayan iş ("her ayın 15'i maaş ödemesi", "her pazartesi 11:00 toplantı").
class ParsedRoutine {
  const ParsedRoutine({
    required this.title,
    required this.scope,
    required this.category,
    required this.frequency,
    this.daysOfWeek = Routine.everyDay,
    this.dayOfMonth,
    this.time,
  });

  static const List<String> _frequencies = ['weekly', 'monthly', 'daily'];
  static const List<String> _dayLabels = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  final String title;
  final String scope;
  final String category;
  final RoutineFrequency frequency;

  /// ISO gün numaraları, sıralı ve tekrarsız. Aylıkta kullanılmaz.
  final List<int> daysOfWeek;

  /// 1..31; yalnızca aylıkta dolu.
  final int? dayOfMonth;
  final TimeOfDayValue? time;

  bool get isMonthly => frequency == RoutineFrequency.monthly;

  String get categoryLabel => switch (category) {
        'operasyon' => 'Operasyon',
        'spor' => 'Spor',
        'beslenme' => 'Beslenme',
        'finans' => 'Finans',
        _ => 'Kişisel',
      };

  /// Önizlemede gösterilen tekrar özeti ("Her ayın 15. günü · 10:00").
  String get scheduleLabel {
    final String days;
    if (isMonthly) {
      days = 'Her ayın $dayOfMonth. günü';
    } else if (daysOfWeek.length == 7) {
      days = 'Her gün';
    } else if (daysOfWeek.join() == '12345') {
      days = 'Hafta içi her gün';
    } else if (daysOfWeek.join() == '67') {
      days = 'Hafta sonu';
    } else {
      days = 'Her ${daysOfWeek.map((d) => _dayLabels[d - 1]).join(', ')}';
    }
    return time == null ? days : '$days · ${time!.format()}';
  }

  static ParsedRoutine? fromJson(Map<String, dynamic> json) {
    final title = _parseText(json['title']);
    if (title == null) return null;

    final rawDay = _parseInt(json['day_of_month']);
    final rawDays = json['days_of_week'];
    final hasWeekdays = rawDays is List && rawDays.isNotEmpty;
    // Sıklık yazılmamışsa eldeki alandan çıkarılır: yalnızca ayın günü
    // verilmişse iş aylıktır.
    final frequency = _oneOf(
      json['frequency'],
      _frequencies,
      rawDay != null && !hasWeekdays ? 'monthly' : 'weekly',
    );

    final monthly = frequency == 'monthly';
    // Günü bilinmeyen aylık iş kaydedilemez (tablo kısıtı); gün uydurulmaz.
    if (monthly && rawDay == null) return null;

    return ParsedRoutine(
      title: _truncate(title, 200),
      scope: _oneOf(
        _legacyWork(json['scope']),
        Routine.scopes,
        Routine.scopePersonal,
      ),
      category: _oneOf(json['category'], Routine.categories, 'kisisel'),
      frequency: monthly ? RoutineFrequency.monthly : RoutineFrequency.weekly,
      daysOfWeek: monthly || frequency == 'daily'
          ? Routine.everyDay
          : _parseWeekdays(rawDays),
      dayOfMonth: monthly ? rawDay!.clamp(1, 31) : null,
      time: _parseClock(json['time_of_day']),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'scope': scope,
        'category': category,
        'frequency': frequency.dbValue,
        'days_of_week': isMonthly ? Routine.everyDay : daysOfWeek,
        'day_of_month': isMonthly ? dayOfMonth : null,
        'time_of_day': time?.format(),
      };
}

/// Kişisel hatırlatıcı ("her gün 22:00'de su içmeyi hatırlat").
/// `quick_add_entries` RPC'sine gitmez; `reminders` tablosuna ayrıca yazılır.
class ParsedReminder {
  const ParsedReminder({
    required this.title,
    required this.time,
    required this.repeat,
    this.onDate,
    this.daysMask = 0,
  });

  static const List<String> repeats = ['once', 'daily', 'weekdays', 'custom'];

  final String title;
  final TimeOfDayValue time;
  final ReminderRepeat repeat;
  final DateTime? onDate;
  final int daysMask;

  ReminderDraft toDraft() => ReminderDraft(
        title: title,
        time: time,
        repeat: repeat,
        onDate: onDate,
        daysMask: daysMask,
      );

  /// Önizleme özeti ("Her gün · 22:00").
  String get scheduleLabel => Reminder(
        id: '',
        userId: '',
        title: title,
        time: time,
        repeat: repeat,
        onDate: onDate,
        daysMask: daysMask,
      ).scheduleLabel;

  /// Saati olmayan hatırlatıcı kaydedilemez (`null`). Gün listesi her gün ya
  /// da hafta içine denk gelirse o tekrar seçilir; tarihsiz "once" bugün
  /// (saat geçtiyse yarın) olur.
  static ParsedReminder? fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final title = _parseText(json['title']);
    final time = _parseClock(json['time_of_day']);
    if (title == null || time == null) return null;
    var repeat = ReminderRepeat.fromDb(
      _oneOf(json['repeat'], repeats, 'daily'),
    );
    var mask = 0;
    DateTime? onDate;
    if (repeat == ReminderRepeat.custom) {
      final rawDays = json['days_of_week'];
      mask = rawDays is List && rawDays.isNotEmpty
          ? ReminderDays.maskOf(_parseWeekdays(rawDays))
          : 0x7F;
      if (mask == 0x7F) {
        repeat = ReminderRepeat.daily;
        mask = 0;
      } else if (mask == 0x1F) {
        repeat = ReminderRepeat.weekdays;
        mask = 0;
      }
    } else if (repeat == ReminderRepeat.once) {
      final date = _parseDate(json['date']);
      if (date != null) {
        onDate = reminderDay(date);
      } else {
        final at = now ?? DateTime.now();
        final todayAt =
            DateTime(at.year, at.month, at.day, time.hour, time.minute);
        onDate = reminderDay(
          todayAt.isAfter(at) ? at : at.add(const Duration(days: 1)),
        );
      }
    }
    return ParsedReminder(
      title: _truncate(title, ReminderDraft.maxTitleLength),
      time: time,
      repeat: repeat,
      onDate: onDate,
      daysMask: mask,
    );
  }
}

enum ParsedKind { task, nutrition, workout, weight, note, routine, reminder }

class ParsedEntry {
  const ParsedEntry({
    this.tasks = const [],
    this.nutrition = const [],
    this.workouts = const [],
    this.weights = const [],
    this.notes = const [],
    this.routines = const [],
    this.reminders = const [],
    this.otherDomain = false,
    this.otherDomainSummary,
  });

  final List<ParsedTask> tasks;
  final List<ParsedNutrition> nutrition;
  final List<ParsedWorkout> workouts;
  final List<ParsedWeight> weights;
  final List<ParsedNote> notes;
  final List<ParsedRoutine> routines;

  /// Kişisel hatırlatıcılar; RPC yüküne ([toJson]) girmez.
  final List<ParsedReminder> reminders;

  /// Metnin tamamı ya da bir kısmı diğer giriş alanına ait; o kısım için
  /// kayıt üretilmedi.
  final bool otherDomain;

  /// Diğer alana ait kısmın modelin yazdığı kısa özeti.
  final String? otherDomainSummary;

  int get totalCount =>
      tasks.length +
      nutrition.length +
      workouts.length +
      weights.length +
      notes.length +
      routines.length +
      reminders.length;

  /// `quick_add_entries` RPC'sine giden kalem sayısı (hatırlatıcılar hariç).
  int get rpcCount => totalCount - reminders.length;

  bool get isEmpty => totalCount == 0;

  /// [taskCategories]: görevler için izin verilen (açık) kategoriler.
  factory ParsedEntry.fromJson(
    Map<String, dynamic> json, {
    List<String> taskCategories = ParsedTask.categories,
  }) =>
      ParsedEntry(
        tasks: _parseList(
          json['tasks'],
          (m) => ParsedTask.fromJson(m, allowed: taskCategories),
        ),
        nutrition: _parseList(json['nutrition'], ParsedNutrition.fromJson),
        workouts: _parseList(json['workouts'], ParsedWorkout.fromJson),
        weights: _parseList(json['weights'], ParsedWeight.fromJson),
        notes: _parseList(json['notes'], ParsedNote.fromJson),
        routines: _parseList(json['routines'], ParsedRoutine.fromJson),
        reminders: _parseList(json['reminders'], ParsedReminder.fromJson),
        otherDomain: _parseFlag(json['other_domain']),
        otherDomainSummary: _parseSummary(json['other_domain_summary']),
      );

  static bool _parseFlag(Object? value) =>
      value == true || (value is String && value.trim().toLowerCase() == 'true');

  static String? _parseSummary(Object? value) {
    final text = _parseText(value);
    return text == null ? null : _truncate(text, 200);
  }

  /// Model şemaya rağmen diğer alanın dizilerini doldurursa onları atar:
  /// iş girişinden öğün, sağlık girişinden görev kaydedilmez.
  ParsedEntry restrictedTo(QuickAddMode mode) => switch (mode) {
        QuickAddMode.work => ParsedEntry(
            tasks: tasks,
            notes: notes,
            routines: routines,
            reminders: reminders,
            otherDomain: otherDomain,
            otherDomainSummary: otherDomainSummary,
          ),
        QuickAddMode.health => ParsedEntry(
            nutrition: nutrition,
            workouts: workouts,
            weights: weights,
            otherDomain: otherDomain,
            otherDomainSummary: otherDomainSummary,
          ),
      };

  /// `quick_add_entries` yükü. `other_domain` alanları yalnızca arayüz
  /// içindir, veritabanına gitmez.
  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'nutrition': nutrition.map((e) => e.toJson()).toList(),
        'workouts': workouts.map((e) => e.toJson()).toList(),
        'weights': weights.map((e) => e.toJson()).toList(),
        'notes': notes.map((e) => e.toJson()).toList(),
        'routines': routines.map((e) => e.toJson()).toList(),
      };

  /// Önizlemede bir kalemi çıkarmak için.
  ParsedEntry without(ParsedKind kind, int index) {
    List<T> drop<T>(List<T> source) {
      if (index < 0 || index >= source.length) return source;
      return [...source]..removeAt(index);
    }

    return ParsedEntry(
      tasks: kind == ParsedKind.task ? drop(tasks) : tasks,
      nutrition: kind == ParsedKind.nutrition ? drop(nutrition) : nutrition,
      workouts: kind == ParsedKind.workout ? drop(workouts) : workouts,
      weights: kind == ParsedKind.weight ? drop(weights) : weights,
      notes: kind == ParsedKind.note ? drop(notes) : notes,
      routines: kind == ParsedKind.routine ? drop(routines) : routines,
      reminders: kind == ParsedKind.reminder ? drop(reminders) : reminders,
      otherDomain: otherDomain,
      otherDomainSummary: otherDomainSummary,
    );
  }
}
