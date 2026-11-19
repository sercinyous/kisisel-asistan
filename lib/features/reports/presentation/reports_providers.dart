import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../data/reports_repository.dart';

export '../data/reports_repository.dart';

/// Günlük rapor listesi için gün aralığı (iki uç dahil). Kayıt (record)
/// olduğu için değer eşitliğiyle `family` anahtarı olur.
typedef ReportRange = ({DateTime from, DateTime to});

/// Bir haftanın raporu; üretilmemişse `null`. Anahtar haftanın Pazartesi'si
/// olmalıdır (`AppDates.weekStart`); başka gün verilirse o haftaya indirgenir
/// ama ayrı önbellek girdisi açılır.
final weeklyReportProvider = FutureProvider.family<WeeklyReport?, DateTime>(
  (ref, weekStart) => ref
      .watch(reportsRepositoryProvider)
      .fetchWeekly(AppDates.weekStart(weekStart)),
);

/// Son haftalık raporlar, yeniden eskiye ("Geçmiş haftalar").
final weeklyReportListProvider = FutureProvider<List<WeeklyReport>>(
  (ref) => ref.watch(reportsRepositoryProvider).fetchWeeklyList(),
);

/// Bir günün raporu; üretilmemişse `null`. Anahtar yerel gün başı olmalıdır.
final dailyReportProvider = FutureProvider.family<DailyReport?, DateTime>(
  (ref, day) =>
      ref.watch(reportsRepositoryProvider).fetchDaily(AppDates.startOfDay(day)),
);

/// Aralıktaki günlük raporlar, yeniden eskiye.
final dailyReportListProvider =
    FutureProvider.family<List<DailyReport>, ReportRange>(
  (ref, range) => ref.watch(reportsRepositoryProvider).fetchDailyList(
        AppDates.startOfDay(range.from),
        AppDates.startOfDay(range.to),
      ),
);

/// [day] ile biten son 7 günün aralığı ("son 7 günün kısa listesi").
ReportRange lastSevenDays(DateTime day) {
  final end = AppDates.startOfDay(day);
  return (from: AppDates.addDays(end, -6), to: end);
}

/// Raporu sunucuda yeniden üretir ve ilgili sağlayıcıları tazeler.
/// Hata ([ReportGenerationException]) çağırana iletilir; o durumda da liste
/// tazelenir çünkü sunucu sayıları yazıp yorumda takılmış olabilir.
Future<void> regenerateReport(
  WidgetRef ref,
  ReportKind kind,
  DateTime date,
) async {
  // Üretim sürerken ekran kapanabilir; await sonrası WidgetRef kullanılamaz.
  final container = ProviderScope.containerOf(ref.context, listen: false);
  try {
    await container
        .read(reportsRepositoryProvider)
        .regenerate(kind: kind, date: date);
  } finally {
    switch (kind) {
      case ReportKind.weekly:
        container
          ..invalidate(weeklyReportProvider)
          ..invalidate(weeklyReportListProvider);
      case ReportKind.daily:
        container
          ..invalidate(dailyReportProvider)
          ..invalidate(dailyReportListProvider);
    }
  }
}
