import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/domain/user_settings.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../data/health_repository.dart';
import '../../domain/energy_balance.dart';
import '../../domain/targets_engine.dart';
import '../energy_providers.dart' show energyWeightLookbackDays;
import '../health_providers.dart' show weightSeriesProvider;
import '../trend_providers.dart' show trendClockProvider;

export '../../domain/safe_targets.dart';
export '../../domain/targets_engine.dart';

/// Kokpit, Bugün, raporlar, Trend ve Gemini'nin okuduğu günlük hedefler
/// (yalnızca `user_settings`).
class DailyTargets {
  const DailyTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.steps,
    required this.sleepMinutes,
    required this.source,
    required this.updatedAt,
    required this.rate,
  });

  factory DailyTargets.of(UserSettings s) => DailyTargets(
        kcal: s.dailyCalories,
        proteinG: s.dailyProteinG,
        carbsG: s.dailyCarbsG,
        fatG: s.dailyFatG,
        steps: s.dailySteps,
        sleepMinutes: s.sleepMinutes,
        source: s.targetsSource,
        updatedAt: s.targetsUpdatedAt,
        rate: s.weeklyRate,
      );

  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int steps;
  final int sleepMinutes;
  final TargetsSource source;
  final DateTime? updatedAt;
  final FatLossRate rate;

  @override
  bool operator ==(Object other) =>
      other is DailyTargets &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG &&
      other.steps == steps &&
      other.sleepMinutes == sleepMinutes &&
      other.source == source &&
      other.updatedAt == updatedAt &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG, steps,
      sleepMinutes, source, updatedAt, rate);
}

/// Ayarlar yüklenene kadar varsayılanlar (ekranlar beklemeden çizilir).
final targetsProvider = Provider<DailyTargets>(
  (ref) => DailyTargets.of(ref.watch(settingsOrDefaultProvider)),
);

/// Son tartı (son [energyWeightLookbackDays] gün); yoksa `null`. Tek kilo
/// kaynağı [weightSeriesProvider]'dır.
final latestWeightProvider = FutureProvider<WeightEntry?>((ref) async {
  final series =
      await ref.watch(weightSeriesProvider(energyWeightLookbackDays).future);
  if (series.isEmpty) return null;
  return series.reduce((a, b) => b.loggedAt.isBefore(a.loggedAt) ? a : b);
});

/// Motorun bugünkü ayar ve son tartıyla ürettiği hedefler (yazmaz). Plan
/// ekranı, öneri satırı ve seriler bunu okur.
final resolvedTargetsProvider = FutureProvider<ResolvedTargets>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final weight = await ref.watch(latestWeightProvider.future);
  final now = ref.watch(trendClockProvider)();
  return resolveTargets(
    settings: settings,
    latestWeightKg: weight?.weightKg,
    age: ageFromSettings(settings, now),
    sex: Sex.tryParse(settings.sex),
  );
});

/// Kaynak 'manual' iken kiloya göre önerilen hedef ("Kilona göre önerilen
/// 1.820 kcal [Uygula]"); yoksa `null`.
final planSuggestionProvider = FutureProvider<ResolvedTargets?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final resolved = await ref.watch(resolvedTargetsProvider.future);
  return planSuggestion(settings, resolved);
});

final planControllerProvider = Provider<PlanController>(PlanController.new);

/// Hedef ve plan ayarlarının yazarı. `daily_*` sütunlarını yalnızca
/// [applyPlan] (motor) ve [saveManualTargets] (Ayarlar > Hedeflerim) yazar.
class PlanController {
  PlanController(this._ref);

  final Ref _ref;

  DateTime _now() => _ref.read(trendClockProvider)();

  Future<UserSettings> _settings() =>
      _ref.read(userSettingsProvider.future);

  Future<UserSettings> _save(UserSettings next) =>
      _ref.read(userSettingsProvider.notifier).save(next);

  /// Motoru çalıştırır ve gerekiyorsa hedefleri yazar. [rate] verilirse
  /// tempo da değişir. [weightKg] verilirse son tartı yerine o kullanılır
  /// (kayıt hemen ardından, seri yenilenmeden çağrılınca). Yazma yoksa
  /// `null` döner; varsa snackbar metni [PlanWrite.message].
  Future<PlanWrite?> applyPlan(
    PlanTrigger trigger, {
    FatLossRate? rate,
    double? weightKg,
  }) async {
    final current = await _settings();
    final settings = rate == null ? current : current.copyWith(weeklyRate: rate);
    final weight = weightKg ??
        (await _ref.read(latestWeightProvider.future))?.weightKg;
    final now = _now();
    final resolved = resolveTargets(
      settings: settings,
      latestWeightKg: weight,
      age: ageFromSettings(settings, now),
      sex: Sex.tryParse(settings.sex),
    );
    final write = planWrite(
      settings: settings,
      resolved: resolved,
      trigger: trigger,
      now: now,
    );
    if (write == null) {
      if (rate != null && rate != current.weeklyRate) await _save(settings);
      return null;
    }
    await _save(write.settings);
    return write;
  }

