import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reports_providers.dart';

/// Raporlar sekmesinin iki görünümü.
enum ReportsView { weekly, daily }

final reportsViewProvider =
    StateProvider<ReportsView>((ref) => ReportsView.weekly);

/// Seçili hafta (Pazartesi); `null` = içinde bulunulan hafta.
final reportsWeekProvider = StateProvider<DateTime?>((ref) => null);

/// Seçili gün (yerel gün başı); `null` = bugün.
final reportsDayProvider = StateProvider<DateTime?>((ref) => null);

/// Yeniden üretilen rapor: tür + dönem başı.
typedef ReportTarget = ({ReportKind kind, DateTime date});

/// Süren üretimler ve son denemenin hata iletileri.
class RegenerationState {
  const RegenerationState({this.busy = const {}, this.errors = const {}});

  final Set<ReportTarget> busy;
  final Map<ReportTarget, String> errors;
}

/// Görünüm değişse de üretim durumu kaybolmasın diye sağlayıcıda tutulur.
class ReportRegenerationNotifier extends Notifier<RegenerationState> {
  @override
  RegenerationState build() => const RegenerationState();

  /// Üretimi başlatır; aynı rapor için süren üretim varsa `false`.
  bool begin(ReportTarget target) {
    if (state.busy.contains(target)) return false;
    state = RegenerationState(
      busy: {...state.busy, target},
      errors: {...state.errors}..remove(target),
    );
    return true;
  }

  void end(ReportTarget target, {String? error}) {
    state = RegenerationState(
      busy: {...state.busy}..remove(target),
      errors: {
        ...state.errors,
        if (error != null) target: error,
      },
    );
  }
}

final reportRegenerationProvider =
    NotifierProvider<ReportRegenerationNotifier, RegenerationState>(
  ReportRegenerationNotifier.new,
);

/// Raporu sunucuda yeniden üretir. Meşgul durumu, tazelenen rapor ekrana
/// gelene kadar sürer; hata iletisi [reportRegenerationProvider]'a yazılır.
Future<void> runRegeneration(
  WidgetRef ref,
  ReportKind kind,
  DateTime date,
) async {
  final ReportTarget target = (kind: kind, date: date);
  // Üretim sürerken ekran kapanabilir; await sonrası WidgetRef kullanılmaz.
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final notifier = container.read(reportRegenerationProvider.notifier);
  if (!notifier.begin(target)) return;

  String? error;
  try {
    await regenerateReport(ref, kind, date);
  } on ReportGenerationException catch (e) {
    error = e.message;
  } catch (_) {
    error = 'Rapor oluşturulamadı. Biraz sonra yeniden dene.';
  }
  try {
    await switch (kind) {
      ReportKind.weekly => container.read(weeklyReportProvider(date).future),
      ReportKind.daily => container.read(dailyReportProvider(date).future),
    };
  } catch (_) {
    // Okuma hatası bölümün kendi hata durumunda gösterilir.
  }
  notifier.end(target, error: error);
}
