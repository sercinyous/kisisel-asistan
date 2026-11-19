import '../../../core/utils/date_utils.dart';

/// Rapor türü; Edge Function'ın `kind` alanıyla aynı değerler.
enum ReportKind {
  daily,
  weekly;

  /// `generate-reports` gövdesindeki değer.
  String get apiValue => name;
}

/// `ai_status` sütunu: yorumun durumu (sayılar her durumda vardır).
enum ReportAiStatus {
  pending,
  ok,
  failed;

  /// Bilinmeyen ya da eksik değer `pending` sayılır.
  static ReportAiStatus fromDb(Object? value) => switch (value) {
        'ok' => ReportAiStatus.ok,
        'failed' => ReportAiStatus.failed,
        _ => ReportAiStatus.pending,
      };
}

// --- Toleranslı okuma yardımcıları -----------------------------------------
// metrics sunucuda üretilen bir jsonb'dir; sürüm farkı ya da elle düzeltme
// yüzünden eksik anahtar, null ya da metin olarak gelen sayı ekranı düşürmemeli.

num? _num(Object? value) {
  if (value is num) return value.isFinite ? value : null;
  if (value is String) {
    final parsed = num.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

int? _intOrNull(Object? value) => _num(value)?.round();
int _int(Object? value) => _intOrNull(value) ?? 0;
double? _doubleOrNull(Object? value) => _num(value)?.toDouble();
double _double(Object? value) => _doubleOrNull(value) ?? 0;

/// Yüzde: 0..100 aralığına sıkıştırılır; sayı değilse `null`.
int? _rate(Object? value) => _intOrNull(value)?.clamp(0, 100);

DateTime? _date(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, v) => MapEntry(key.toString(), v))
    : const <String, dynamic>{};

/// Haftalık raporun `days` dizisindeki bir gün.
class DayMetrics {
  const DayMetrics({
    required this.date,
    this.workRate,
    this.formRate,
    this.calories = 0,
    this.proteinG = 0,
    this.steps = 0,
    this.sleepMinutes = 0,
    this.workouts = 0,
  });

  /// Yerel gün (gece yarısı).
  final DateTime date;

  /// İş tamamlama yüzdesi; o gün planlı iş yoksa (ya da gün gelmediyse) `null`.
  final int? workRate;

  /// Form yüzdesi; gün henüz gelmediyse `null`.
  final int? formRate;
  final double calories;
  final double proteinG;
  final int steps;
  final int sleepMinutes;

  /// O gün yapılan antrenman sayısı.
  final int workouts;

  /// Tarihi okunamayan kalem `null` döner (listeye alınmaz).
  static DayMetrics? tryParse(Object? json) {
    final map = _map(json);
    final date = _date(map['date']);
    if (date == null) return null;
    return DayMetrics(
      date: date,
      workRate: _rate(map['work_rate']),
      formRate: _rate(map['form_rate']),
      calories: _double(map['calories']),
      proteinG: _double(map['protein_g']),
      steps: _int(map['steps']),
      sleepMinutes: _int(map['sleep_minutes']),
      workouts: _int(map['workouts']),
    );
  }
}

/// Raporun sayıları (`metrics` jsonb). Kurallar sunucuda uygulanır
/// (supabase/schema.sql `report_period_metrics`); uygulama yalnızca gösterir.
///
/// Haftalık raporda beslenme ve sağlık değerleri **günlük ortalama**dır
/// (yalnızca verisi olan günler üzerinden); günlük raporda o günün toplamıdır.
class ReportMetrics {
  const ReportMetrics({
    this.periodStart,
    this.periodEnd,
    this.tasksTotal = 0,
    this.tasksDone = 0,
    this.routinesPlanned = 0,
    this.routinesDone = 0,
    this.workRate,
    this.workoutsPlanned = 0,
    this.workoutsDone = 0,
    this.proteinDaysHit = 0,
    this.calorieDaysInRange = 0,
    this.formRate,
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.daysLogged = 0,
    this.steps = 0,
    this.sleepMinutes = 0,
    this.activeKcal = 0,
    this.daysWithData = 0,
    this.weightStartKg,
    this.weightEndKg,
    this.weightChangeKg,
    this.targetCalories,
    this.targetProteinG,
    this.targetSteps,
    this.targetSleepMinutes,
    this.days = const [],
  });

  /// Hiç sayı içermeyen rapor (boş ya da okunamayan `metrics`).
  static const empty = ReportMetrics();

  // period
  final DateTime? periodStart;
  final DateTime? periodEnd;

  // work
  final int tasksTotal;
  final int tasksDone;
  final int routinesPlanned;
  final int routinesDone;

  /// (görev + rutin) tamamlama yüzdesi; planlı iş yoksa `null`.
  final int? workRate;

  // form
  final int workoutsPlanned;
  final int workoutsDone;
  final int proteinDaysHit;
  final int calorieDaysInRange;
  final int? formRate;

  // nutrition
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Öğün kaydı girilen gün sayısı; 0 ise beslenme değerleri "veri yok"tur.
  final int daysLogged;

  // health
  final int steps;
  final int sleepMinutes;
  final int activeKcal;

  /// HealthKit özeti bulunan gün sayısı; 0 ise sağlık değerleri "veri yok"tur.
  final int daysWithData;

  // weight
  /// Dönemden önceki son ölçüm (yoksa dönemdeki ilk ölçüm).
  final double? weightStartKg;

  /// Dönemdeki son ölçüm.
  final double? weightEndKg;
  final double? weightChangeKg;

  // targets (raporun üretildiği andaki günlük hedefler)
  final int? targetCalories;
  final int? targetProteinG;
  final int? targetSteps;
  final int? targetSleepMinutes;

  /// Gün gün döküm, eskiden yeniye (yalnızca haftalık raporda dolu).
  final List<DayMetrics> days;

  /// Rutin tamamlama yüzdesi; planlı rutin yoksa `null`.
  int? get routineRate => routinesPlanned <= 0
      ? null
      : (100 * routinesDone / routinesPlanned).round().clamp(0, 100);

  /// Görev tamamlama yüzdesi; o döneme ait görev yoksa `null`.
  int? get taskRate => tasksTotal <= 0
      ? null
      : (100 * tasksDone / tasksTotal).round().clamp(0, 100);

  bool get hasNutrition => daysLogged > 0;
  bool get hasHealth => daysWithData > 0;

  /// Eksik anahtar, `null`, metin olarak gelen sayı ve int/double farkı
  /// hata vermez; okunamayan alan varsayılana düşer.
  factory ReportMetrics.fromJson(Object? json) {
    final root = _map(json);
    if (root.isEmpty) return ReportMetrics.empty;
    final period = _map(root['period']);
    final work = _map(root['work']);
    final form = _map(root['form']);
    final nutrition = _map(root['nutrition']);
    final health = _map(root['health']);
    final weight = _map(root['weight']);
    final targets = _map(root['targets']);
    final rawDays = root['days'];

    final start = _doubleOrNull(weight['start_kg']);
    final end = _doubleOrNull(weight['end_kg']);
    final days = <DayMetrics>[
      if (rawDays is List)
        for (final item in rawDays)
          if (DayMetrics.tryParse(item) case final day?) day,
    ]..sort((a, b) => a.date.compareTo(b.date));

    return ReportMetrics(
      periodStart: _date(period['start']),
      periodEnd: _date(period['end']),
      tasksTotal: _int(work['tasks_total']),
      tasksDone: _int(work['tasks_done']),
      routinesPlanned: _int(work['routines_planned']),
      routinesDone: _int(work['routines_done']),
      workRate: _rate(work['rate']),
      workoutsPlanned: _int(form['workouts_planned']),
      workoutsDone: _int(form['workouts_done']),
      proteinDaysHit: _int(form['protein_days_hit']),
      calorieDaysInRange: _int(form['calorie_days_in_range']),
      formRate: _rate(form['rate']),
      calories: _double(nutrition['calories']),
      proteinG: _double(nutrition['protein_g']),
      carbsG: _double(nutrition['carbs_g']),
      fatG: _double(nutrition['fat_g']),
      daysLogged: _int(nutrition['days_logged']),
      steps: _int(health['steps']),
      sleepMinutes: _int(health['sleep_minutes']),
      activeKcal: _int(health['active_kcal']),
      daysWithData: _int(health['days_with_data']),
      weightStartKg: start,
      weightEndKg: end,
      // Sunucu değeri yoksa iki uçtan hesaplanır.
      weightChangeKg: _doubleOrNull(weight['change_kg']) ??
          (start != null && end != null ? end - start : null),
      targetCalories: _intOrNull(targets['calories']),
      targetProteinG: _intOrNull(targets['protein_g']),
      targetSteps: _intOrNull(targets['steps']),
      targetSleepMinutes: _intOrNull(targets['sleep_minutes']),
      days: List.unmodifiable(days),
    );
  }
}

DateTime? _timestamp(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

String? _summary(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// `daily_reports` satırı.
class DailyReport {
  const DailyReport({
    required this.reportDate,
    required this.metrics,
    this.aiSummary,
    this.aiStatus = ReportAiStatus.pending,
    this.generatedAt,
  });

  /// Raporun günü (yerel gece yarısı).
  final DateTime reportDate;
  final ReportMetrics metrics;

  /// Yapay zekâ yorumu; `aiStatus != ok` iken `null`.
  final String? aiSummary;
  final ReportAiStatus aiStatus;
  final DateTime? generatedAt;

  /// Yorum gösterilebilir mi?
  bool get hasSummary => aiStatus == ReportAiStatus.ok && aiSummary != null;

  factory DailyReport.fromMap(Map<String, dynamic> map) => DailyReport(
        reportDate: AppDates.startOfDay(
          DateTime.parse(map['report_date'] as String),
        ),
        metrics: ReportMetrics.fromJson(map['metrics']),
        aiSummary: _summary(map['ai_summary']),
        aiStatus: ReportAiStatus.fromDb(map['ai_status']),
        generatedAt: _timestamp(map['generated_at']),
      );
}

/// `weekly_reports` satırı.
class WeeklyReport {
  const WeeklyReport({
    required this.weekStart,
    required this.metrics,
    this.aiSummary,
    this.aiStatus = ReportAiStatus.pending,
    this.generatedAt,
  });

  /// Haftanın Pazartesi'si (yerel gece yarısı).
  final DateTime weekStart;
  final ReportMetrics metrics;

  /// Yapay zekâ yorumu; `aiStatus != ok` iken `null`.
  final String? aiSummary;
  final ReportAiStatus aiStatus;
  final DateTime? generatedAt;

  /// Haftanın Pazar'ı.
  DateTime get weekEnd => AppDates.addDays(weekStart, 6);

  /// Yorum gösterilebilir mi?
  bool get hasSummary => aiStatus == ReportAiStatus.ok && aiSummary != null;

  factory WeeklyReport.fromMap(Map<String, dynamic> map) => WeeklyReport(
        weekStart: AppDates.startOfDay(
          DateTime.parse(map['week_start'] as String),
        ),
        metrics: ReportMetrics.fromJson(map['metrics']),
        aiSummary: _summary(map['ai_summary']),
        aiStatus: ReportAiStatus.fromDb(map['ai_status']),
        generatedAt: _timestamp(map['generated_at']),
      );
}
