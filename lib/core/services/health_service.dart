import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

final healthServiceProvider = Provider<HealthService>((ref) => HealthService());

enum HealthStatus {
  /// Veri okundu.
  ok,

  /// Platform HealthKit desteklemiyor (simülatör dışı iOS harici ortamlar).
  unavailable,

  /// İzin penceresi reddedildi ya da tamamlanamadı.
  denied,
}

class HealthSnapshot {
  const HealthSnapshot({
    required this.status,
    this.steps = 0,
    this.activeKcal = 0,
    this.sleepMinutes = 0,
    this.readAt,
  });

  final HealthStatus status;
  final int steps;
  final int activeKcal;
  final int sleepMinutes;
  final DateTime? readAt;

  bool get hasData => steps > 0 || activeKcal > 0 || sleepMinutes > 0;
}

/// Bir günün HealthKit okuması ([day] yerel gün başı).
typedef HealthDayReading = ({DateTime day, HealthSnapshot snapshot});

/// Bir yerel günün HealthKit sorgu pencereleri.
class HealthDayWindow {
  const HealthDayWindow({
    required this.day,
    required this.end,
    required this.sleepStart,
    required this.sleepEnd,
  });

  /// Yerel gün başı; adım ve enerji aralığının başlangıcı.
  final DateTime day;

  /// Adım ve enerji aralığının bitişi: geçmiş günde ertesi gece yarısı,
  /// bugünde şu an.
  final DateTime end;

  /// Uyku penceresi: önceki gün 18:00 → o gün 18:00 (bugünde en geç şu an).
  /// 18:00 sınırı olmasa akşam uykusu hem o güne hem ertesi güne sayılırdı.
  final DateTime sleepStart;
  final DateTime sleepEnd;
}

/// [now] gününden önceki [pastDays] tamamlanmış gün ve bugün, eskiden yeniye
/// (son öğe bugündür).
List<HealthDayWindow> healthDayWindows(
  DateTime now, {
  int pastDays = HealthService.backfillDays,
}) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (var back = pastDays; back >= 0; back--)
      () {
        // Takvim günüyle hesaplanır (yaz saati geçişinde 24 saat eklenmez).
        final day = DateTime(today.year, today.month, today.day - back);
        final evening = DateTime(day.year, day.month, day.day, 18);
        return HealthDayWindow(
          day: day,
          end: back == 0 ? now : DateTime(day.year, day.month, day.day + 1),
          sleepStart: DateTime(day.year, day.month, day.day - 1, 18),
          sleepEnd: back == 0 && now.isBefore(evening) ? now : evening,
        );
      }(),
  ];
}

/// Apple HealthKit okuma katmanı (Fitbit verisi HealthKit'e senkronlandığı
/// sürece buradan görünür). Yalnızca OKUMA izni ister.
class HealthService {
  /// Açılışta ve öne gelişte yeniden okunan tamamlanmış gün sayısı. 7: Pazartesi
  /// açılan uygulama biten haftanın (Pzt–Paz) tamamını kapsamalıdır.
  static const int backfillDays = 7;

  final Health _health = Health();
  bool _configured = false;

  static const List<HealthDataType> _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static const List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    ..._sleepTypes,
  ];

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// HealthKit izin sayfasını açar. iOS, okuma izninin reddedildiğini
  /// uygulamaya bildirmez; reddedilirse sorgular boş döner.
  Future<bool> requestAccess() async {
    if (!isSupported) return false;
    await _ensureConfigured();
    return _health.requestAuthorization(
      _types,
      permissions: List<HealthDataAccess>.filled(
        _types.length,
        HealthDataAccess.READ,
      ),
    );
  }

  /// Bugünün adım ve aktif kalorisi + dün geceki uyku süresi.
  Future<HealthSnapshot> readToday({DateTime? now}) async {
    if (!isSupported) {
      return const HealthSnapshot(status: HealthStatus.unavailable);
    }

    final bool granted;
    try {
      granted = await requestAccess();
    } catch (_) {
      return const HealthSnapshot(status: HealthStatus.denied);
    }
    if (!granted) return const HealthSnapshot(status: HealthStatus.denied);

    final current = now ?? DateTime.now();
    return _read(healthDayWindows(current, pastDays: 0).single, current);
  }

  /// Bugünden önceki [days] tamamlanmış günün gün sonu değerleri, eskiden
  /// yeniye. [readToday] günü ancak okuma anına kadar görür; gün bittikten
  /// sonra eksik kalan toplam buradan tamamlanır. Desteklenmiyorsa ya da izin
  /// yoksa boş liste döner.
  Future<List<HealthDayReading>> readPastDays({
    int days = backfillDays,
    DateTime? now,
  }) async {
    if (!isSupported || days <= 0) return const [];

    final bool granted;
    try {
      granted = await requestAccess();
    } catch (_) {
      return const [];
    }
    if (!granted) return const [];

    final current = now ?? DateTime.now();
    final windows = healthDayWindows(current, pastDays: days);
    return [
      // Son pencere bugündür; onu readToday okur.
      for (final window in windows.take(windows.length - 1))
        (day: window.day, snapshot: await _read(window, current)),
    ];
  }

  Future<HealthSnapshot> _read(HealthDayWindow window, DateTime readAt) async {
    final steps =
        await _health.getTotalStepsInInterval(window.day, window.end) ?? 0;

    // İstatistik sorgusu: HealthKit birden fazla kaynağı (iPhone + saat/Fitbit)
    // kendisi tekilleştirir. Ham örnekleri toplamak çift sayıma yol açar.
    final energyPoints = await _health.getHealthIntervalDataFromTypes(
      startDate: window.day,
      endDate: window.end,
      types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
      interval: 86400,
    );
    var activeKcal = 0.0;
    for (final point in energyPoints) {
      // Aralık sorgusu bitişten sonra başlayan bir dilim de döndürebilir.
      if (!point.dateFrom.isBefore(window.end)) continue;
      final value = point.value;
      if (value is NumericHealthValue) {
        activeKcal += value.numericValue.toDouble();
      }
    }

    // Birden fazla kaynak (saat + Fitbit) aynı aralığı yazabildiği için
    // çakışan aralıklar birleştirilir; pencereyi aşan kısım sayılmaz.
    final sleepPoints = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: window.sleepStart,
      endTime: window.sleepEnd,
    );
    final sleepMinutes = _mergedMinutes([
      for (final p in sleepPoints)
        if (p.dateTo.isAfter(window.sleepStart) &&
            p.dateFrom.isBefore(window.sleepEnd))
          (
            p.dateFrom.isBefore(window.sleepStart)
                ? window.sleepStart
                : p.dateFrom,
            p.dateTo.isAfter(window.sleepEnd) ? window.sleepEnd : p.dateTo,
          ),
    ]);

    return HealthSnapshot(
      status: HealthStatus.ok,
      steps: steps,
      activeKcal: activeKcal.round(),
      sleepMinutes: sleepMinutes,
      readAt: readAt,
    );
  }

  /// Çakışan aralıkları birleştirip toplam dakikayı döndürür.
  static int _mergedMinutes(List<(DateTime, DateTime)> intervals) {
    if (intervals.isEmpty) return 0;
    intervals.sort((a, b) => a.$1.compareTo(b.$1));
    var total = Duration.zero;
    var (start, end) = intervals.first;
    for (final (s, e) in intervals.skip(1)) {
      if (s.isAfter(end)) {
        total += end.difference(start);
        start = s;
        end = e;
      } else if (e.isAfter(end)) {
        end = e;
      }
    }
    total += end.difference(start);
    return total.inMinutes;
  }
}