  /// Ayarlar > Hedeflerim: değerler aynen yazılır, kaynak 'manual'.
  Future<UserSettings> saveManualTargets({
    required int kcal,
    required int proteinG,
    required int carbsG,
    required int fatG,
    int? steps,
    int? sleepMinutes,
  }) async {
    final s = await _settings();
    return _save(manualTargets(
      s.copyWith(dailySteps: steps, sleepMinutes: sleepMinutes),
      kcal: kcal,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      now: _now(),
    ));
  }

  /// Elle harcama (`null` = model tahmini). Kaynak 'manual' değilse hedefler
  /// yeni harcamayla yeniden yazılır.
  Future<void> setExpenditureManual(int? kcal) async {
    final s = await _settings();
    final next = kcal == null
        ? s.copyWith(clearExpenditureKcalManual: true)
        : s.copyWith(
            expenditureKcalManual: kcal
                .clamp(UserSettings.expenditureManualMin,
                    UserSettings.expenditureManualMax)
                .toInt(),
          );
    await _save(next);
    if (next.targetsSource != TargetsSource.manual) {
      await applyPlan(PlanTrigger.rateChanged);
    }
  }

  Future<void> setMealCount(int count) async {
    final s = await _settings();
    await _save(s.copyWith(mealCount: count.clamp(2, 3).toInt()));
  }

  Future<void> setCheckinSchedule({
    CheckinCadence? cadence,
    int? weekday,
    int? monthday,
    bool? reminder,
  }) async {
    final s = await _settings();
    await _save(s.copyWith(
      checkinCadence: cadence,
      checkinWeekday: weekday?.clamp(1, 7).toInt(),
      checkinMonthday:
          monthday?.clamp(1, UserSettings.checkinMonthdayMax).toInt(),
      checkinReminder: reminder,
    ));
  }

  Future<void> setHidePhotos(bool hide) async {
    final s = await _settings();
    await _save(s.copyWith(hidePhotos: hide));
  }
}

/// Eski cihaz tercihlerinin anahtarları (yağ yakımı ekranı). Yalnızca bir kez
/// [migrateLegacyFatLossPrefs] okur, `user_settings`'e taşır ve siler.
const String legacyFatLossRateKey = 'fat_loss_rate';
const String legacyFatLossExpenditureKey = 'fat_loss_expenditure_kcal';
const String legacyFatLossManualModeKey = 'fat_loss_expenditure_manual';

/// Eski tercihlerden taşınacak alanlar; taşınacak bir şey yoksa `null`.
/// Sunucudaki değer varsayılandan farklıysa (başka cihazda seçilmiş) ona
/// dokunulmaz.
UserSettings? legacyPrefsMerge(
  UserSettings settings, {
  String? rate,
  int? expenditure,
  bool? manualMode,
}) {
  var next = settings;
  if (rate != null && settings.weeklyRate == FatLossRate.classic) {
    next = next.copyWith(weeklyRate: FatLossRate.parse(rate));
  }
  if (manualMode == true &&
      expenditure != null &&
      settings.expenditureKcalManual == null) {
    next = next.copyWith(
      expenditureKcalManual: expenditure
          .clamp(UserSettings.expenditureManualMin,
              UserSettings.expenditureManualMax)
          .toInt(),
    );
  }
  final changed = next.weeklyRate != settings.weeklyRate ||
      next.expenditureKcalManual != settings.expenditureKcalManual;
  return changed ? next : null;
}

/// Uygulama açılışında bir kez: eski SharedPreferences anahtarlarını okur,
/// `user_settings`'e yazar ve anahtarları siler. Şema henüz yükseltilmediyse
/// ([UserSettings.healthPlanColumns] false) hiçbir şey yapmaz.
final legacyFatLossPrefsMigrationProvider = FutureProvider<void>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!settings.healthPlanColumns) return;
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } on Object {
    return;
  }
  final rate = prefs.getString(legacyFatLossRateKey);
  final expenditure = prefs.getInt(legacyFatLossExpenditureKey);
  final manual = prefs.getBool(legacyFatLossManualModeKey);
  if (rate == null && expenditure == null && manual == null) return;
  final merged = legacyPrefsMerge(
    settings,
    rate: rate,
    expenditure: expenditure,
    manualMode: manual,
  );
  if (merged != null) {
    await ref.read(userSettingsProvider.notifier).save(merged);
  }
  await prefs.remove(legacyFatLossRateKey);
  await prefs.remove(legacyFatLossExpenditureKey);
  await prefs.remove(legacyFatLossManualModeKey);
});
