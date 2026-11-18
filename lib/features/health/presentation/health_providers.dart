import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../routines/data/routines_repository.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import '../data/health_repository.dart';
import 'energy_providers.dart';
import 'health_source_providers.dart';
import 'water_providers.dart';

export '../data/health_repository.dart';
export 'health_source_providers.dart';

/// Kilo grafiğinin seçilebilir pencereleri (gün).
const List<int> weightSeriesWindows = [30, 90];

/// Bugünle biten son N günün kilo ölçümleri, eskiden yeniye.
/// Anahtar gün sayısıdır ([weightSeriesWindows]).
final weightSeriesProvider =
    FutureProvider.family<List<WeightEntry>, int>((ref, days) {
  final today = AppDates.startOfDay(DateTime.now());
  return ref.watch(healthRepositoryProvider).fetchWeights(
        AppDates.addDays(today, -(days - 1)),
        AppDates.endOfDay(today),
      );
});

/// Bir günün öğün kayıtları, saat sırasıyla. Anahtar yerel gün başı olmalıdır.
final dayNutritionLogsProvider =
    FutureProvider.family<List<NutritionLog>, DateTime>(
  (ref, day) => ref
      .watch(healthRepositoryProvider)
      .fetchNutritionLogs(AppDates.startOfDay(day)),
);

/// Antrenman günlüğünün geriye baktığı gün sayısı.
const int recentWorkoutsDays = 30;

/// Son [recentWorkoutsDays] günün antrenmanları, yeniden eskiye.
final recentWorkoutsProvider = FutureProvider<List<WorkoutLog>>((ref) {
  final today = AppDates.startOfDay(DateTime.now());
  return ref.watch(healthRepositoryProvider).fetchWorkouts(
        AppDates.addDays(today, -(recentWorkoutsDays - 1)),
        AppDates.endOfDay(today),
      );
});

/// Haftanın bir günü: o güne planlı spor rutinleri ve yapılan antrenmanlar.
class WorkoutPlanDay {
  const WorkoutPlanDay({
    required this.date,
    this.planned = const [],
    this.done = const [],
  });

  /// Yerel gün (gece yarısı).
  final DateTime date;

  /// O gün planlı spor rutinleri (category = 'spor').
  final List<Routine> planned;

  /// O gün kaydedilen antrenmanlar, saat sırasıyla.
  final List<WorkoutLog> done;

  bool get isPlanned => planned.isNotEmpty;
  bool get isDone => done.isNotEmpty;
}

/// Bu haftanın (Pzt–Paz) antrenman planı ve gerçekleşeni.
class WeekWorkoutPlan {
  const WeekWorkoutPlan({required this.weekStart, required this.days});

  /// Haftanın Pazartesi'si.
  final DateTime weekStart;

  /// Pazartesi'den Pazar'a 7 gün.
  final List<WorkoutPlanDay> days;

  /// Hafta boyunca planlı spor rutini sayısı.
  int get plannedCount => days.fold(0, (sum, d) => sum + d.planned.length);

  /// Hafta boyunca yapılan antrenman sayısı.
  int get doneCount => days.fold(0, (sum, d) => sum + d.done.length);
}

/// [weekStart] haftasının planını kurar. Kurallar rapor fonksiyonuyla
/// (supabase/schema.sql `report_period_metrics`) aynıdır: aktif spor rutinleri;
/// haftalıkta `daysOfWeek`, aylıkta günü o haftaya düşüyorsa; rutin
/// oluşturulduğu günden önce planlı sayılmaz.
WeekWorkoutPlan buildWeekWorkoutPlan(
  Iterable<Routine> routines,
  Iterable<WorkoutLog> workouts,
  DateTime weekStart,
) {
  final monday = AppDates.weekStart(weekStart);
  final sport =
      routines.where((r) => r.isActive && r.category == 'spor').toList();

  bool plannedOn(Routine r, DateTime day) {
    final created = r.createdAt;
    if (created != null && day.isBefore(AppDates.startOfDay(created))) {
      return false;
    }
    return r.isMonthly
        ? monthlyDueDate(r, day.year, day.month) == day
        : r.daysOfWeek.contains(day.weekday);
  }

  return WeekWorkoutPlan(
    weekStart: monday,
    days: [
      for (var i = 0; i < 7; i++)
        () {
          final day = AppDates.addDays(monday, i);
          return WorkoutPlanDay(
            date: day,
            planned: [
              for (final r in sport)
                if (plannedOn(r, day)) r,
            ],
            done: [
              for (final w in workouts)
                if (AppDates.startOfDay(w.loggedAt) == day) w,
            ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt)),
          );
        }(),
    ],
  );
}

