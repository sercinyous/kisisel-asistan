import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

final healthServiceProvider = Provider<HealthService>((ref) => HealthService());

/// Adım, aktif kalori ve uykunun okunduğu kaynak. Aynı anda yalnızca biri
/// `daily_health_metrics` tablosunu ve arayüzü besler (ikisi birden çift
/// sayardı); seçim cihazda saklanır (`health_source.dart`).
enum HealthSourceKind {
  appleHealth('Apple Sağlık', 'Apple Sağlık'),
  googleHealth('Google Health', 'Google Health');

  const HealthSourceKind(this.label, this.shortLabel);

  /// Seçim düğmesindeki ad.
  final String label;

  /// Kartlarda verinin nereden geldiğini gösteren kısa ad
  /// ("HealthKit · 14:05", "Google Health · 14:05").
  final String shortLabel;

  /// Kayıt yoksa ya da okunamazsa kullanılan kaynak.
  static const HealthSourceKind fallback = HealthSourceKind.appleHealth;

  /// Saklanan metni kaynağa çevirir; tanınmayan değer [fallback] olur.
  static HealthSourceKind parse(String? raw) {
    for (final kind in values) {
      if (kind.name == raw) return kind;
    }
    return fallback;
  }
}

enum HealthStatus {
  /// Veri okundu.
  ok,

  /// Kaynak bu cihazda/derlemede kullanılamıyor (HealthKit iPhone dışında,
  /// Google ise istemci kimliği verilmemiş derlemede).
  unavailable,

  /// İzin penceresi reddedildi ya da tamamlanamadı (HealthKit).
  denied,

  /// Google hesabı bağlı değil.
  notConnected,

  /// Google oturumu yenilenemedi ya da izin eksik: kullanıcı yeniden
  /// bağlanmalı. Ayrıntı [HealthSnapshot.message] içindedir.
  reconnect,

  /// Geçici hata (ağ, yoğunluk, sunucu); sonra tekrar denenebilir.
  failed,
}

class HealthSnapshot {
  const HealthSnapshot({
    required this.status,
    this.steps = 0,
    this.activeKcal = 0,
    this.sleepMinutes = 0,
    this.readAt,
    this.source = HealthSourceKind.appleHealth,
    this.message,
  });

  final HealthStatus status;
  final int steps;
  final int activeKcal;
  final int sleepMinutes;
  final DateTime? readAt;

  /// Okumayı yapan kaynak.
  final HealthSourceKind source;

  /// Durumun kullanıcıya gösterilecek Türkçe açıklaması (yalnızca Google
  /// okumasında; HealthKit metinleri arayüzde sabittir).
  final String? message;

  bool get hasData => steps > 0 || activeKcal > 0 || sleepMinutes > 0;
}

/// Sağlık kaynağından okunan en son boy ve kilo; bilinmeyen alan `null`.
class BodyMeasurements {
  const BodyMeasurements({this.heightCm, this.weightKg});

  final int? heightCm;
  final double? weightKg;

  bool get isEmpty => heightCm == null && weightKg == null;
}

/// Ham ölçümlerden (boy metre, kilo kg) en son geçerli boy ve kiloyu seçer.
/// Boy cm'ye yuvarlanır, kilo bir ondalığa; aralık dışı değer atlanır.
BodyMeasurements latestBodyMeasurements(
  Iterable<({String type, double value, DateTime at})> samples,
) {
  ({double value, DateTime at})? height;
  ({double value, DateTime at})? weight;
  for (final s in samples) {
    if (!s.value.isFinite) continue;
    if (s.type == 'height') {
      final cm = s.value * 100;
      if (cm < 100 || cm > 250) continue;
      if (height == null || s.at.isAfter(height.at)) {
        height = (value: cm, at: s.at);
      }
    } else if (s.type == 'weight') {
      if (s.value < 30 || s.value > 250) continue;
      if (weight == null || s.at.isAfter(weight.at)) {
        weight = (value: s.value, at: s.at);
      }
    }
  }
  return BodyMeasurements(
    heightCm: height?.value.round(),
    weightKg: weight == null ? null : (weight.value * 10).roundToDouble() / 10,
  );
}

/// Bir günün sağlık okuması ([day] yerel gün başı).
typedef HealthDayReading = ({DateTime day, HealthSnapshot snapshot});

/// Sağlık verisi kaynağı sözleşmesi: Apple HealthKit ([HealthService]) ve
/// Google Health aynı pencerelerle ([healthDayWindows]) okur.
abstract interface class HealthDataSource {
  /// Bugünün adım ve aktif kalorisi + dün geceki uyku süresi.
  Future<HealthSnapshot> readToday({DateTime? now});

