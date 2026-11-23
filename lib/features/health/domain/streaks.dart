import 'dart:math' as math;

import 'fat_loss_plan.dart' show FatLossRules;
import 'safe_targets.dart';

/// Seriler (Adım, Kayıt, Açık), haftalık kalori açığı ve düşük alım uyarısı.
/// Saf fonksiyonlar; ham günlük veriden türetilir, hiçbir şey saklanmaz
/// (geriye dönük kayıt eklenince seri kendiliğinden yeniden hesaplanır).
/// Gün, cihazın yerel takvimine göredir. Dondurma yoktur: bugün, gece
/// yarısından önce seriyi asla bozmaz.

/// Bir günün ham verisi.
class StreakDay {
  const StreakDay({
    required this.date,
    this.steps,
    this.mealCount = 0,
    this.intakeKcal = 0,
    this.expenditureKcal,
  });

  /// Yerel gün (saat 00:00).
  final DateTime date;

  /// Adım; sağlık kaynağı yoksa `null`.
  final int? steps;

  /// O gün kaydedilen öğün sayısı.
  final int mealCount;

  /// Kaydedilen kcal.
  final double intakeKcal;

  /// O günün harcaması (bugün için şu ana kadar); bilinmiyorsa `null`.
  final int? expenditureKcal;

  /// Kalori açığı = harcama − alınan; öğün ya da harcama yoksa `null`.
  double? get deficit => mealCount == 0 || expenditureKcal == null
      ? null
      : expenditureKcal! - intakeKcal;
}

/// Serilerin ölçütü olan hedefler.
class StreakTargets {
  const StreakTargets({
    required this.dailySteps,
    required this.kcalTarget,
    required this.floorKcal,
    this.plannedDeficit = 0,
  });

  final int dailySteps;
  final int kcalTarget;

  /// Kalori tabanı: max(1.200, bazal).
  final int floorKcal;

  /// Planın günlük açığı (harcama − hedef). Açık sınırı en az bu kadardır,
  /// böylece hedefinde yiyen kullanıcı cezalandırılmaz.
  final int plannedDeficit;
}

enum StreakKind {
  steps('Adım', 'Adım serisi'),
  logging('Kayıt', 'Kayıt serisi'),
  deficit('Açık', 'Açık serisi');

  const StreakKind(this.label, this.semanticLabel);

  /// Şeritteki kısa ad.
  final String label;

  /// VoiceOver adı: "Adım serisi 7 gün".
  final String semanticLabel;
}

/// Bugünün durumu.
enum StreakToday {
  /// Bugün koşul sağlandı (✓).
  done,

  /// Henüz sağlanmadı; gece yarısına kadar seri bozulmaz.
  pending,
}

/// Bir serinin özeti.
class StreakStatus {
  const StreakStatus({
    required this.kind,
    required this.current,
    required this.best,
    required this.today,
    required this.days,
  });

  final StreakKind kind;

  /// Bugünle (sağlandıysa) ya da dünle biten ardışık gün sayısı.
  final int current;

  /// Penceredeki en uzun seri.
  final int best;
  final StreakToday today;

  /// Gün → sayıldı mı (eskiden yeniye; nokta takvimi için).
  final Map<DateTime, bool> days;

  /// "Adım serisi 7 gün"
  String get semantics => '${kind.semanticLabel} $current gün';
}

/// Kayıt günü: ≥ 2 öğün ya da alınan ≥ hedefin %50'si.
bool isLoggingDay(StreakDay d, StreakTargets t) =>
    d.mealCount >= 2 || (d.mealCount > 0 && d.intakeKcal >= t.kcalTarget * 0.5);

/// Adım günü: adım ≥ hedef.
bool isStepsDay(StreakDay d, StreakTargets t) =>
    d.steps != null && d.steps! >= t.dailySteps;

/// Açık günü: Kayıt günü VE taban ≤ alınan ≤ hedef VE gerçek açık ≤ sınır
/// (max(min(%25 harcama, 1.000), planın açığı)). Aç kalmak ödüllendirilmez.
bool isDeficitDay(StreakDay d, StreakTargets t) {
  if (!isLoggingDay(d, t)) return false;
  if (d.intakeKcal < t.floorKcal || d.intakeKcal > t.kcalTarget) return false;
  final exp = d.expenditureKcal;
  if (exp == null) return true;
  final cap = math.max(deficitCap(exp), t.plannedDeficit);
  return exp - d.intakeKcal <= cap;
}

