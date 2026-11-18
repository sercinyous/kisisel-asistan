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

/// Kokpit kartlarının alt bardaki bir sekmeye geçme isteği (sekme sırası:
/// 0 Kokpit, 1 Operasyon, 2 Sağlık, 3 Raporlar). Kabuk dinler ve geçince
/// `null`'a döndürür.
final homeTabRequestProvider = StateProvider<int?>((ref) => null);

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
/// Supabase'e yedekler. Okuma başında kullanıcı, kaynak ve Google bağlantısı
/// sabitlenir ([HealthWriteGuard]); okuma sürerken biri değiştiyse (ör. çıkış
/// yapıp başka hesapla girildi) okunan değer yazılmaz, yazma sabit kullanıcıyla
/// yapılır.
final healthTodayProvider = FutureProvider<HealthSnapshot>((ref) async {
  // Kullanıcı değişince sağlayıcı yeniden kurulur.
  ref.watch(healthRepositoryProvider);
  final source = ref.watch(healthDataSourceProvider);
  final guard = HealthWriteGuard.capture(ref.read);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  final snapshot = await source.readToday();
  // Okuma sürerken kaynak değiştiyse eski kaynağın değeri yazılmaz (iki kaynak
  // karışmasın). Tamamı sıfır okuma kuralları depodadır
  // ([HealthRepository.upsertHealthMetrics]).
  if (guard != null &&
      !disposed &&
      guard.isValid &&
      snapshot.status == HealthStatus.ok &&
      snapshot.source == guard.source) {
    try {
      await guard.repository.upsertHealthMetrics(
        snapshot.readAt ?? DateTime.now(),
        snapshot,
        ownerId: guard.ownerId,
      );
    } catch (_) {
      // Yedekleme başarısız olsa da ekranda okunan veri gösterilir.
    }
  }
  return snapshot;
});
