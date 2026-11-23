import '../core/config/app_targets.dart';
import '../core/services/health_service.dart';
import '../core/utils/date_utils.dart';
import '../features/ai_quick_add/data/quick_add_repository.dart';
import '../features/ai_quick_add/domain/parsed_entry.dart';
import '../features/ai_quick_add/domain/quick_add_mode.dart';
import '../features/health/data/google_health_source.dart';
import '../features/health/data/health_repository.dart';
import '../features/operations/domain/note_item.dart';
import '../features/operations/domain/task_item.dart';
import '../features/reports/domain/report_models.dart';
import '../features/routines/domain/routine.dart';
import '../core/avatar/avatar_spec.dart';
import '../features/health/data/body_repository.dart';
import '../features/health/domain/energy_balance.dart' show Sex;
import '../features/health/domain/targets_engine.dart';
import '../features/settings/domain/user_settings.dart';
import 'demo_backend.dart';

/// Demodaki sağlık ve öğün geçmişinin uzunluğu (gün; bugün dahil).
const int demoHistoryDays = 60;

/// Demo kullanıcısının profili (Ayarlar > Profil, Enerji dengesi).
const int demoHeightCm = 180;
const int demoBirthYear = 1990;
const String demoSex = 'male';

/// Demo kullanıcısının kilo hedefleri (tartı geçmişi 86,2 → 83,6 kg).
const double demoStartWeightKg = 86;
const double demoTargetWeightKg = 80;

/// Demodaki isteğe bağlı ekip (Ayarlar > Ekip, görevlerde "İlgili kişi").
const List<String> _demoTeam = ['Ayşe', 'Can', 'Elif'];

/// Tarayıcı demosunun bellekteki örnek verisi.
class DemoData {
  DemoData._({
    required this.routines,
    required this.tasks,
    required this.notes,
    required this.health,
    required this.kokpit,
    required this.settings,
    required this.reports,
    required this.body,
  });

  final FakeRoutinesRepository routines;
  final FakeTasksRepository tasks;
  final FakeNotesRepository notes;
  final FakeHealthRepository health;
  final FakeKokpitRepository kokpit;
  final FakeSettingsRepository settings;
  final FakeReportsRepository reports;

  /// Mezura ölçüleri (fotoğraf web demosunda yüklenmez).
  final MemoryBodyRepository body;

  int _seq = 0;
  String nextId(String prefix) => '$prefix-demo-${_seq++}';

