import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_source.dart' show healthSourceProvider;
import '../../../core/services/notification_sync.dart';
import '../../../core/utils/date_utils.dart';
import '../../health/data/health_repository.dart';
import '../../operations/data/tasks_repository.dart';
import '../../operations/domain/task_item.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/routines_repository.dart';
import '../domain/routine.dart';

/// Aktif rutin tanımları (günlük, haftalık, aylık).
final activeRoutinesProvider = FutureProvider<List<Routine>>(
  (ref) => ref.watch(routinesRepositoryProvider).fetchActive(),
);

/// Gün ekranının rutin içeriği.
class TodayOccurrences {
  const TodayOccurrences({required this.daily, required this.monthly});

  /// Bugüne düşen günlük/haftalık rutinler.
  final List<RoutineOccurrence> daily;

  /// Penceresi açılmış ya da gecikmiş aylık işler.
  final List<RoutineOccurrence> monthly;
}

/// Bugünün rutinleri; işaretlemeler iyimser (optimistic) uygulanır.
final todayOccurrencesProvider =
    AsyncNotifierProvider<TodayOccurrencesNotifier, TodayOccurrences>(
  TodayOccurrencesNotifier.new,
);

class TodayOccurrencesNotifier extends AsyncNotifier<TodayOccurrences> {
  /// Yazması süren işaretlemeler (dönem → hedef durum). Notifier örneği
  /// invalidate sonrası da yaşadığı için eşzamanlı bir yenileme bu değerleri ezemez.
  final Map<RoutineCompletionKey, bool> _overrides = {};

  /// Her yazma bittiğinde artar; yazmadan önce başlamış bir okuma bayat sayılır.
  int _writeSeq = 0;

  // Son başarılı okumanın ham verisi: iyimser durum buradan yeniden hesaplanır.
  List<Routine> _routines = const [];
  Set<RoutineCompletionKey> _completions = {};
  DateTime _today = AppDates.startOfDay(DateTime.now());
  int _leadDays = 0;

  TodayOccurrences _compose() {
    final completions = {..._completions};
    _overrides.forEach((key, completed) {
      completions.remove(key);
      if (completed) completions.add(key);
    });
    return TodayOccurrences(
      daily: occurrencesForDay(_routines, completions, _today),
      monthly: monthlyForDay(_routines, completions, _today, _leadDays),
    );
  }

  @override
  Future<TodayOccurrences> build() async {
    final repository = ref.watch(routinesRepositoryProvider);
    final leadDays = ref.watch(
      settingsOrDefaultProvider.select((s) => s.monthlyLeadDays),
    );
    while (true) {
      final seq = _writeSeq;
      final today = AppDates.startOfDay(DateTime.now());
      final routines = await repository.fetchActive();
      // Bu ayın 1'i (aylık dönem anahtarı) ile gelecek ayın 1'i (ay sınırını
      // aşan pencere) arası; bugünün günlük kayıtları da bu aralıktadır.
      final completions = await repository.fetchCompletions(
        DateTime(today.year, today.month),
        DateTime(today.year, today.month + 1),
      );
      // Okuma sürerken bir yazma bittiyse sonuç o yazmadan eski olabilir.
      if (seq != _writeSeq && _overrides.isEmpty) continue;
      _routines = routines;
      _completions = completions;
      _today = today;
      _leadDays = leadDays;
      return _compose();
    }
  }

  /// İyimser güncelleme. Başarısız olursa yalnızca bu kalem, GÜNCEL liste
  /// üzerinde geri alınır ve hata çağırana iletilir.
  Future<void> toggle(RoutineOccurrence occurrence) async {
    if (!state.hasValue) return;
    final target = !occurrence.completed;
    final key = RoutineCompletionKey(
      occurrence.routine.id,
      occurrence.periodKey,
      completedAt: DateTime.now(),
    );
    // Aynı dönem için yazma sürüyorsa ikinci dokunuş yok sayılır.
    if (_overrides.containsKey(key)) return;

    _overrides[key] = target;
    state = AsyncData(_compose());

    try {
      await ref.read(routinesRepositoryProvider).setCompleted(
            routineId: key.routineId,
            periodKey: key.periodKey,
            completed: target,
          );
      _completions.remove(key);
      if (target) _completions.add(key);
      _overrides.remove(key);
      _writeSeq++;
    } catch (_) {
      _overrides.remove(key);
      _writeSeq++;
      if (state.hasValue) state = AsyncData(_compose());
      rethrow;
    }
    // Ay ekranı aynı kayıtları gösterir; aylık işin bildirimi de duruma bağlıdır.
    ref.invalidate(monthOverviewProvider);
    if (occurrence.routine.isMonthly) ref.invalidate(notificationSyncProvider);
  }
}