  /// Bugünden önceki [days] tamamlanmış günün gün sonu değerleri, eskiden
  /// yeniye. Okunamazsa boş liste.
  Future<List<HealthDayReading>> readPastDays({
    int days = HealthService.backfillDays,
    DateTime? now,
  });
}

/// [intervals] içindeki aralıkların [start, end) penceresine düşen kısmını
/// kırpar, çakışanları birleştirir ve toplam dakikayı döndürür. Uyku
/// toplamının ortak kuralıdır: birden fazla kaynak aynı aralığı yazabilir,
/// pencereyi aşan kısım sayılmaz.
int sleepMinutesInWindow(
  Iterable<(DateTime, DateTime)> intervals,
  DateTime start,
  DateTime end,
) {
  return mergedIntervalMinutes([
    for (final (from, to) in intervals)
      if (to.isAfter(start) && from.isBefore(end))
        (from.isBefore(start) ? start : from, to.isAfter(end) ? end : to),
  ]);
}

/// Çakışan aralıkları birleştirip toplam dakikayı döndürür.
int mergedIntervalMinutes(List<(DateTime, DateTime)> intervals) {
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
class HealthService implements HealthDataSource {
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
    HealthDataType.WORKOUT,
  ];

  /// İlk kurulumda boy ve kilo ön doldurması için okunan tipler.
  static const List<HealthDataType> _bodyTypes = [
    HealthDataType.HEIGHT,
    HealthDataType.WEIGHT,
  ];

  /// Boy ve kilonun aranacağı geçmiş.
  static const Duration bodyLookback = Duration(days: 3650);

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// HealthKit izin sayfasını açar. iOS, okuma izninin reddedildiğini
  /// uygulamaya bildirmez; reddedilirse sorgular boş döner.
  Future<bool> requestAccess({bool body = false}) async {
    if (!isSupported) return false;
    await _ensureConfigured();
    final types = body ? _bodyTypes : _types;
    return _health.requestAuthorization(
      types,
      permissions: List<HealthDataAccess>.filled(
        types.length,
        HealthDataAccess.READ,
      ),
    );
  }

  /// Bugünün adım ve aktif kalorisi + dün geceki uyku süresi.
  @override
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
  @override
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

  /// Apple Sağlık'taki en son boy (cm) ve kilo (kg). İzin yoksa, veri yoksa
  /// ya da okuma hata verirse ilgili alan `null` olur; hiçbir zaman fırlatmaz.
  /// Sınır dışı değerler (boy 100–250 cm, kilo 30–250 kg) yok sayılır.
  Future<BodyMeasurements> readLatestBody({DateTime? now}) async {
    if (!isSupported) return const BodyMeasurements();
    try {
      if (!await requestAccess(body: true)) return const BodyMeasurements();
      final end = now ?? DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: _bodyTypes,
        startTime: end.subtract(bodyLookback),
        endTime: end,
      );
      return latestBodyMeasurements([
        for (final p in points)
          if (p.value is NumericHealthValue)
            (
              type: p.type == HealthDataType.HEIGHT ? 'height' : 'weight',
              value: (p.value as NumericHealthValue).numericValue.toDouble(),
              at: p.dateTo,
            ),
      ]);
    } catch (_) {
      return const BodyMeasurements();
    }
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
    final sleepMinutes = mergedIntervalMinutes([
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

  /// Son [days] günün Apple Sağlık antrenmanları (Apple Watch, Fitness vb.).
  /// İzin yoksa, desteklenmiyorsa ya da okuma hata verirse boş liste döner.
  Future<List<AppleWorkout>> readWorkouts({
    int days = backfillDays,
    DateTime? now,
  }) async {
    if (!isSupported || days <= 0) return const [];
    try {
      if (!await requestAccess()) return const [];
      final end = now ?? DateTime.now();
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.WORKOUT],
        startTime: end.subtract(Duration(days: days)),
        endTime: end,
      );
      return [
        for (final p in points)
          if (p.value is WorkoutHealthValue && p.uuid.isNotEmpty)
            AppleWorkout(
              uuid: p.uuid,
              activityType:
                  (p.value as WorkoutHealthValue).workoutActivityType.name,
              start: p.dateFrom,
              end: p.dateTo,
              kcal: (p.value as WorkoutHealthValue).totalEnergyBurned,
              meters: (p.value as WorkoutHealthValue).totalDistance,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Apple Sağlık'tan okunan bir antrenman (ham değerler; eşleme
/// `features/health/data/apple_workouts.dart` içinde).
class AppleWorkout {
  const AppleWorkout({
    required this.uuid,
    required this.activityType,
    required this.start,
    required this.end,
    this.kcal,
    this.meters,
  });

  final String uuid;

  /// `HealthWorkoutActivityType` adı (ör. `RUNNING`).
  final String activityType;
  final DateTime start;
  final DateTime end;
  final int? kcal;
  final int? meters;
}
