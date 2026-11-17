export 'goal_rules.dart' show TrendMetric;

/// Bir günün hedef durumu.
///
/// - [hit]: veri var ve hedef tutturuldu (bugün için de, hedef zaten tutturulduysa).
/// - [miss]: geçmiş günde veri var, hedef tutturulmadı.
/// - [noData]: o gün için veri yok (paydada ve ortalamada yok, seriyi bozmaz).
/// - [inProgress]: bugün, veri var ama hedef henüz tutturulmadı (paydada yok).
/// - [future]: bugünden sonraki gün (boş çubuk, hesaba girmez).
enum DayStatus { hit, miss, noData, inProgress, future }

/// Trend grafiğindeki tek gün. [value] yalnızca verisi olan geçmiş/bugün
/// günlerinde doludur; verisiz ve gelecek günlerde `null`.
class TrendDay {
  const TrendDay({
    required this.day,
    required this.value,
    required this.status,
  });

  final DateTime day;
  final double? value;
  final DayStatus status;

  @override
  bool operator ==(Object other) =>
      other is TrendDay &&
      other.day == day &&
      other.value == value &&
      other.status == status;

  @override
  int get hashCode => Object.hash(day, value, status);

  @override
  String toString() => 'TrendDay($day, $value, ${status.name})';
}

/// Bir dönemin (hafta ya da ay) hedef tutturma özeti. Saf Dart, ekrandan
/// bağımsız.
///
/// Kurallar:
/// - Verisiz gün paydada yok; `percent` = hitDays / dataDays ya da `null`.
/// - Bugün "devam ediyor": hedef tutturulduysa tutan gün, yoksa paydada ve
///   ortalamada yok.
/// - Verisiz ve devam eden günler seriyi bozmaz (atlanır); veri olup hedefi
///   tutturmayan gün seriyi bozar.
/// - `currentStreak` yalnızca geçerli dönemde anlamlıdır; geçmiş dönemde `null`.
class TrendStats {
  const TrendStats({
    required this.days,
    required this.hitDays,
    required this.dataDays,
    required this.percent,
    required this.average,
    required this.longestStreak,
    required this.currentStreak,
  });

  /// Dönemin günleri, girdi sırasıyla (değiştirilemez liste).
  final List<TrendDay> days;

  /// Hedefi tutturulan gün sayısı.
  final int hitDays;

  /// Paydadaki gün sayısı: veri olan geçmiş günler + hedefi tutturan bugün.
  final int dataDays;

  /// hitDays / dataDays, 0–1 aralığında; `dataDays == 0` ise `null`.
  final double? percent;

  /// Paydadaki günlerin değer ortalaması; paydada gün yoksa `null`.
  /// Devam eden bugün dahil değildir.
  final double? average;

  /// Dönem içindeki en uzun ardışık tutan gün serisi.
  final int longestStreak;

  /// Dönemin sonundaki seri; geçerli dönem değilse `null`.
  final int? currentStreak;

  /// [days] dönemin günleri (sırayla), [values] yalnızca verisi olan günleri
  /// içerir; anahtarlar günün saat bileşeninden bağımsız eşleşir. [hit] ham
  /// günlük değeri alır ve hedef tutturuldu mu diye döner. [today] cihaz yerel
  /// günüdür; [isCurrentPeriod] dönem bugünü kapsıyorsa `true`.
  factory TrendStats.build({
    required List<DateTime> days,
    required Map<DateTime, double> values,
    required bool Function(double) hit,
    required DateTime today,
    required bool isCurrentPeriod,
  }) {
    final todayDate = _dateOnly(today);
    final byDay = <DateTime, double>{};
    values.forEach((k, v) {
      if (v.isFinite) byDay[_dateOnly(k)] = v;
    });

    final built = <TrendDay>[];
    var hitDays = 0;
    var dataDays = 0;
    var sum = 0.0;
    var run = 0;
    var longest = 0;

    for (final raw in days) {
      final day = _dateOnly(raw);
      if (day.isAfter(todayDate)) {
        built.add(TrendDay(day: day, value: null, status: DayStatus.future));
        continue;
      }
      final value = byDay[day];
      if (value == null) {
        built.add(TrendDay(day: day, value: null, status: DayStatus.noData));
        continue;
      }
      final isToday = day == todayDate;
      final hitIt = hit(value);
      if (isToday && !hitIt) {
        built.add(
          TrendDay(day: day, value: value, status: DayStatus.inProgress),
        );
        continue;
      }
      dataDays++;
      sum += value;
      if (hitIt) {
        hitDays++;
        run++;
        if (run > longest) longest = run;
        built.add(TrendDay(day: day, value: value, status: DayStatus.hit));
      } else {
        run = 0;
        built.add(TrendDay(day: day, value: value, status: DayStatus.miss));
      }
    }

    return TrendStats(
      days: List<TrendDay>.unmodifiable(built),
      hitDays: hitDays,
      dataDays: dataDays,
      percent: dataDays == 0 ? null : hitDays / dataDays,
      average: dataDays == 0 ? null : sum / dataDays,
      longestStreak: longest,
      currentStreak: isCurrentPeriod ? run : null,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
