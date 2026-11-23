import 'health_models.dart';

/// Hedef kiloya tahmini varışın durumu.
enum WeightEtaStatus {
  /// Tahmin için yeterli ölçüm yok.
  insufficient,

  /// Eğilime göre hedefe zaten ulaşıldı.
  reached,

  /// Eğilim hedefe doğru; [WeightEta.eta] dolu.
  onTrack,

  /// Eğilim hedefe doğru değil (ya da hedefe varış 2 yıldan uzak).
  notTowards,
}

/// Son haftaların kilo ölçümlerinden doğrusal regresyonla tahmin.
class WeightEta {
  const WeightEta({
    required this.status,
    this.eta,
    this.slopeKgPerWeek,
    this.fittedNowKg,
  });

  final WeightEtaStatus status;

  /// Tahmini varış günü (yerel gün başı); yalnızca [WeightEtaStatus.onTrack].
  final DateTime? eta;

  /// Haftalık eğilim (kg/hafta; eksi = kilo kaybı).
  final double? slopeKgPerWeek;

  /// Regresyon doğrusunun bugünkü değeri.
  final double? fittedNowKg;
}

/// Tahminin baktığı en uzun pencere (8 hafta).
const int weightEtaWindowDays = 56;

/// Tahmin için gereken en kısa ölçüm aralığı (gün).
const int weightEtaMinSpanDays = 14;

/// Tahmin için gereken en az ölçüm sayısı.
const int weightEtaMinEntries = 3;

/// Hedefe bu kadar (kg) yakınsa "ulaşıldı" sayılır.
const double weightEtaReachedToleranceKg = 0.3;

/// Bundan uzak varışlar "hedefe doğru değil" sayılır (gün).
const int weightEtaMaxDays = 730;

/// [entries] içinden son [weightEtaWindowDays] günü alır, gün (x) – kilo (y)
/// en küçük kareler doğrusunu kurar ve [targetKg]'a varış gününü tahmin eder.
/// Saf fonksiyon; [now] dışarıdan verilir.
WeightEta estimateWeightEta(
  Iterable<WeightEntry> entries, {
  required double targetKg,
  required DateTime now,
}) {
  final windowStart = now.subtract(const Duration(days: weightEtaWindowDays));
  final points = [
    for (final e in entries)
      if (!e.loggedAt.isBefore(windowStart) && !e.loggedAt.isAfter(now)) e,
  ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  if (points.length < weightEtaMinEntries) {
    return const WeightEta(status: WeightEtaStatus.insufficient);
  }
  final span = points.last.loggedAt.difference(points.first.loggedAt);
  if (span.inHours < weightEtaMinSpanDays * 24) {
    return const WeightEta(status: WeightEtaStatus.insufficient);
  }

  // x: [now]'a göre gün (geçmiş eksi).
  double dayOf(DateTime t) => t.difference(now).inMinutes / (60 * 24);
  final n = points.length;
  var sumX = 0.0, sumY = 0.0;
  for (final p in points) {
    sumX += dayOf(p.loggedAt);
    sumY += p.weightKg;
  }
  final meanX = sumX / n, meanY = sumY / n;
  var sxx = 0.0, sxy = 0.0;
  for (final p in points) {
    final dx = dayOf(p.loggedAt) - meanX;
    sxx += dx * dx;
    sxy += dx * (p.weightKg - meanY);
  }
  if (sxx == 0) return const WeightEta(status: WeightEtaStatus.insufficient);
  final slope = sxy / sxx; // kg/gün
  final fittedNow = meanY - slope * meanX; // x = 0 → bugün
  final perWeek = slope * 7;

  final remaining = targetKg - fittedNow;
  if (remaining.abs() <= weightEtaReachedToleranceKg) {
    return WeightEta(
      status: WeightEtaStatus.reached,
      slopeKgPerWeek: perWeek,
      fittedNowKg: fittedNow,
    );
  }
  // Hedefe doğru anlamlı bir eğilim yoksa (haftada 50 g'dan az) tahmin yok.
  final towards = remaining.sign == slope.sign && perWeek.abs() >= 0.05;
  if (!towards) {
    return WeightEta(
      status: WeightEtaStatus.notTowards,
      slopeKgPerWeek: perWeek,
      fittedNowKg: fittedNow,
    );
  }
  final days = (remaining / slope).ceil();
  if (days > weightEtaMaxDays) {
    return WeightEta(
      status: WeightEtaStatus.notTowards,
      slopeKgPerWeek: perWeek,
      fittedNowKg: fittedNow,
    );
  }
  final today = DateTime(now.year, now.month, now.day);
  return WeightEta(
    status: WeightEtaStatus.onTrack,
    eta: DateTime(today.year, today.month, today.day + days),
    slopeKgPerWeek: perWeek,
    fittedNowKg: fittedNow,
  );
}

const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _kg(double v) {
  final rounded = (v * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1).replaceAll('.', ',');
}

/// Kartta gösterilen tek satırlık açıklama.
String weightEtaMessage(WeightEta eta,
    {required double targetKg, required DateTime now}) {
  switch (eta.status) {
    case WeightEtaStatus.insufficient:
      return 'Tahmin için son 8 haftada en az 2 haftaya yayılan '
          '$weightEtaMinEntries ölçüm gerekli';
    case WeightEtaStatus.reached:
      return '${_kg(targetKg)} kg hedefindesin';
    case WeightEtaStatus.notTowards:
      return 'Son haftalardaki trend hedefe doğru değil';
    case WeightEtaStatus.onTrack:
      final d = eta.eta!;
      final year = d.year == now.year ? '' : ' ${d.year}';
      return 'Bu gidişle ${_kg(targetKg)} kg\'a yaklaşık '
          '${d.day} ${_months[d.month - 1]}$year';
  }
}

/// Tek ETA fonksiyonu: Kilo kartı, KiloDetay ve Plan bunu kullanır
/// ([estimateWeightEta] ile aynı doğrusal eğilim).
WeightEta weightEta(
  List<WeightEntry> series, {
  required double targetKg,
  required DateTime now,
}) =>
    estimateWeightEta(series, targetKg: targetKg, now: now);

/// Gerçek haftalık kayıp (kg/hafta, kayıpta pozitif) aynı eğilimden;
/// eğilim hesaplanamıyorsa `null`.
double? actualKgPerWeek(List<WeightEntry> series, {required DateTime now}) {
  final slope = estimateWeightEta(series, targetKg: 0, now: now).slopeKgPerWeek;
  return slope == null ? null : -slope;
}
