import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/report_models.dart';

export '../domain/report_models.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return ReportsRepository(ref.watch(supabaseClientProvider));
});

/// Rapor üretimi başarısız oldu; [message] kullanıcıya gösterilebilir.
class ReportGenerationException implements Exception {
  const ReportGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `generate-reports` hatasının kullanıcıya gösterilecek metni. Sunucunun
/// girdi hatası (400) ya da günlük yenileme sınırı (429) için yazdığı Türkçe
/// ileti varsa o; yoksa duruma göre genel bir ileti. [status] 0: istek
/// sunucuya ulaşamadı.
String reportErrorMessage(int status, Object? details) {
  if ((status == 400 || status == 429) &&
      details is Map &&
      details['error'] is String) {
    return details['error'] as String;
  }
  return switch (status) {
    0 => 'Bağlantı kurulamadı. İnternetini kontrol edip yeniden dene.',
    401 || 403 => 'Oturum doğrulanamadı. Çıkış yapıp yeniden giriş yap.',
    404 => 'Rapor servisi kurulmamış (generate-reports).',
    _ => 'Rapor oluşturulamadı. Biraz sonra yeniden dene.',
  };
}

/// Raporlar sunucuda üretilir (Edge Function `generate-reports`); uygulama
/// satırları yalnızca okur ve yeniden üretimi tetikler.
class ReportsRepository {
  const ReportsRepository(this._client);

  final SupabaseClient _client;

  static const _weeklyColumns =
      'week_start, metrics, ai_summary, ai_status, generated_at';
  static const _dailyColumns =
      'report_date, metrics, ai_summary, ai_status, generated_at';

  /// [weekStart] haftasının raporu (haftanın herhangi bir günü verilebilir);
  /// henüz üretilmediyse `null`.
  Future<WeeklyReport?> fetchWeekly(DateTime weekStart) async {
    final row = await _client
        .from('weekly_reports')
        .select(_weeklyColumns)
        .eq('week_start', AppDates.ymd(AppDates.weekStart(weekStart)))
        .maybeSingle();
    return row == null ? null : WeeklyReport.fromMap(row);
  }

  /// Son haftalık raporlar, yeniden eskiye.
  Future<List<WeeklyReport>> fetchWeeklyList({int limit = 12}) async {
    final rows = await _client
        .from('weekly_reports')
        .select(_weeklyColumns)
        .order('week_start', ascending: false)
        .limit(limit);
    return [for (final row in rows) WeeklyReport.fromMap(row)];
  }

  /// [day] gününün raporu; henüz üretilmediyse `null`.
  Future<DailyReport?> fetchDaily(DateTime day) async {
    final row = await _client
        .from('daily_reports')
        .select(_dailyColumns)
        .eq('report_date', AppDates.ymd(day))
        .maybeSingle();
    return row == null ? null : DailyReport.fromMap(row);
  }

  /// [from]..[to] (iki uç dahil, yerel gün) aralığının günlük raporları,
  /// yeniden eskiye.
  Future<List<DailyReport>> fetchDailyList(DateTime from, DateTime to) async {
    final rows = await _client
        .from('daily_reports')
        .select(_dailyColumns)
        .gte('report_date', AppDates.ymd(from))
        .lte('report_date', AppDates.ymd(to))
        .order('report_date', ascending: false);
    return [for (final row in rows) DailyReport.fromMap(row)];
  }

  /// Raporu sunucuda yeniden üretir (sayılar + yorum) ve kaydeder.
  /// [date]: günlükte o gün, haftalıkta haftanın herhangi bir günü.
  /// Başarısız olursa [ReportGenerationException] fırlatır.
  Future<void> regenerate({
    required ReportKind kind,
    required DateTime date,
  }) async {
    final target = kind == ReportKind.weekly ? AppDates.weekStart(date) : date;
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'generate-reports',
        body: {'kind': kind.apiValue, 'date': AppDates.ymd(target)},
      );
    } on FunctionException catch (e) {
      throw ReportGenerationException(reportErrorMessage(e.status, e.details));
    }
    final data = response.data;
    if (data is Map && data['ok'] == false) {
      throw ReportGenerationException(
          reportErrorMessage(response.status, data));
    }
  }
}
