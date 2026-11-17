import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../health/data/health_repository.dart';
import '../../health/presentation/health_source_providers.dart';
import '../../operations/data/tasks_repository.dart';
import '../../operations/domain/task_item.dart';
import '../data/kokpit_repository.dart';
import '../domain/kokpit_models.dart';

/// Kokpit başlığındaki tarih/selamlama için "şimdi". Uygulama öne geldiğinde
/// ve aşağı çekip yenilemede güncellenir.
final kokpitClockProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Kokpit'in iki görünümü.
enum KokpitView { day, month }

final kokpitViewProvider = StateProvider<KokpitView>((ref) => KokpitView.day);

/// Ay görünümünde açık olan ay (ayın 1'i). Gün görünümüne geçip dönünce
/// kullanıcının baktığı ay kaybolmasın diye ekran durumunda tutulmaz.
final kokpitMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

/// Takvimde seçili gün; seçim yoksa `null`.
final kokpitSelectedDayProvider = StateProvider<DateTime?>((ref) => null);

/// "Bugün ve yaklaşanlar": bugünün saati geçmiş açık kayıtları da listede
/// kalsın diye pencere gün başından açılır.
final upcomingRemindersProvider = FutureProvider<List<TaskItem>>(
  (ref) => ref
      .watch(tasksRepositoryProvider)
      .fetchUpcoming(from: AppDates.startOfDay(DateTime.now())),
);

final todayNutritionProvider = FutureProvider<NutritionSummary>(
  (ref) =>
      ref.watch(kokpitRepositoryProvider).fetchNutritionFor(DateTime.now()),
);

/// Seçili kaynaktan (HealthKit ya da Google Health) bugünün verisini okur ve
/// Supabase'e yedekler.
final healthTodayProvider = FutureProvider<HealthSnapshot>((ref) async {
  final repository = ref.watch(healthRepositoryProvider);
  final selection = ref.watch(healthSourceProvider.notifier);
  final snapshot = await ref.watch(healthDataSourceProvider).readToday();
  // iOS okuma izninin reddini bildirmez; tamamı sıfır olan okuma "veri yok"
  // demektir ve gerçek veri gibi saklanmaz. Okuma sürerken kaynak
  // değiştirildiyse eski kaynağın değeri yazılmaz (iki kaynak karışmasın).
  if (snapshot.status == HealthStatus.ok &&
      snapshot.hasData &&
      snapshot.source == selection.current) {
    try {
      await repository.upsertHealthMetrics(
        snapshot.readAt ?? DateTime.now(),
        snapshot,
      );
    } catch (_) {
      // Yedekleme başarısız olsa da ekranda HealthKit verisi gösterilir.
    }
  }
  return snapshot;
});