  /// [regenerateDelay]: "Raporu oluştur" bu kadar sürer (tarayıcı demosunda
  /// meşgul durumu görünsün diye verilir; testlerde sıfırdır).
  factory DemoData.seed(
    DateTime now, {
    Duration regenerateDelay = Duration.zero,
  }) {
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

    final thisWeek = AppDates.weekStart(today);
    final health = FakeHealthRepository(
      // Son 60 gün: Trend ekranı (hafta/ay, geçen ay), Enerji dengesi ve Ay
      // özeti ay başında da dolu olsun. Üç haftadan eski günlerin bazısında
      // sağlık verisi yoktur ("veri yok" günleri trendde boş görünür); raporların
      // kapsadığı son üç hafta eksiksizdir.
      metrics: [
        for (var back = demoHistoryDays - 1; back >= 0; back--)
          if (!_demoHealthGap(back, AppDates.addDays(today, -back)))
            _demoMetric(AppDates.addDays(today, -back)),
      ],
      // 90 günde 86.2 → 83.6 kg; üç günde bir ölçüm, küçük dalgalanmayla.
      weights: [
        for (var back = 90; back >= 3; back -= 3)
          WeightEntry(
            id: 'w-$back',
            weightKg: double.parse(
              (83.6 + back * 0.029 + ((back ~/ 3) % 3 - 1) * 0.15)
                  .toStringAsFixed(1),
            ),
            loggedAt: AppDates.addDays(today, -back).add(
              const Duration(hours: 8),
            ),
          ),
        WeightEntry(
          id: 'w-0',
          weightKg: 83.6,
          loggedAt: today.add(const Duration(hours: 8)),
        ),
      ],
      // Geçmiş günler toplam olarak; bugünün öğünleri kalem kalem. Üç haftadan
      // eski günlerin bazısında öğün girilmemiştir (enerji dengesi "henüz öğün
      // girilmedi" der, kalori trendi o günü paydaya katmaz).
      nutrition: [
        for (var back = demoHistoryDays - 1; back >= 1; back--)
          if (!_demoMealGap(back, AppDates.addDays(today, -back)))
            _demoNutrition(AppDates.addDays(today, -back)),
      ],
      nutritionLogs: [
        NutritionLog(
          id: 'n-1',
          mealType: 'breakfast',
          foodName: 'Yulaf ezmesi',
          quantityText: '70 gr',
          calories: 264,
          proteinG: 9,
          carbsG: 46,
          fatG: 5,
          eatenAt: today.add(const Duration(hours: 8, minutes: 10)),
        ),
        NutritionLog(
          id: 'n-2',
          mealType: 'breakfast',
          foodName: 'Yumurta',
          quantityText: '2 adet',
          calories: 156,
          proteinG: 13,
          carbsG: 1,
          fatG: 11,
          eatenAt: today.add(const Duration(hours: 8, minutes: 10)),
        ),
        NutritionLog(
          id: 'n-3',
          mealType: 'lunch',
          foodName: 'Tavuk göğsü',
          quantityText: '200 gr',
          calories: 330,
          proteinG: 62,
          carbsG: 0,
          fatG: 7,
          eatenAt: today.add(const Duration(hours: 13, minutes: 5)),
          source: 'ai',
        ),
        NutritionLog(
          id: 'n-4',
          mealType: 'lunch',
          foodName: 'Tam çavdar ekmeği',
          quantityText: '2 dilim',
          calories: 130,
          proteinG: 5,
          carbsG: 24,
          fatG: 2,
          eatenAt: today.add(const Duration(hours: 13, minutes: 5)),
          source: 'ai',
        ),
        // Yağ yakımı "Bugün" kartı karışık bir gün göstersin: yağ fazla,
        // protein ve karbonhidrat eksik.
        NutritionLog(
          id: 'n-5',
          mealType: 'lunch',
          foodName: 'Peynirli börek',
          quantityText: '1 porsiyon',
          calories: 420,
          proteinG: 12,
          carbsG: 38,
          fatG: 26,
          eatenAt: today.add(const Duration(hours: 13, minutes: 5)),
          source: 'ai',
        ),
        NutritionLog(
          id: 'n-6',
          mealType: 'snack',
          foodName: 'Karışık kuruyemiş',
          quantityText: '60 gr',
          calories: 370,
          proteinG: 11,
          carbsG: 12,
          fatG: 32,
          eatenAt: today.add(const Duration(hours: 16, minutes: 30)),
        ),
      ],
      // Son iki haftanın antrenmanları (plan günlerine göre; birkaçı kaçmış).
      workouts: [
        for (var back = 13; back >= 1; back--)
          if (_demoWorkout(AppDates.addDays(today, -back)) case final w?) w,
      ],
    );

    return DemoData._(
      routines: FakeRoutinesRepository(
        routines: [
          weekly(
              'r1', 'Sabah tartı ve kilo kaydı', 'Kişisel', 'beslenme', 8, 0),
          weekly('r2', 'Sabah planı ve öncelikler', AppTargets.workCategory,
              'operasyon', 9, 0),
          weekly('r3', 'Gelen kutusu kontrolü', AppTargets.workCategory,
              'operasyon', 9, 30),
          weekly('r4', 'Öğlen görev listesini gözden geçir',
              AppTargets.workCategory, 'operasyon', 13, 0),
          weekly('r5', 'Ağırlık antrenmanı', 'Kişisel', 'spor', 19, 0,
              days: const [1, 2, 4, 5]),
          weekly('r6', 'Kickboks', 'Kişisel', 'spor', 19, 30, days: const [3]),
          weekly('r7', 'Koşu', 'Kişisel', 'spor', 10, 0, days: const [6]),
          weekly('r8', 'Halı saha', 'Kişisel', 'spor', 20, 0, days: const [7]),
          weekly('r9', 'Günü kapat ve yarını planla', AppTargets.workCategory,
              'operasyon', 22, 0),
          monthly('m1', 'Maaş ödemeleri', AppTargets.workCategory, 'finans',
              dayIn(2)),
          monthly('m2', 'Aylık faaliyet raporu', AppTargets.workCategory,
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
        task('t1', 'Ayşe ile haftalık planı gözden geçir', 'Ekip', 'high',
            today.add(const Duration(days: 1, hours: 15)),
            assignee: _demoTeam.first),
        task('t2', 'Dişçi randevusu', 'Kişisel', 'medium',
            today.add(const Duration(days: 3, hours: 14))),
        task('t3', 'Faaliyet raporunu hazırla', AppTargets.workCategory, 'high',
            today.add(const Duration(days: 2, hours: 12))),
        task('t4', 'Aylık gelir-gider tablosu', 'Finans', 'medium',
            today.add(const Duration(days: 6, hours: 18))),
      ]),
      notes: FakeNotesRepository(notes: [
        NoteItem(
          id: 'n1',
          title: 'Form hedefi',
          content:
              'Haftalık ortalama kiloyu takip et, hedefe acele etmeden yaklaş.',
          isPinned: true,
          createdAt: now,
        ),
        NoteItem(
          id: 'n2',
          title: 'Fikir: haftalık gözden geçirme şablonu',
          content:
              'Her pazar tekrar kullanılabilecek kısa bir kontrol listesi.',
          category: 'Fikir',
          createdAt: now,
        ),
      ]),
      health: health,
      // Kokpit'in beslenme özeti Sağlık sekmesindeki öğün kayıtlarından gelir.
      kokpit: FakeKokpitRepository(health: health),
      // Profil dolu: Enerji dengesi kartı sayıları gösterir (boş profilde
      // "boy, yaş ve cinsiyet gerekli" der). Kilo hedefleri demodaki tartı
      // geçmişiyle tutarlıdır; ekip isteğe bağlıdır, demoda birkaç kişi vardır.
      // Hedefler plan motorunun yazdığı gibidir (0,5 kg/hafta, son tartı).
      settings: FakeSettingsRepository(
        settings: demoPlanSettings(
          const UserSettings.defaults().copyWith(
            startWeightKg: demoStartWeightKg,
            targetWeightKg: demoTargetWeightKg,
            heightCm: demoHeightCm,
            birthYear: demoBirthYear,
            sex: demoSex,
            activityLevel: ActivityLevel.moderate,
            teamMembers: _demoTeam,
            weeklyRate: FatLossRate.half,
            avatar: const AvatarChoice(
              kind: AvatarKind.mascot,
              mascotId: 'bal_porsugu',
            ),
          ),
          latestWeightKg: 83.6,
          now: now,
        ),
      ),
      body: MemoryBodyRepository(measurements: demoMeasurements(today)),
      reports: FakeReportsRepository(
        // Bu hafta (kısmi) + önceki iki hafta.
        weekly: [
          for (var back = 2; back >= 0; back--)
            demoWeeklyReport(AppDates.addDays(thisWeek, -7 * back), now),
        ],
        // Dünle biten 7 gün; bugünün raporu henüz üretilmemiş görünür.
        daily: [
          for (var back = 7; back >= 1; back--)
            demoDailyReport(AppDates.addDays(today, -back), now),
        ],
        weeklyBuilder: (weekStart) =>
            demoWeeklyReport(weekStart, DateTime.now()),
        dailyBuilder: (day) => demoDailyReport(day, DateTime.now()),
        regenerateDelay: regenerateDelay,
      ),
    );
  }
}

/// Demodaki Google Health kaynağı: bugünün ve son 7 günün sayıları HealthKit
/// demosundan farklıdır (kaynak değişince kartlarda fark görülür) ve dünün
/// sabah koşusu içe aktarılır (yeniden eşitlemede kopyası oluşmaz).
FakeGoogleHealthSource demoGoogleHealthSource(
  GoogleHealthLink link,
  DateTime now,
) {
  final today = AppDates.startOfDay(now);
  HealthSnapshot googleDay(DateTime day) {
    final m = _demoMetric(day);
    return HealthSnapshot(
      status: HealthStatus.ok,
      steps: m.steps + 640,
      activeKcal: m.activeKcal + 45,
      sleepMinutes: m.sleepMinutes - 12,
      readAt: now,
      source: HealthSourceKind.googleHealth,
    );
  }

  final yesterday = AppDates.addDays(today, -1);
  return FakeGoogleHealthSource(
    link: link,
    today: googleDay(today),
    pastDays: [
      for (var back = HealthService.backfillDays; back >= 1; back--)
        (
          day: AppDates.addDays(today, -back),
          snapshot: googleDay(AppDates.addDays(today, -back)),
        ),
    ],
    workouts: [
      ExternalWorkout(
        source: GoogleHealthSource.workoutSource,
        externalId: 'demo-google-run-${AppDates.ymd(yesterday)}',
        workout: WorkoutLog(
          id: '',
          workoutType: 'running',
          title: 'Sabah koşusu',
          durationMin: 38,
          distanceKm: 6.12,
          caloriesBurned: 402,
          loggedAt: yesterday.add(const Duration(hours: 7, minutes: 5)),
          source: GoogleHealthSource.workoutSource,
        ),
      ),
    ],
  );
}

// --- Demo sayıları: tarihe bağlıdır, sayfa her açıldığında aynı çıkar. --------

int _seed(DateTime day) => day.month * 31 + day.day;

/// Raporların kapsadığı en eski gün bugünden 20 gün öncedir (üç hafta); bundan
/// eski günlerde veri boşlukları olabilir, yakın günler her zaman doludur.
const int _demoGapFromDaysBack = 21;

/// [back] gün öncesi (bugün 0) için sağlık satırı yok mu? Her yedi eski
/// günden biri.
bool _demoHealthGap(int back, DateTime day) =>
    back >= _demoGapFromDaysBack && _seed(day) % 7 == 3;

/// [back] gün öncesi için öğün kaydı yok mu? Her altı eski günden biri;
/// sağlık boşluklarıyla örtüşmez ki "öğün var, aktif kalori verisi yok" günü
/// de görünsün.
bool _demoMealGap(int back, DateTime day) =>
    back >= _demoGapFromDaysBack && _seed(day) % 6 == 2;

DailyHealthMetric _demoMetric(DateTime day) {
  final d = _seed(day);
  return DailyHealthMetric(
    day: day,
    // 7000–11799: hedef (10000) günlerin yaklaşık yarısında tutar.
    steps: 7000 + (d * 517) % 4800,
    activeKcal: 320 + (d * 37) % 260,
    sleepMinutes: 390 + (d * 23) % 90,
  );
}

DailyNutritionTotal _demoNutrition(DateTime day) {
  final d = _seed(day);
  // Her dokuzuncu gün "kaçmış" gündür (+450 kcal): kalori trendinde hedefi
  // aşan, enerji dengesinde fazla geçen gün de görünsün.
  final slip = d % 9 == 0 ? 450.0 : 0.0;
  return DailyNutritionTotal(
    day: day,
    calories: 1850.0 + (d * 61) % 320 + slip,
    proteinG: 146.0 + (d * 7) % 34,
    carbsG: 170,
    fatG: 60,
    entryCount: 4,
  );
}

/// Plan: ağırlık Pzt/Sal/Per/Cum, kickboks Çar, koşu Cmt, halı saha Paz.
/// Her dört günden biri kaçmış sayılır (`null`).
WorkoutLog? _demoWorkout(DateTime day) {
  if (_seed(day) % 4 == 0) return null;
  final (type, title, hour, minutes, kcal, km) = switch (day.weekday) {
    DateTime.wednesday => ('kickboxing', 'Kickboks', 19, 60, 540, null),
    DateTime.saturday => ('running', 'Koşu', 10, 40, 420, 6.5),
    DateTime.sunday => ('football', 'Halı saha', 20, 60, 480, null),
    _ => ('weights', 'Ağırlık antrenmanı', 19, 45, 310, null),
  };
  return WorkoutLog(
    id: 'wo-${AppDates.ymd(day)}',
    workoutType: type,
    title: title,
    durationMin: minutes,
    distanceKm: km,
    caloriesBurned: kcal,
    loggedAt: day.add(Duration(hours: hour, minutes: 30)),
  );
}

/// Sunucunun ürettiği `metrics` biçiminde bir günün sayıları. Gelecek gün
/// boştur (oranlar `null`).
Map<String, dynamic> _demoDayJson(DateTime day, DateTime today) {
  if (day.isAfter(today)) {
    return {
      'date': AppDates.ymd(day),
      'work_rate': null,
      'form_rate': null,
      'calories': 0,
      'protein_g': 0,
      'steps': 0,
      'sleep_minutes': 0,
      'workouts': 0,
    };
  }
  final d = _seed(day);
  final metric = _demoMetric(day);
  final nutrition = _demoNutrition(day);
  final workedOut = _demoWorkout(day) != null;
  // Hedef 170 g; eşik %90 = 153 g.
  final proteinHit = nutrition.proteinG >= 153;
  return {
    'date': AppDates.ymd(day),
    'work_rate': 58 + (d * 13) % 40,
    'form_rate': ((workedOut ? 1 : 0) + (proteinHit ? 1 : 0)) * 50,
    'calories': nutrition.calories,
    'protein_g': nutrition.proteinG,
    'steps': metric.steps,
    'sleep_minutes': metric.sleepMinutes,
    'workouts': workedOut ? 1 : 0,
  };
}

const Map<String, dynamic> _demoTargets = {
  'calories': 2000,
  'protein_g': 170,
  'steps': 10000,
  'sleep_minutes': 450,
};

/// Demo haftalık raporu ([weekStart] Pazartesi). İçinde bulunulan haftada
/// yalnızca geçen günler sayılır.
WeeklyReport demoWeeklyReport(DateTime weekStart, DateTime now) {
  final today = AppDates.startOfDay(now);
  final days = [
    for (var i = 0; i < 7; i++)
      _demoDayJson(AppDates.addDays(weekStart, i), today),
  ];
  final elapsed = days.where((d) => d['work_rate'] != null).toList();
  final n = elapsed.length;
  int sum(String key) =>
      elapsed.fold<num>(0, (total, d) => total + (d[key] as num)).round();
  int avg(String key) => n == 0 ? 0 : (sum(key) / n).round();

  final workouts = sum('workouts');
  final proteinDays =
      elapsed.where((d) => (d['protein_g'] as num) >= 153).length;
  final calorieDays = elapsed
      .where((d) =>
          (d['calories'] as num) >= 1700 && (d['calories'] as num) <= 2200)
      .length;
  final tasksTotal = n == 0 ? 0 : 5 + n;
  final tasksDone = (tasksTotal * avg('work_rate') / 100).round();
  final routinesPlanned = n * 7;
  final routinesDone = (routinesPlanned * avg('work_rate') / 100).round();
  // Haftada yaklaşık 0.2 kg iniş: demo kilo serisiyle aynı eğim.
  final weeksAgo = AppDates.weekStart(today).difference(weekStart).inDays ~/ 7;
  final endKg = 83.6 + weeksAgo * 0.2;

  final metrics = <String, dynamic>{
    'period': {
      'start': AppDates.ymd(weekStart),
      'end': AppDates.ymd(AppDates.addDays(weekStart, 6)),
    },
    'work': {
      'tasks_total': tasksTotal,
      'tasks_done': tasksDone,
      'routines_planned': routinesPlanned,
      'routines_done': routinesDone,
      'rate': n == 0 ? null : avg('work_rate'),
    },
    'form': {
      'workouts_planned': n,
      'workouts_done': workouts,
      'protein_days_hit': proteinDays,
      'calorie_days_in_range': calorieDays,
      'rate':
          n == 0 ? null : (100 * (workouts + proteinDays) / (2 * n)).round(),
    },
    'nutrition': {
      'calories': avg('calories'),
      'protein_g': avg('protein_g'),
      'carbs_g': n == 0 ? 0 : 170,
      'fat_g': n == 0 ? 0 : 60,
      'days_logged': n,
    },
    'health': {
      'steps': avg('steps'),
      'sleep_minutes': avg('sleep_minutes'),
      'active_kcal': n == 0 ? 0 : 430,
      'days_with_data': n,
    },
    'weight': {
      'start_kg': n == 0 ? null : endKg + 0.2,
      'end_kg': n == 0 ? null : endKg,
      'change_kg': n == 0 ? null : -0.2,
    },
    'targets': _demoTargets,
    'days': days,
  };
  final parsed = ReportMetrics.fromJson(metrics);
  return WeeklyReport(
    weekStart: weekStart,
    metrics: parsed,
    aiSummary: n == 0
        ? null
        : 'İş tarafında ${(parsed.workRate ?? 0) >= 75 ? 'güçlü' : 'orta'} bir hafta: '
            'görevlerin $tasksDone / $tasksTotal kadarı kapandı, rutinler '
            '%${parsed.routineRate ?? 0} düzeyinde. Form tarafında $workouts antrenman '
            'yapıldı, protein hedefi $proteinDays gün tuttu.\n'
            'Kaçan antrenmanı sabaha al.\n'
            'Öğle öğününe 30 g protein ekle.\n'
            'Hafta sonu için uyku saatini sabitle.',
    aiStatus: n == 0 ? ReportAiStatus.failed : ReportAiStatus.ok,
    generatedAt: now,
  );
}

/// Demo günlük raporu.
DailyReport demoDailyReport(DateTime day, DateTime now) {
  final today = AppDates.startOfDay(now);
  final json = _demoDayJson(day, today);
  final metric = _demoMetric(day);
  final d = _seed(day);
  final workedOut = json['workouts'] == 1;
  final proteinHit = (json['protein_g'] as num) >= 153;
  final calories = json['calories'] as num;
  final tasksTotal = 1 + d % 3;
  final workRate = json['work_rate'] as int? ?? 0;
  final metrics = <String, dynamic>{
    'period': {'start': AppDates.ymd(day), 'end': AppDates.ymd(day)},
    'work': {
      'tasks_total': tasksTotal,
      'tasks_done': (tasksTotal * workRate / 100).round(),
      'routines_planned': 7,
      'routines_done': (7 * workRate / 100).round(),
      'rate': json['work_rate'],
    },
    'form': {
      'workouts_planned': 1,
      'workouts_done': json['workouts'],
      'protein_days_hit': proteinHit ? 1 : 0,
      'calorie_days_in_range': calories >= 1700 && calories <= 2200 ? 1 : 0,
      'rate': json['form_rate'],
    },
    'nutrition': {
      'calories': calories,
      'protein_g': json['protein_g'],
      'carbs_g': 170,
      'fat_g': 60,
      'days_logged': 1,
    },
    'health': {
      'steps': metric.steps,
      'sleep_minutes': metric.sleepMinutes,
      'active_kcal': metric.activeKcal,
      'days_with_data': 1,
    },
    'weight': {'start_kg': null, 'end_kg': null, 'change_kg': null},
    'targets': _demoTargets,
  };
  return DailyReport(
    reportDate: day,
    metrics: ReportMetrics.fromJson(metrics),
    aiSummary: 'İşlerin %$workRate kadarı tamamlandı. '
        '${workedOut ? 'Antrenman yapıldı' : 'Antrenman kaçtı'}, protein hedefi '
        '${proteinHit ? 'tuttu' : 'biraz altında kaldı'}. '
        '${metric.steps} adım ve ${metric.sleepMinutes ~/ 60} sa '
        '${metric.sleepMinutes % 60} dk uyku ile gün dengeli geçti.',
    aiStatus: ReportAiStatus.ok,
    generatedAt: now,
  );
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
      saved.add(
        SavedTask(
          id: id,
          title: t.title,
          dueAt: t.dueAt,
          remindAt: t.remindAt,
        ),
      );
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
    for (final n in entry.nutrition) {
      _data.health.nutritionLogs.add(
        NutritionLog(
          id: _data.nextId('nutrition'),
          mealType: n.mealType,
          foodName: n.foodName,
          quantityText: n.quantityText,
          calories: n.calories,
          proteinG: n.proteinG,
          carbsG: n.carbsG,
          fatG: n.fatG,
          eatenAt: n.eatenAt?.toLocal() ?? DateTime.now(),
          source: 'ai',
        ),
      );
    }
    for (final w in entry.workouts) {
      _data.health.workouts.add(
        WorkoutLog(
          id: _data.nextId('workout'),
          workoutType: w.workoutType,
          title: w.title,
          durationMin: w.durationMin,
          distanceKm: w.distanceKm,
          caloriesBurned: w.caloriesBurned,
          notes: w.notes,
          loggedAt: w.performedAt?.toLocal() ?? DateTime.now(),
          source: 'ai',
        ),
      );
    }
    return QuickAddResult(
      tasks: saved,
      nutritionCount: entry.nutrition.length,
      workoutCount: entry.workouts.length,
      weightCount: entry.weights.length,
      noteCount: entry.notes.length,
      routineCount: entry.routines.length,
      reminderCount: entry.reminders.length,
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

  final scope =
      RegExp(r'maaş|toplantı|vardiya|müşteri|rapor|ekip|proje|ofis').hasMatch(s)
          ? AppTargets.workCategory
          : 'Kişisel';
  final category = RegExp(r'maaş|ödeme|fatura|kira|bütçe').hasMatch(s)
      ? 'finans'
      : (scope == AppTargets.workCategory ? 'operasyon' : 'kisisel');

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
    for (final name in _demoTeam) {
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
              : scope == AppTargets.workCategory
                  ? AppTargets.workCategory
                  : 'Kişisel',
      'priority': RegExp(r'acil|önemli|hemen').hasMatch(s) ? 'high' : 'medium',
      'assignee': assignee,
      'due_at': due?.toIso8601String(),
      // Gerçek talimattaki gibi: ayrı bir hatırlatma zamanı söylenmedi.
      'remind_at': null,
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

/// Demo ayarlarına plan motorunun hedeflerini yazar (ilk kurulum sonrası
/// durum gibi; kaynak 'plan').
UserSettings demoPlanSettings(
  UserSettings base, {
  required double latestWeightKg,
  required DateTime now,
}) {
  final resolved = resolveTargets(
    settings: base,
    latestWeightKg: latestWeightKg,
    age: ageFromSettings(base, now),
    sex: Sex.tryParse(base.sex),
  );
  return planWrite(
    settings: base,
    resolved: resolved,
    trigger: PlanTrigger.rateChanged,
    now: now.subtract(const Duration(days: 2)),
  )!
      .settings;
}

/// 12 haftalık mezura geçmişi (her pazartesi): bel 94 → 89 cm, kalça
/// 104 → 101 cm; kol ve boyun yaklaşık sabit. Bu haftanın ölçüsü henüz
/// girilmemiştir (Vücut sekmesinde "ölçü günü" görünsün).
List<BodyMeasurement> demoMeasurements(DateTime today) {
  final thisMonday = AppDates.weekStart(today);
  return [
    for (var week = 12; week >= 1; week--)
      BodyMeasurement(
        id: 'bm-$week',
        measuredOn: AppDates.addDays(thisMonday, -7 * week),
        values: {
          BodyField.waist: roundCm(89 + week * 0.42 + (week % 3 == 0 ? 0.3 : 0)),
          BodyField.hip: roundCm(101 + week * 0.25),
          BodyField.chest: roundCm(103 + week * 0.15),
          BodyField.arm: roundCm(35.5 - week * 0.02),
          if (week.isEven) BodyField.thigh: roundCm(58 + week * 0.18),
          BodyField.neck: roundCm(39.5 + week * 0.05),
        },
      ),
  ];
}
