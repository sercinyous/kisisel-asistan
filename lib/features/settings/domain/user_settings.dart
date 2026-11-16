/// Gün içi saat (`time` sütunu). Flutter'ın `TimeOfDay`'inden bağımsızdır ki
/// alan katmanı arayüz kitaplığına bağlanmasın.
class TimeOfDayValue implements Comparable<TimeOfDayValue> {
  const TimeOfDayValue(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  /// "HH:mm" ya da Postgres'in "HH:mm:ss" biçimi; geçersizse `null`.
  static TimeOfDayValue? tryParse(Object? value) {
    if (value is! String) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDayValue(h, m);
  }

  /// "HH:mm"
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(TimeOfDayValue other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      other is TimeOfDayValue && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => format();
}

/// `user_settings` satırı: hedefler, bildirim tercihleri ve ekip.
/// Varsayılanlar ve sınırlar supabase/schema.sql ile aynıdır.
class UserSettings {
  const UserSettings({
    required this.startWeightKg,
    required this.targetWeightKg,
    required this.dailyCalories,
    required this.dailyProteinG,
    required this.dailyCarbsG,
    required this.dailyFatG,
    required this.dailySteps,
    required this.sleepMinutes,
    required this.notificationsEnabled,
    required this.routineNotifications,
    required this.monthlyLeadDays,
    required this.monthlyRemindTime,
    required this.eventRemindMinutes,
    required this.quietHoursEnabled,
    required this.quietStart,
    required this.quietEnd,
    required this.teamMembers,
  });

  const UserSettings.defaults()
      : startWeightKg = 84.5,
        targetWeightKg = 78,
        dailyCalories = 2000,
        dailyProteinG = 170,
        dailyCarbsG = 180,
        dailyFatG = 65,
        dailySteps = 10000,
        sleepMinutes = 450,
        notificationsEnabled = true,
        routineNotifications = true,
        monthlyLeadDays = 3,
        monthlyRemindTime = const TimeOfDayValue(9, 0),
        eventRemindMinutes = 30,
        quietHoursEnabled = true,
        quietStart = const TimeOfDayValue(23, 0),
        quietEnd = const TimeOfDayValue(7, 30),
        teamMembers = const ['Duhan', 'İlhan', 'Mehmet', 'Sedat'];

  final double startWeightKg;
  final double targetWeightKg;
  final int dailyCalories;
  final int dailyProteinG;
  final int dailyCarbsG;
  final int dailyFatG;
  final int dailySteps;
  final int sleepMinutes;

  /// Kapalıysa hiçbir bildirim planlanmaz.
  final bool notificationsEnabled;
  final bool routineNotifications;

  /// Aylık iş gününden kaç gün önce Gün ekranına ve bildirime düşer (0..14).
  final int monthlyLeadDays;
  final TimeOfDayValue monthlyRemindTime;

  /// `remind_at` verilmemiş randevu için terminden kaç dakika önce (0..1440).
  final int eventRemindMinutes;
  final bool quietHoursEnabled;
  final TimeOfDayValue quietStart;
  final TimeOfDayValue quietEnd;
  final List<String> teamMembers;

  /// Eksik ya da bozuk alanlar varsayılana düşer.
  factory UserSettings.fromMap(Map<String, dynamic> map) {
    const d = UserSettings.defaults();
    final team = map['team_members'];
    return UserSettings(
      startWeightKg:
          (map['start_weight_kg'] as num?)?.toDouble() ?? d.startWeightKg,
      targetWeightKg:
          (map['target_weight_kg'] as num?)?.toDouble() ?? d.targetWeightKg,
      dailyCalories: (map['daily_calories'] as num?)?.toInt() ?? d.dailyCalories,
      dailyProteinG:
          (map['daily_protein_g'] as num?)?.toInt() ?? d.dailyProteinG,
      dailyCarbsG: (map['daily_carbs_g'] as num?)?.toInt() ?? d.dailyCarbsG,
      dailyFatG: (map['daily_fat_g'] as num?)?.toInt() ?? d.dailyFatG,
      dailySteps: (map['daily_steps'] as num?)?.toInt() ?? d.dailySteps,
      sleepMinutes: (map['sleep_minutes'] as num?)?.toInt() ?? d.sleepMinutes,
      notificationsEnabled:
          map['notifications_enabled'] as bool? ?? d.notificationsEnabled,
      routineNotifications:
          map['routine_notifications'] as bool? ?? d.routineNotifications,
      monthlyLeadDays:
          (map['monthly_lead_days'] as num?)?.toInt() ?? d.monthlyLeadDays,
      monthlyRemindTime: TimeOfDayValue.tryParse(map['monthly_remind_time']) ??
          d.monthlyRemindTime,
      eventRemindMinutes: (map['event_remind_minutes'] as num?)?.toInt() ??
          d.eventRemindMinutes,
      quietHoursEnabled:
          map['quiet_hours_enabled'] as bool? ?? d.quietHoursEnabled,
      quietStart: TimeOfDayValue.tryParse(map['quiet_start']) ?? d.quietStart,
      quietEnd: TimeOfDayValue.tryParse(map['quiet_end']) ?? d.quietEnd,
      teamMembers: team is List
          ? team.whereType<String>().toList(growable: false)
          : d.teamMembers,
    );
  }

  /// Yazılabilir sütunlar (user_id ve updated_at hariç).
  Map<String, dynamic> toMap() => {
        'start_weight_kg': startWeightKg,
        'target_weight_kg': targetWeightKg,
        'daily_calories': dailyCalories,
        'daily_protein_g': dailyProteinG,
        'daily_carbs_g': dailyCarbsG,
        'daily_fat_g': dailyFatG,
        'daily_steps': dailySteps,
        'sleep_minutes': sleepMinutes,
        'notifications_enabled': notificationsEnabled,
        'routine_notifications': routineNotifications,
        'monthly_lead_days': monthlyLeadDays,
        'monthly_remind_time': monthlyRemindTime.format(),
        'event_remind_minutes': eventRemindMinutes,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_start': quietStart.format(),
        'quiet_end': quietEnd.format(),
        'team_members': teamMembers,
      };

  UserSettings copyWith({
    double? startWeightKg,
    double? targetWeightKg,
    int? dailyCalories,
    int? dailyProteinG,
    int? dailyCarbsG,
    int? dailyFatG,
    int? dailySteps,
    int? sleepMinutes,
    bool? notificationsEnabled,
    bool? routineNotifications,
    int? monthlyLeadDays,
    TimeOfDayValue? monthlyRemindTime,
    int? eventRemindMinutes,
    bool? quietHoursEnabled,
    TimeOfDayValue? quietStart,
    TimeOfDayValue? quietEnd,
    List<String>? teamMembers,
  }) =>
      UserSettings(
        startWeightKg: startWeightKg ?? this.startWeightKg,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        dailyCalories: dailyCalories ?? this.dailyCalories,
        dailyProteinG: dailyProteinG ?? this.dailyProteinG,
        dailyCarbsG: dailyCarbsG ?? this.dailyCarbsG,
        dailyFatG: dailyFatG ?? this.dailyFatG,
        dailySteps: dailySteps ?? this.dailySteps,
        sleepMinutes: sleepMinutes ?? this.sleepMinutes,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        routineNotifications: routineNotifications ?? this.routineNotifications,
        monthlyLeadDays: monthlyLeadDays ?? this.monthlyLeadDays,
        monthlyRemindTime: monthlyRemindTime ?? this.monthlyRemindTime,
        eventRemindMinutes: eventRemindMinutes ?? this.eventRemindMinutes,
        quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        teamMembers: teamMembers ?? this.teamMembers,
      );
}
