import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/health/domain/checkin.dart';
import '../../features/settings/domain/user_settings.dart';
import '../utils/date_utils.dart';
import 'notification_plan.dart';

/// Sağlık dürtüleri. Sıra önceliktir: bir güne ikiden fazla düşerse
/// sondakiler atılır.
enum HealthNudgeKind {
  /// Ölçü günü 09:00 (Plan > "Ölçü ve fotoğraf günü" anahtarı yönetir).
  checkin('Ölçü ve fotoğraf günü', 9, 0),

  /// 20:30: bugün hiç öğün yoksa.
  meals('Öğün hatırlatması', 20, 30),

  /// 19:00: hedefin en az %70'i bitti ve 4.000'den az adım kaldıysa.
  steps('Adım hatırlatması', 19, 0),

  /// Pazar 21:00: haftanın açığı ve işlerin oranı.
  weekly('Haftalık özet', 21, 0);

  const HealthNudgeKind(this.label, this.hour, this.minute);

  /// Ayarlardaki anahtarın adı.
  final String label;
  final int hour;
  final int minute;
}

/// Gün başına en fazla sağlık dürtüsü.
const int maxHealthNudgesPerDay = 2;

/// Planın kaç gün ileriye baktığı (bugün dahil).
const int healthNudgeHorizonDays = 7;

/// Planlamanın okuduğu anlık durum. Bilinmeyen değer `null`dır ve o dürtü
/// (yanlış bir şey söylememek için) planlanmaz.
class HealthNudgeState {
  const HealthNudgeState({
    required this.mealsLoggedToday,
    this.stepsToday,
    this.stepTarget = 0,
    this.checkinDoneToday = false,
    this.weekDeficitKcal,
    this.weekDeficitKg,
    this.tasksDonePercent,
  });

  /// Bugün en az bir öğün kaydı var; `null` = okunamadı.
  final bool? mealsLoggedToday;

  /// Bugünkü adım; sağlık kaynağı yoksa `null`.
  final int? stepsToday;
  final int stepTarget;
  final bool checkinDoneToday;

  /// Bu haftanın (Pazartesi→bugün) toplam açığı; veri yoksa `null`.
  final double? weekDeficitKcal;
  final double? weekDeficitKg;

  /// Haftanın işlerinin tamamlanma oranı (0–100); bilinmiyorsa `null`.
  final int? tasksDonePercent;
}

/// Adım dürtüsünün koşulu: hedefin ≥ %70'i tamam, kalan < 4.000 ve hedef
/// henüz bitmedi.
bool stepsNudgeApplies(int? steps, int target) {
  if (steps == null || target <= 0 || steps >= target) return false;
  return steps >= target * 0.7 && target - steps < 4000;
}

final NumberFormat _thousands = NumberFormat.decimalPattern('tr_TR');
final NumberFormat _oneDecimal = NumberFormat('0.0', 'tr_TR');

/// "Bu hafta −3.100 kcal (≈0,4 kg) · işlerin %80 tamam". Açık yoksa suçlamadan
/// yalnızca işler (o da yoksa `null`).
String? weeklyNudgeBody(HealthNudgeState state) {
  final parts = <String>[];
  final kcal = state.weekDeficitKcal;
  if (kcal != null && kcal >= 100) {
    final kg = state.weekDeficitKg ?? kcal / 7700;
    parts.add('Bu hafta −${_thousands.format(kcal.round())} kcal '
        '(≈${_oneDecimal.format(kg)} kg)');
  }
  final tasks = state.tasksDonePercent;
  if (tasks != null) parts.add('işlerin %$tasks tamam');
  if (parts.isEmpty) return null;
  final text = parts.join(' · ');
  // Türkçe büyük harf: i → İ.
  final head = text[0] == 'i' ? 'İ' : text[0].toUpperCase();
  return head + text.substring(1);
}

/// Sağlık dürtülerinin anahtarı; [HealthNudgeKind] ve günden türetilir.
String healthNudgeKey(HealthNudgeKind kind, DateTime day) =>
    'health:${kind.name}:${DateFormat('yyyy-MM-dd').format(day)}';

/// [now]'dan itibaren [healthNudgeHorizonDays] günün tüm olası anahtarları
/// (dünü de kapsar); eski planı silerken kullanılır.
List<String> healthNudgeKeysAround(DateTime now) {
  final today = AppDates.startOfDay(now);
  return [
    for (var i = -1; i < healthNudgeHorizonDays; i++)
      for (final kind in HealthNudgeKind.values)
        healthNudgeKey(kind, AppDates.addDays(today, i)),
  ];
}

