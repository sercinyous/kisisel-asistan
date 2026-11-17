import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/health_repository.dart';
import '../domain/energy_balance.dart';
import 'trend_providers.dart' show trendClockProvider;

export '../domain/energy_balance.dart';

/// Son tartıyı ararken geriye bakılan gün sayısı. Bu pencerede hiç tartı
/// yoksa ayarlardaki başlangıç kilosu kullanılır.
const int energyWeightLookbackDays = 365;

/// Enerji aralığı sorgusu: iki uç dahil yerel günler.
typedef EnergyWindow = ({DateTime from, DateTime to});

/// Bir günün enerji dengesi. Profil (boy, doğum yılı, cinsiyet) eksikse
/// `null` döner; kart bu durumda profili doldurmaya yönlendirir.
///
/// Anahtar yerel gündür; "şimdi" [trendClockProvider]'dan okunur, böylece
/// bugün için bazal, günün geçen oranıyla ("şu ana kadar") hesaplanır.
final energyDayProvider =
    FutureProvider.family<EnergyDay?, DateTime>((ref, day) async {
  final days = await _energyDays(ref, day, day);
  return days.isEmpty ? null : days.first;
});

/// [EnergyWindow] aralığının günleri, eskiden yeniye: her takvim günü için bir
/// [EnergyDay]. Gelecek günler üretilmez (liste bugünde biter); profil
/// eksikse liste boştur. Öğünü olmayan gün [EnergyVerdict.noMeals] olarak
/// gelir ve toplamlara girmez ([summarize]).
final energyRangeProvider =
    FutureProvider.family<List<EnergyDay>, EnergyWindow>(
  (ref, window) => _energyDays(ref, window.from, window.to),
);

/// Enerji sağlayıcılarının önbelleğini boşaltır. Öğün, antrenman ya da kilo
/// değişince, uygulama öne gelince (gün değişmiş olabilir) ve sağlık verisi
/// yedeklenince çağrılır ([invalidateHealthData] bunu da çağırır). Kapsayıcı
/// alır, çünkü `await` sonrası `WidgetRef` kullanılamaz.
void invalidateEnergyData(ProviderContainer container) {
  container
    ..invalidate(energyDayProvider)
    ..invalidate(energyRangeProvider);
}

Future<List<EnergyDay>> _energyDays(
  Ref ref,
  DateTime from,
  DateTime to,
) async {
  // Ayarlar yüklenemezse hata kartta "yüklenemedi" olarak görünür: profil
  // için anlamlı bir varsayılan yoktur.
  final settings = await ref.watch(userSettingsProvider.future);
  final heightCm = settings.heightCm;
  final birthYear = settings.birthYear;
  final sex = Sex.tryParse(settings.sex);
  if (heightCm == null || birthYear == null || sex == null) return const [];

  final now = ref.watch(trendClockProvider)();
  final today = AppDates.startOfDay(now);
  final first = AppDates.startOfDay(from);
  final lastRequested = AppDates.startOfDay(to);
  final last = lastRequested.isAfter(today) ? today : lastRequested;
  if (first.isAfter(last)) return const [];

  final repository = ref.watch(healthRepositoryProvider);
  final metricsRead = repository.fetchDailyMetrics(first, last);
  final nutritionRead =
      repository.fetchNutritionTotals(first, AppDates.endOfDay(last));
  final workoutsRead =
      repository.fetchWorkouts(first, AppDates.endOfDay(last));
  final weightsRead = repository.fetchWeights(
    AppDates.addDays(first, -energyWeightLookbackDays),
    AppDates.endOfDay(last),
  );
  // Paralel okuma; ilk hata özgün türüyle iletilir, diğerleri sahipsiz kalmaz.
  await Future.wait<Object>([
    metricsRead,
    nutritionRead,
    workoutsRead,
    weightsRead,
  ]);

  final metrics = {
    for (final m in await metricsRead) AppDates.startOfDay(m.day): m,
  };
  final nutrition = {
    for (final n in await nutritionRead) AppDates.startOfDay(n.day): n,
  };
  final workoutKcal = <DateTime, int>{};
  for (final w in await workoutsRead) {
    final kcal = w.caloriesBurned ?? 0;
    if (kcal <= 0) continue;
    final day = AppDates.startOfDay(w.loggedAt);
    workoutKcal[day] = (workoutKcal[day] ?? 0) + kcal;
  }
  final weights = [...await weightsRead]
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  // Gün başına son tartı (o günün sonuna kadar); yoksa başlangıç kilosu.
  double weightOn(DateTime day) {
    final end = AppDates.endOfDay(day);
    var kg = settings.startWeightKg;
    for (final w in weights) {
      if (!w.loggedAt.isBefore(end)) break;
      kg = w.weightKg;
    }
    return kg;
  }

  return [
    for (var day = first; !day.isAfter(last); day = AppDates.addDays(day, 1))
      computeEnergyDay(
        day: day,
        now: now,
        weightKg: weightOn(day),
        heightCm: heightCm,
        birthYear: birthYear,
        sex: sex,
        mealEntryCount: nutrition[day]?.entryCount ?? 0,
        intakeKcal: nutrition[day]?.calories ?? 0,
        activeKcalFromMetrics: metrics[day]?.activeKcal,
        workoutKcal: workoutKcal[day] ?? 0,
      ),
  ];
}