/// [days] (herhangi bir sırada, eksik günler boş sayılır) ve [today] için
/// üç seri. Bugün sağlanmadıysa "bekleniyor"dur ve seriyi bozmaz.
List<StreakStatus> computeStreaks({
  required List<StreakDay> days,
  required StreakTargets targets,
  required DateTime today,
  bool includeSteps = true,
}) {
  final todayOnly = DateTime(today.year, today.month, today.day);
  final byDay = {
    for (final d in days) DateTime(d.date.year, d.date.month, d.date.day): d,
  };
  return [
    if (includeSteps)
      _streak(
          StreakKind.steps, byDay, todayOnly, (d) => isStepsDay(d, targets)),
    _streak(
        StreakKind.logging, byDay, todayOnly, (d) => isLoggingDay(d, targets)),
    _streak(
        StreakKind.deficit, byDay, todayOnly, (d) => isDeficitDay(d, targets)),
  ];
}

StreakStatus _streak(
  StreakKind kind,
  Map<DateTime, StreakDay> byDay,
  DateTime today,
  bool Function(StreakDay) counts,
) {
  if (byDay.isEmpty) {
    return StreakStatus(
      kind: kind,
      current: 0,
      best: 0,
      today: StreakToday.pending,
      days: const {},
    );
  }
  final first = byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final marks = <DateTime, bool>{};
  var run = 0;
  var best = 0;
  for (var d = first;
      !d.isAfter(today);
      d = DateTime(d.year, d.month, d.day + 1)) {
    final day = byDay[d];
    final ok = day != null && counts(day);
    marks[d] = ok;
    if (ok) {
      run++;
      best = math.max(best, run);
    } else if (d != today) {
      run = 0;
    }
  }
  final todayDone = marks[today] ?? false;
  return StreakStatus(
    kind: kind,
    current: run,
    best: best,
    today: todayDone ? StreakToday.done : StreakToday.pending,
    days: marks,
  );
}

/// Son [SafeTargets.lowIntakeWarningDays] kapalı günün (bugün hariç) hepsinde
/// öğün kaydı var ve alınan tabanın altında mı? "Son 3 gün çok az yedin".
bool lowIntakeWarning({
  required List<StreakDay> days,
  required int floorKcal,
  required DateTime today,
}) {
  final byDay = {
    for (final d in days) DateTime(d.date.year, d.date.month, d.date.day): d,
  };
  for (var i = 1; i <= SafeTargets.lowIntakeWarningDays; i++) {
    final d = byDay[DateTime(today.year, today.month, today.day - i)];
    if (d == null || d.mealCount == 0 || d.intakeKcal >= floorKcal) {
      return false;
    }
  }
  return true;
}

/// Haftanın bir gününün açığı.
class DayDeficit {
  const DayDeficit({
    required this.date,
    required this.deficit,
    required this.isToday,
  });

  final DateTime date;

  /// Harcama − alınan (pozitif = açık); öğün ya da harcama yoksa `null`.
  final double? deficit;

  /// Bugün: "şu ana kadar" (kesinleşmez; grafikte taralı).
  final bool isToday;
}

/// Pazartesi–Pazar haftalık kalori açığı.
class WeekDeficit {
  const WeekDeficit({
    required this.weekStart,
    required this.days,
    required this.targetKcal,
  });

  /// Haftanın pazartesisi.
  final DateTime weekStart;

  /// Pazartesiden bugüne (en çok 7) gün.
  final List<DayDeficit> days;

  /// Haftalık hedef açık (kcal): haftalık hız × 7.700 ya da plan açığı × 7.
  final int targetKcal;

  /// Kapalı günler + bugün (şu ana kadar) toplamı.
  double get totalKcal => days.fold(0.0, (sum, d) => sum + (d.deficit ?? 0));

  /// ≈ kg = toplam / 7.700.
  double get kg => totalKcal / FatLossRules.kcalPerKgFat;

  /// Hedefin oranı (0..∞); hedef yoksa 0.
  double get progress => targetKcal <= 0 ? 0 : totalKcal / targetKcal;
}

/// [weekStart]'tan başlayan haftanın açığı; [today]'den sonraki günler
/// eklenmez.
WeekDeficit computeWeekDeficit({
  required DateTime weekStart,
  required List<StreakDay> days,
  required DateTime today,
  required int targetKcal,
}) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  final byDay = {
    for (final d in days) DateTime(d.date.year, d.date.month, d.date.day): d,
  };
  return WeekDeficit(
    weekStart: start,
    targetKcal: math.max(0, targetKcal),
    days: [
      for (var i = 0; i < 7; i++)
        if (!DateTime(start.year, start.month, start.day + i)
            .isAfter(todayOnly))
          DayDeficit(
            date: DateTime(start.year, start.month, start.day + i),
            deficit: byDay[DateTime(start.year, start.month, start.day + i)]
                ?.deficit,
            isToday:
                DateTime(start.year, start.month, start.day + i) == todayOnly,
          ),
    ],
  );
}

/// Haftalık hedef açık: hız modunda r × 7.700; klasikte planın günlük açığı
/// × 7 (negatifse 0).
int weeklyDeficitTarget({double? kgPerWeek, required int dailyDeficit}) =>
    kgPerWeek != null
        ? (kgPerWeek * FatLossRules.kcalPerKgFat).round()
        : math.max(0, dailyDeficit * 7);
