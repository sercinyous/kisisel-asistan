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

/// Apple HealthKit okuma katmanı (Fitbit verisi HealthKit'e senkronlandığı
/// sürece buradan görünür). Yalnızca OKUMA izni ister.
class HealthService {
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
    final dayStart = DateTime(current.year, current.month, current.day);

    final steps = await _health.getTotalStepsInInterval(dayStart, current) ?? 0;

    // İstatistik sorgusu: HealthKit birden fazla kaynağı (iPhone + saat/Fitbit)
    // kendisi tekilleştirir. Ham örnekleri toplamak çift sayıma yol açar.
    final energyPoints = await _health.getHealthIntervalDataFromTypes(
      startDate: dayStart,
      endDate: current,
      types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
      interval: 86400,
    );
    var activeKcal = 0.0;
    for (final point in energyPoints) {
      final value = point.value;
      if (value is NumericHealthValue) {
        activeKcal += value.numericValue.toDouble();
      }
    }

    // Uyku penceresi: dün 18:00 → şu an. Birden fazla kaynak (saat + Fitbit)
    // aynı aralığı yazabildiği için çakışan aralıklar birleştirilir.
    final sleepStart = dayStart.subtract(const Duration(hours: 6));
    final sleepPoints = await _health.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: sleepStart,
      endTime: current,
    );
    final sleepMinutes = _mergedMinutes(
      sleepPoints.map((p) => (p.dateFrom, p.dateTo)).toList(),
    );

    return HealthSnapshot(
      status: HealthStatus.ok,
      steps: steps,
      activeKcal: activeKcal.round(),
      sleepMinutes: sleepMinutes,
      readAt: current,
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
