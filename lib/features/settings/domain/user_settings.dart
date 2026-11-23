import '../../../core/avatar/avatar_spec.dart';
import '../../operations/domain/task_category.dart';
import '../../health/domain/fat_loss_rate.dart' show FatLossRate;
import '../../health/domain/goal_mode.dart' show GainRate, GoalMode;
import 'activity_level.dart';

export '../../health/domain/fat_loss_rate.dart' show FatLossRate;
export 'activity_level.dart';

/// Günlük hedeflerin (kcal ve makrolar) son kaynağı (`targets_source`).
enum TargetsSource {
  /// İlk kurulumda plan motoruyla yazıldı.
  onboarding,

  /// Plan motoru (tempo değişimi, tartı, öneriyi uygulama) yazdı.
  plan,

  /// Kullanıcı Ayarlar > Hedeflerim'den elle yazdı; tartı hedefleri değiştirmez.
  manual;

  static TargetsSource parse(Object? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return TargetsSource.plan;
  }
}

/// Ölçü ve fotoğraf gününün sıklığı (`checkin_cadence`).
enum CheckinCadence {
  weekly,
  monthly;

  static CheckinCadence parse(Object? value) =>
      value == 'monthly' ? CheckinCadence.monthly : CheckinCadence.weekly;
}

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
    this.heightCm,
    this.birthYear,
    this.sex,
    this.displayName,
    this.workDescription,
    this.onboardedAt,
    this.taskCategoriesRaw,
    this.activityLevel,
    this.avatar = const AvatarChoice(),
    this.weeklyRate = FatLossRate.classic,
    this.expenditureKcalManual,
    this.mealCount = 3,
    this.targetsSource = TargetsSource.plan,
    this.targetsUpdatedAt,
    this.checkinCadence = CheckinCadence.weekly,
    this.checkinWeekday = 1,
    this.checkinMonthday = 1,
    this.checkinReminder = true,
    this.hidePhotos = false,
    this.healthPlanColumns = true,
    this.goalMode = GoalMode.fatLoss,
    this.gainRate = GainRate.slow,
    this.goalModeColumns = true,
  });

  const UserSettings.defaults()
      : startWeightKg = 70,
        targetWeightKg = 70,
        dailyCalories = 2000,
        dailyProteinG = 120,
        dailyCarbsG = 220,
        dailyFatG = 65,
        dailySteps = 8000,
        sleepMinutes = 450,
        notificationsEnabled = true,
        routineNotifications = true,
        monthlyLeadDays = 3,
        monthlyRemindTime = const TimeOfDayValue(9, 0),
        eventRemindMinutes = 30,
        quietHoursEnabled = true,
        quietStart = const TimeOfDayValue(23, 0),
        quietEnd = const TimeOfDayValue(7, 30),
        teamMembers = const [],
        heightCm = null,
        birthYear = null,
        sex = null,
        displayName = null,
        workDescription = null,
        onboardedAt = null,
        taskCategoriesRaw = null,
        activityLevel = null,
        avatar = const AvatarChoice(),
        weeklyRate = FatLossRate.classic,
        expenditureKcalManual = null,
        mealCount = 3,
        targetsSource = TargetsSource.plan,
        targetsUpdatedAt = null,
        checkinCadence = CheckinCadence.weekly,
        checkinWeekday = 1,
        checkinMonthday = 1,
        checkinReminder = true,
        hidePhotos = false,
        healthPlanColumns = true,
        goalMode = GoalMode.fatLoss,
        gainRate = GainRate.slow,
        goalModeColumns = true;

  /// Elle girilen günlük harcamanın sınırları (schema.sql check).
  static const int expenditureManualMin = 1200;
  static const int expenditureManualMax = 6000;

  /// Ayın ölçü günü en çok 28 (her ay var).
  static const int checkinMonthdayMax = 28;

  /// Profil alanlarının sınırları; supabase/schema.sql'deki check'lerle aynıdır.
  static const int heightCmMin = 100;
  static const int heightCmMax = 250;
  static const int birthYearMin = 1900;
  static const int birthYearMax = 2100;

  /// `display_name` ve `work_description` en çok bu kadar karakter (schema.sql).
  static const int displayNameMax = 60;
  static const int workDescriptionMax = 500;

  /// `sex` sütununun kabul ettiği değerler. `null` = henüz cevaplanmadı.
  static const List<String> sexValues = ['female', 'male', 'unspecified'];

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

  /// Profil (enerji dengesi için). Cevaplanmamışsa `null`.
  final int? heightCm;
  final int? birthYear;

  /// 'female' | 'male' | 'unspecified' | null.
  final String? sex;

  /// Arkadaşların seni göreceği ad; boşsa (`null`) maskelenmiş e-posta görünür.
  final String? displayName;

  /// "Ne iş yapıyorsun" cevabı; yalnızca AI komutuna girer, kimseyle
  /// paylaşılmaz. Boşsa `null`.
  final String? workDescription;

  /// İlk kurulumun (kılavuz ve sorular) bittiği an; `null` = henüz bitmedi.
  final DateTime? onboardedAt;

  /// Kullanıcının kaydettiği görev kategorileri; `null` = hiç düzenlenmedi
  /// (yerleşik liste geçerli ve sütun yazılmaz).
  final List<TaskCategory>? taskCategoriesRaw;

  /// Günlük hareket düzeyi (kalori önerisinin katsayısı); `null` = cevaplanmadı.
  final ActivityLevel? activityLevel;

  /// Profil avatarı. [toMap] bunu YAZMAZ: avatar yalnızca
  /// `SettingsRepository.saveAvatar` ile yazılır (sütunu henüz olmayan
  /// şemada diğer ayarların kaydı bozulmasın).
  final AvatarChoice avatar;

  /// Haftalık kayıp hızı (`weekly_rate`); varsayılan Klasik (kg × 26).
  final FatLossRate weeklyRate;

  /// Elle girilen günlük harcama (kcal); `null` = model tahmini kullanılır.
  final int? expenditureKcalManual;

  /// Günlük öğün sayısı (2 ya da 3); örnek menü ve eksik satırı paylaşır.
  final int mealCount;

  /// Günlük kcal/makro hedeflerinin kaynağı.
  final TargetsSource targetsSource;

  /// Hedeflerin son yazıldığı an; hiç yazılmadıysa `null`.
  final DateTime? targetsUpdatedAt;

  /// Ölçü ve fotoğraf günü: haftalık (ISO gün 1..7) ya da aylık (1..28).
  final CheckinCadence checkinCadence;
  final int checkinWeekday;
  final int checkinMonthday;

  /// Ölçü gününde 09:00 hatırlatması.
  final bool checkinReminder;

  /// İlerleme fotoğrafları dokunulana kadar bulanık gösterilir.
  final bool hidePhotos;

  /// Satır Sağlık v2 sütunlarını taşıyor mu? Şema henüz yükseltilmemişse
  /// (`weekly_rate` anahtarı yok) [toMap] bu sütunları yazmaz, böylece diğer
  /// ayarların kaydı bozulmaz.
  final bool healthPlanColumns;

  /// Hedef türü (`goal_mode`); varsayılan yağ yakma.
  final GoalMode goalMode;

  /// Kas yapma temposu (`gain_rate`); varsayılan yavaş (+250 kcal).
  final GainRate gainRate;

  /// Satır `goal_mode` sütununu taşıyor mu? Şema henüz yükseltilmemişse
  /// [toMap] `goal_mode`/`gain_rate` yazmaz.
  final bool goalModeColumns;

  /// Etkin görev kategorileri tanımı (kapalılar dahil).
  List<TaskCategory> get taskCategories =>
      taskCategoriesRaw ?? TaskCategory.defaults;

  /// Seçici, filtre ve AI için açık kategori adları.
  List<String> get activeTaskCategories =>
      TaskCategory.activeNames(taskCategories);

  /// İlk kurulum tamamlandı mı?
  bool get isOnboarded => onboardedAt != null;

  /// Boy, doğum yılı ve cinsiyetin üçü de dolu.
  bool get profileComplete =>
      heightCm != null && birthYear != null && sex != null;

  /// Eksik ya da bozuk alanlar varsayılana düşer; profil alanlarında varsayılan
  /// `null`'dır ve aralık dışı değer de `null` olur.
  factory UserSettings.fromMap(Map<String, dynamic> map) {
    const d = UserSettings.defaults();
    final team = map['team_members'];
    return UserSettings(
      startWeightKg:
          (map['start_weight_kg'] as num?)?.toDouble() ?? d.startWeightKg,
      targetWeightKg:
          (map['target_weight_kg'] as num?)?.toDouble() ?? d.targetWeightKg,
      dailyCalories:
          (map['daily_calories'] as num?)?.toInt() ?? d.dailyCalories,
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
      heightCm: _profileInt(map['height_cm'], heightCmMin, heightCmMax),
      birthYear: _profileInt(map['birth_year'], birthYearMin, birthYearMax),
      sex: _profileSex(map['sex']),
      displayName: _text(map['display_name'], displayNameMax),
      workDescription: _text(map['work_description'], workDescriptionMax),
      onboardedAt: _timestamp(map['onboarded_at']),
      taskCategoriesRaw: map['task_categories'] is List
          ? TaskCategory.parseList(map['task_categories'])
          : null,
      activityLevel: ActivityLevel.tryParse(map['activity_level']),
      avatar: AvatarChoice.fromMap(map),
      weeklyRate: FatLossRate.parse(map['weekly_rate'] as String?),
      goalMode: GoalMode.parse(map['goal_mode']),
      gainRate: GainRate.parse(map['gain_rate']),
      expenditureKcalManual: _profileInt(map['expenditure_kcal_manual'],
          expenditureManualMin, expenditureManualMax),
      mealCount: _profileInt(map['meal_count'], 2, 3) ?? d.mealCount,
      targetsSource: TargetsSource.parse(map['targets_source']),
      targetsUpdatedAt: _timestamp(map['targets_updated_at']),
      checkinCadence: CheckinCadence.parse(map['checkin_cadence']),
      checkinWeekday:
          _profileInt(map['checkin_weekday'], 1, 7) ?? d.checkinWeekday,
      checkinMonthday:
          _profileInt(map['checkin_monthday'], 1, checkinMonthdayMax) ??
              d.checkinMonthday,
      checkinReminder: map['checkin_reminder'] as bool? ?? d.checkinReminder,
      hidePhotos: map['hide_photos'] as bool? ?? d.hidePhotos,
    );
  }

  /// Boşluğu kırpılmış metin; metin değilse, boşsa ya da [max] karakteri
  /// aşıyorsa `null` (tanınmayan değer güvenle "yok" sayılır).
  static String? _text(Object? value, int max) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.runes.length > max) return null;
    return trimmed;
  }

  /// ISO 8601 metni (Postgres `timestamptz`) yerel zamana çevrilir; tanınmayan
  /// değer `null` olur.
  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// Tam sayı ve [min]..[max] aralığındaysa değer; aksi hâlde `null`.
  static int? _profileInt(Object? value, int min, int max) {
    if (value is! num || !value.isFinite || value != value.truncate()) {
      return null;
    }
    final n = value.toInt();
    return n < min || n > max ? null : n;
  }

  static String? _profileSex(Object? value) =>
      value is String && sexValues.contains(value) ? value : null;

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
        // Boş profil açıkça null yazılır: kullanıcı alanı temizleyebilsin.
        'height_cm': heightCm,
        'birth_year': birthYear,
        'sex': sex,
        // Boş metin null yazılır (kullanıcı temizleyebilsin).
        'display_name': displayName,
        'work_description': workDescription,
        // Yalnızca doluysa yazılır: eski bir kopyanın kaydı, tamamlanmış ilk
        // kurulumu geri alıp kullanıcıyı kılavuza döndürmesin.
        if (onboardedAt != null)
          'onboarded_at': onboardedAt!.toUtc().toIso8601String(),
        // Yalnızca kullanıcı düzenlediyse yazılır: sütunu henüz olmayan şemada
        // diğer ayarların kaydı bozulmasın.
        if (taskCategoriesRaw != null)
          'task_categories': TaskCategory.toJsonList(taskCategoriesRaw!),
        // Yalnızca seçildiyse yazılır (sütunu henüz olmayan şemada diğer
        // ayarların kaydı bozulmasın).
        if (activityLevel != null) 'activity_level': activityLevel!.dbValue,
        if (healthPlanColumns) ...{
          'weekly_rate': weeklyRate.dbValue,
          'expenditure_kcal_manual': expenditureKcalManual,
          'meal_count': mealCount,
          'targets_source': targetsSource.name,
          'targets_updated_at': targetsUpdatedAt?.toUtc().toIso8601String(),
          'checkin_cadence': checkinCadence.name,
          'checkin_weekday': checkinWeekday,
          'checkin_monthday': checkinMonthday,
          'checkin_reminder': checkinReminder,
          'hide_photos': hidePhotos,
        },
        if (goalModeColumns) ...{
          'goal_mode': goalMode.dbValue,
          'gain_rate': gainRate.dbValue,
        },
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
    int? heightCm,
    int? birthYear,
    String? sex,
    String? displayName,
    String? workDescription,
    DateTime? onboardedAt,
    List<TaskCategory>? taskCategories,
    ActivityLevel? activityLevel,
    AvatarChoice? avatar,
    bool clearHeightCm = false,
    bool clearBirthYear = false,
    bool clearSex = false,
    bool clearDisplayName = false,
    bool clearWorkDescription = false,
    FatLossRate? weeklyRate,
    int? expenditureKcalManual,
    bool clearExpenditureKcalManual = false,
    int? mealCount,
    TargetsSource? targetsSource,
    DateTime? targetsUpdatedAt,
    CheckinCadence? checkinCadence,
    int? checkinWeekday,
    int? checkinMonthday,
    bool? checkinReminder,
    bool? hidePhotos,
    bool? healthPlanColumns,
    GoalMode? goalMode,
    GainRate? gainRate,
    bool? goalModeColumns,
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
        heightCm: clearHeightCm ? null : (heightCm ?? this.heightCm),
        birthYear: clearBirthYear ? null : (birthYear ?? this.birthYear),
        sex: clearSex ? null : (sex ?? this.sex),
        displayName:
            clearDisplayName ? null : (displayName ?? this.displayName),
        workDescription: clearWorkDescription
            ? null
            : (workDescription ?? this.workDescription),
        onboardedAt: onboardedAt ?? this.onboardedAt,
        taskCategoriesRaw: taskCategories == null
            ? taskCategoriesRaw
            : TaskCategory.ensureActive(taskCategories),
        activityLevel: activityLevel ?? this.activityLevel,
        avatar: avatar ?? this.avatar,
        weeklyRate: weeklyRate ?? this.weeklyRate,
        expenditureKcalManual: clearExpenditureKcalManual
            ? null
            : (expenditureKcalManual ?? this.expenditureKcalManual),
        mealCount: mealCount ?? this.mealCount,
        targetsSource: targetsSource ?? this.targetsSource,
        targetsUpdatedAt: targetsUpdatedAt ?? this.targetsUpdatedAt,
        checkinCadence: checkinCadence ?? this.checkinCadence,
        checkinWeekday: checkinWeekday ?? this.checkinWeekday,
        checkinMonthday: checkinMonthday ?? this.checkinMonthday,
        checkinReminder: checkinReminder ?? this.checkinReminder,
        hidePhotos: hidePhotos ?? this.hidePhotos,
        healthPlanColumns: healthPlanColumns ?? this.healthPlanColumns,
        goalMode: goalMode ?? this.goalMode,
        gainRate: gainRate ?? this.gainRate,
        goalModeColumns: goalModeColumns ?? this.goalModeColumns,
      );
}