/// Ay ekranının tüm verisi.
class MonthOverview {
  const MonthOverview({
    required this.month,
    required this.monthly,
    required this.tasks,
    required this.weeklyPlanned,
    required this.weeklyDone,
    required this.health,
  });

  /// Ayın 1'i.
  final DateTime month;

  /// O ayın aylık işleri (bkz. `monthlyForMonth`).
  final List<RoutineOccurrence> monthly;

  /// Takvim anı bu aya düşen görev/randevular (tamamlananlar dahil).
  final List<TaskItem> tasks;

  /// Günlük/haftalık rutinlerin ay içinde (bugüne kadar) planlanan ve
  /// tamamlanan sayısı.
  final int weeklyPlanned;
  final int weeklyDone;
  final MonthHealthSummary health;

  int get tasksDone => tasks.where((t) => t.isDone).length;
}

/// Anahtar ayın herhangi bir günü olabilir; ayın 1'ine indirgenir.
/// Aynı ayı farklı günlerle istemek ayrı önbellek girdisi açmasın diye
/// çağıranlar ayın 1'ini vermelidir.
final monthOverviewProvider =
    FutureProvider.family<MonthOverview, DateTime>((ref, anyDay) async {
  final month = DateTime(anyDay.year, anyDay.month);
  final nextMonth = DateTime(month.year, month.month + 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  final today = AppDates.startOfDay(DateTime.now());

  final routinesRepository = ref.watch(routinesRepositoryProvider);
  final tasksRepository = ref.watch(tasksRepositoryProvider);
  final healthRepository = ref.watch(healthRepositoryProvider);

  final routinesFuture = routinesRepository.fetchActive();
  final completionsFuture = routinesRepository.fetchCompletions(month, lastDay);
  final tasksFuture = tasksRepository.fetchInRange(month, nextMonth);
  final metricsFuture = healthRepository.fetchDailyMetrics(
    month,
    lastDay,
    source: ref.watch(healthSourceProvider),
  );
  final nutritionFuture =
      healthRepository.fetchNutritionTotals(month, nextMonth);
  final weightsFuture = healthRepository.fetchWeights(month, nextMonth);
  // Paralel okuma. Future.wait ilk hatayı özgün türüyle iletir (ekranlar
  // PostgrestException'ı ayırt edebilsin) ve diğer hataları sahipsiz bırakmaz.
  await Future.wait<Object>([
    routinesFuture,
    completionsFuture,
    tasksFuture,
    metricsFuture,
    nutritionFuture,
    weightsFuture,
  ]);
  final routines = await routinesFuture;
  final completions = await completionsFuture;
  final tasks = await tasksFuture;
  final metrics = await metricsFuture;
  final nutrition = await nutritionFuture;
  final weights = await weightsFuture;

  // Henüz gelmemiş günler "planlandı" sayılmaz; yoksa oran ay sonuna kadar
  // haksız yere düşük görünür.
  final statsEnd = lastDay.isAfter(today) ? today : lastDay;
  final weekly = statsEnd.isBefore(month)
      ? (planned: 0, done: 0)
      : weeklyStatsForRange(routines, completions, month, statsEnd);

  return MonthOverview(
    month: month,
    monthly: monthlyForMonth(
      routines,
      completions,
      month.year,
      month.month,
      today,
    ),
    tasks: tasks,
    weeklyPlanned: weekly.planned,
    weeklyDone: weekly.done,
    health: MonthHealthSummary.from(
      metrics: metrics,
      nutrition: nutrition,
      weights: weights,
    ),
  );
});

/// Ay ekranından aylık işi işaretler ya da işareti kaldırır; ardından Gün ve
/// Ay verisini, bildirim planını tazeler. Hata çağırana iletilir.
Future<void> toggleMonthly(WidgetRef ref, RoutineOccurrence occurrence) async {
  // Yazma sürerken ekran kapanabilir; await sonrası WidgetRef kullanılamaz.
  final container = ProviderScope.containerOf(ref.context, listen: false);
  await container.read(routinesRepositoryProvider).setCompleted(
        routineId: occurrence.routine.id,
        periodKey: occurrence.periodKey,
        completed: !occurrence.completed,
      );
  container
    ..invalidate(monthOverviewProvider)
    ..invalidate(todayOccurrencesProvider)
    ..invalidate(notificationSyncProvider);
}