/// Bu haftanın planlı spor rutinleri ve yapılan antrenmanlar.
final weekWorkoutPlanProvider = FutureProvider<WeekWorkoutPlan>((ref) async {
  final monday = AppDates.weekStart(DateTime.now());
  final routinesFuture = ref.watch(routinesRepositoryProvider).fetchActive();
  final workoutsFuture = ref
      .watch(healthRepositoryProvider)
      .fetchWorkouts(monday, AppDates.addDays(monday, 7));
  // Paralel okuma; ilk hata özgün türüyle iletilir, diğeri sahipsiz kalmaz.
  await Future.wait<Object>([routinesFuture, workoutsFuture]);
  return buildWeekWorkoutPlan(
    await routinesFuture,
    await workoutsFuture,
    monday,
  );
});

/// Bugünle biten son 7 günün HealthKit özeti; eskiden yeniye tam 7 kalem
/// (kaydı olmayan gün sıfırlarla doldurulur).
final weekStepsProvider = FutureProvider<List<DailyHealthMetric>>((ref) async {
  final today = AppDates.startOfDay(DateTime.now());
  final from = AppDates.addDays(today, -6);
  final rows = await ref.watch(healthRepositoryProvider).fetchDailyMetrics(
        from,
        today,
        source: ref.watch(healthSourceProvider),
      );
  final byDay = {for (final m in rows) AppDates.startOfDay(m.day): m};
  return [
    for (var i = 0; i < 7; i++)
      byDay[AppDates.addDays(from, i)] ??
          DailyHealthMetric(day: AppDates.addDays(from, i)),
  ];
});

/// Verisi olan günlerin adım ortalaması; hiç veri yoksa `null`.
int? averageSteps(Iterable<DailyHealthMetric> days) {
  final withData = days.where((d) => d.steps > 0).toList();
  if (withData.isEmpty) return null;
  return (withData.fold<int>(0, (sum, d) => sum + d.steps) / withData.length)
      .round();
}

/// Sağlık kaydı (öğün, antrenman, kilo) yazıldıktan sonra bu verileri
/// gösteren tüm sağlayıcıları tazeler: Sağlık sekmesi, Kokpit'in beslenme
/// özeti, Ay özeti ve Enerji dengesi. await sonrası `WidgetRef`
/// kullanılamayacağı için kapsayıcı alır
/// (`ProviderScope.containerOf(context, listen: false)`).
/// Bu sağlayıcılar pencerelerini "bugün"e göre açtığı için uygulama öne
/// geldiğinde de çağrılır (gün değişmiş olabilir).
void invalidateHealthData(ProviderContainer container) {
  container
    ..invalidate(weightSeriesProvider)
    ..invalidate(dayNutritionLogsProvider)
    ..invalidate(recentWorkoutsProvider)
    ..invalidate(weekWorkoutPlanProvider)
    ..invalidate(todayNutritionProvider)
    ..invalidate(monthOverviewProvider)
    ..invalidate(waterTodayProvider);
  // Enerji dengesi öğün, antrenman, kilo ve günlük sağlık özetinden hesaplanır;
  // "bugün" ve bazal oranı da saate bağlıdır.
  invalidateEnergyData(container);
}

/// Seçili kaynağın (HealthKit ya da Google Health) son
/// [HealthService.backfillDays] tamamlanmış gününü gün sonu değerleriyle
/// yeniden yedekler. Bugünün okuması günü ancak o ana kadar görür; gün
/// bittikten sonra kimse yeniden okumazsa raporlar, 7 günlük adım grafiği ve
/// Ay ortalamaları eksik kalır. Google seçiliyse aynı dönemin antrenmanları
/// da `fitness_logs`'a aktarılır. Bitince bu satırları okuyan sağlayıcılar
/// tazelenir (bugünün yedeği de o zamana dek yazılmıştır).
/// Uygulama açılışında çağrılır; öne gelişte ve elle yenilemede
/// [resyncHealthKit] kullanılır.
Future<void> backfillHealthKit(ProviderContainer container) async {
  pushHealthSourceToServer(container);
  var workoutsImported = false;
  try {
    // Kullanıcı, kaynak ve Google bağlantısı işlem başında sabitlenir; her
    // await sonrası hâlâ geçerli mi bakılır (çıkış/başka hesap, kaynak ya da
    // Google hesabı değiştiyse okunan değerler yazılmaz).
    final guard = HealthWriteGuard.capture(container.read);
    // Bugünün okuması ve yedeği bitsin; izin penceresi de orada açılır.
    final today = await container.read(healthTodayProvider.future);
    if (guard != null &&
        guard.isValid &&
        today.status == HealthStatus.ok &&
        today.source == guard.source) {
      final repository = guard.repository;
      if (today.source == HealthSourceKind.googleHealth) {
        final google = container.read(googleHealthSourceProvider);
        final days = await google.readPastDays();
        if (guard.isValid) {
          await repository.upsertHealthDays(days, ownerId: guard.ownerId);
          if (guard.isValid) {
            workoutsImported = await google.importWorkouts(
                  repository,
                  ownerId: guard.ownerId,
                  isValid: () => guard.isValid,
                ) >
                0;
          }
        }
      } else {
        // Onay denetimli kaynak: bu kullanıcı onay vermediyse HealthKit
        // okunmaz (boş liste); yazma da [HealthWriteGuard] ile engellenir.
        final days =
            await container.read(healthDataSourceProvider).readPastDays();
        if (guard.isValid) {
          await repository.upsertHealthDays(days, ownerId: guard.ownerId);
        }
      }
    }
  } catch (_) {
    // Okuma hatası kartta gösterilir; yedekleme hatası ekranı bozmaz.
  }
  try {
    container
      ..invalidate(weekStepsProvider)
      ..invalidate(monthOverviewProvider);
    // Yedeklenen aktif kalori ve antrenmanlar enerji dengesine girer.
    invalidateEnergyData(container);
    if (workoutsImported) {
      container
        ..invalidate(recentWorkoutsProvider)
        ..invalidate(weekWorkoutPlanProvider);
    }
  } on StateError {
    // Okuma sürerken kapsayıcı kapanmış (çıkış, test sonu).
  }
}