/// Sağlık dürtülerini hesaplar (saf). Kurallar:
/// - Bildirimler kapalıysa hiç; kullanıcının kapattığı türler hiç.
/// - Sessiz saate düşen dürtü aynı gün sessiz saatin bitişine kayar; o gün
///   içinde kalmıyorsa atılır (gece yarısı "öğün ekle" denmez).
/// - Gün başına en çok [maxHealthNudgesPerDay], öncelik [HealthNudgeKind] sırası.
/// - Öğün dürtüsü bugün kayıt varsa bugün için yok; adım dürtüsü yalnızca bugün
///   ve koşul tutarsa; haftalık yalnızca bu haftanın Pazarı.
List<PlannedNotification> buildHealthNudgePlan({
  required DateTime now,
  required UserSettings settings,
  required HealthNudgeState state,
  Set<HealthNudgeKind> disabled = const {},
}) {
  if (!settings.notificationsEnabled) return const [];
  final today = AppDates.startOfDay(now);
  final quietStart = settings.quietStart.minutesSinceMidnight;
  final quietEnd = settings.quietEnd.minutesSinceMidnight;
  final quietOn = settings.quietHoursEnabled && quietStart != quietEnd;

  bool inQuiet(int m) {
    if (!quietOn) return false;
    return quietStart < quietEnd
        ? m >= quietStart && m < quietEnd
        : m >= quietStart || m < quietEnd;
  }

  /// Sessiz saat dışına aynı gün içinde taşır; taşınamazsa `null`.
  DateTime? place(DateTime day, HealthNudgeKind kind) {
    var minutes = kind.hour * 60 + kind.minute;
    if (inQuiet(minutes)) {
      minutes = quietEnd;
      // Bitiş daha erken bir saatse (gece yarısını aşan aralık) ertesi güne
      // düşer: o gün için atılır.
      if (minutes <= kind.hour * 60 + kind.minute || inQuiet(minutes)) {
        return null;
      }
    }
    final at =
        DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
    return at.isAfter(now) ? at : null;
  }

  final plan = <PlannedNotification>[];
  for (var offset = 0; offset < healthNudgeHorizonDays; offset++) {
    final day = AppDates.addDays(today, offset);
    final isToday = offset == 0;
    final candidates = <PlannedNotification>[];

    void add(HealthNudgeKind kind, String title, String body) {
      if (disabled.contains(kind)) return;
      final at = place(day, kind);
      if (at == null) return;
      final key = healthNudgeKey(kind, day);
      candidates.add(PlannedNotification(
        key: key,
        kind: PlannedKind.healthNudge,
        sourceId: key,
        title: title,
        body: body,
        fireAt: at,
      ));
    }

    if (settings.checkinReminder &&
        isCheckinDay(settings, day) &&
        !(isToday && state.checkinDoneToday)) {
      add(HealthNudgeKind.checkin, 'Ölçü ve fotoğraf günü',
          checkinNotificationBody);
    }

    final mealsLogged = state.mealsLoggedToday;
    if (isToday ? mealsLogged == false : mealsLogged != null) {
      add(HealthNudgeKind.meals, 'Bugünün öğünleri',
          'Bugün henüz öğün eklemedin. Tek cümle yazman yeter.');
    }

    if (isToday && stepsNudgeApplies(state.stepsToday, state.stepTarget)) {
      final left = state.stepTarget - state.stepsToday!;
      add(
          HealthNudgeKind.steps,
          'Adım hedefine az kaldı',
          'Hedefe ${_thousands.format(left)} adım kaldı. '
              'Kısa bir yürüyüş yeter.');
    }

    if (day.weekday == DateTime.sunday &&
        AppDates.weekStart(day) == AppDates.weekStart(today)) {
      final body = weeklyNudgeBody(state);
      if (body != null) add(HealthNudgeKind.weekly, 'Haftanın özeti', body);
    }

    plan.addAll(candidates.take(maxHealthNudgesPerDay));
  }
  plan.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return plan;
}

// ----------------------------------------------------------- tür anahtarları

/// Kullanıcının kapattığı dürtü türleri (cihazda saklanır). Ölçü günü
/// `user_settings.checkin_reminder` ile yönetilir; burada yalnızca diğerleri.
class HealthNudgePrefs extends AsyncNotifier<Set<HealthNudgeKind>> {
  static const String prefsKey = 'health_nudges_disabled';

  @override
  Future<Set<HealthNudgeKind>> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(prefsKey) ?? const [];
      return {
        for (final k in HealthNudgeKind.values)
          if (names.contains(k.name)) k,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> setEnabled(HealthNudgeKind kind, bool enabled) async {
    final current = {...?state.valueOrNull};
    enabled ? current.remove(kind) : current.add(kind);
    state = AsyncData(current);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      prefsKey,
      [for (final k in current) k.name],
    );
  }
}

final healthNudgePrefsProvider =
    AsyncNotifierProvider<HealthNudgePrefs, Set<HealthNudgeKind>>(
  HealthNudgePrefs.new,
);
