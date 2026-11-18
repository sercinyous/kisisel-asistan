/// Tek bir su kaydı (ml).
class WaterLog {
  const WaterLog({
    required this.id,
    required this.loggedOn,
    required this.ml,
    required this.createdAt,
  });

  final String id;

  /// Yerel gün (gece yarısı).
  final DateTime loggedOn;
  final int ml;
  final DateTime createdAt;

  factory WaterLog.fromMap(Map<String, dynamic> map) {
    final day = DateTime.parse(map['logged_on'] as String);
    final created = map['created_at'];
    return WaterLog(
      id: map['id'] as String,
      loggedOn: DateTime(day.year, day.month, day.day),
      ml: (map['ml'] as num).toInt(),
      createdAt: created is String
          ? DateTime.parse(created).toLocal()
          : DateTime(day.year, day.month, day.day),
    );
  }
}

/// Varsayılan günlük su hedefi (ml).
const int defaultDailyWaterMl = 2000;

/// Tek kayıtta izin verilen en büyük miktar (veritabanı kısıtıyla aynı).
const int maxWaterLogMl = 3000;

/// Hızlı ekleme düğmeleri (ml).
const List<int> waterQuickAddMl = [250, 500];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// [day] gününün toplamı (ml).
int waterTotalForDay(Iterable<WaterLog> logs, DateTime day) {
  var total = 0;
  for (final log in logs) {
    if (_sameDay(log.loggedOn, day)) total += log.ml;
  }
  return total;
}

/// Hedefe oran (0–1 arasına kırpılmış); hedef geçersizse 0.
double waterProgress(int totalMl, int targetMl) {
  if (targetMl <= 0) return 0;
  final p = totalMl / targetMl;
  return p < 0 ? 0 : (p > 1 ? 1 : p);
}

/// "1,25 L" / "750 ml"
String formatWaterMl(int ml) {
  if (ml < 1000) return '$ml ml';
  final liters = ml / 1000;
  final text = liters == liters.roundToDouble()
      ? liters.toStringAsFixed(0)
      : liters.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return '${text.replaceAll('.', ',')} L';
}