/// Seçili kaynağı yeniden okur (bugün + son günler) ve yedekler; bitince 7
/// günlük adım grafiği ile Ay ortalamaları tazelenir. `healthTodayProvider`
/// doğrudan tazelenirse bu ikisi yedeklenen yeni satırı görmez; onun yerine
/// bu çağrılır.
Future<void> resyncHealthKit(ProviderContainer container) {
  container.invalidate(healthTodayProvider);
  return backfillHealthKit(container);
}

/// Sağlık verisi kaynağını değiştirir ve yeni kaynaktan bugünü ve son
/// günleri yeniden okuyup yazar (eski kaynağın satırlarının üstüne). Aynı
/// anda tek kaynak okunduğu için değerler çift sayılmaz.
Future<void> selectHealthSource(
  ProviderContainer container,
  HealthSourceKind kind,
) async {
  final selection = container.read(healthSourceProvider.notifier);
  if (selection.current == kind) return;
  await selection.select(kind);
  if (selection.current != kind) return;
  pushHealthSourceToServer(container);
  await resyncHealthKit(container);
}

/// Seçili kaynağı sunucuya yazar (`user_settings.health_source`): raporlar ve
/// arkadaş sıralaması grafikle aynı kaynağı okur. Açılışta (eşitleme) ve
/// seçim değişince çağrılır; beklenmez, hata akışı durdurmaz (sonraki
/// açılışta yeniden yazılır).
void pushHealthSourceToServer(ProviderContainer container) {
  try {
    final repository = container.read(healthRepositoryProvider);
    final owner = repository.currentUserId;
    if (owner == null) return;
    repository
        .saveHealthSource(container.read(healthSourceProvider), ownerId: owner)
        .catchError((Object _) {});
  } catch (_) {
    // Kapsayıcı kapanmış ya da Supabase başlatılmamış (testler).
  }
}

/// Oturumdaki kullanıcının Apple Health verisinin kendi hesabına aktarılmasına
/// onay verir ve hemen eşitler. Yalnızca kullanıcı dokunuşuyla çağrılır;
/// cihazdaki HealthKit izni tek başına onay sayılmaz. Oturum yoksa `false`.
Future<bool> approveAppleHealth(ProviderContainer container) async {
  final owner = container.read(healthRepositoryProvider).currentUserId;
  if (owner == null) return false;
  await container.read(appleHealthConsentProvider.notifier).grant(owner);
  if (container.read(healthSourceProvider) == HealthSourceKind.appleHealth) {
    await resyncHealthKit(container);
  }
  return true;
}

/// Google giriş penceresini açar; başarıda Google seçiliyse hemen eşitler.
/// Gösterilecek hata metnini döndürür (başarıda ve kullanıcı vazgeçince
/// `null`). Yalnızca kullanıcı dokunuşuyla çağrılır.
Future<String?> connectGoogleHealth(ProviderContainer container) async {
  try {
    await container.read(googleConnectionProvider.notifier).connect();
  } on GoogleAuthException catch (error) {
    return error.kind == GoogleAuthErrorKind.canceled ? null : error.message;
  }
  if (container.read(healthSourceProvider) == HealthSourceKind.googleHealth) {
    await resyncHealthKit(container);
  }
  return null;
}

/// Google bağlantısını keser. Google seçiliyse kartlar "bağlı değil"
/// durumunu göstersin diye okuma yenilenir; kayıtlı değerler silinmez.
Future<void> disconnectGoogleHealth(ProviderContainer container) async {
  await container.read(googleConnectionProvider.notifier).disconnect();
  if (container.read(healthSourceProvider) == HealthSourceKind.googleHealth) {
    await resyncHealthKit(container);
  }
}
