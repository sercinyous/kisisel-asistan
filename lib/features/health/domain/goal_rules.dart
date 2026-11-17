/// Trend ekranlarının izlediği üç metrik.
enum TrendMetric { steps, sleep, calories }

/// Günlük hedef tutturma kuralları. Eşikler yalnızca burada tanımlıdır
/// (Faz 4B sunucu özeti aynı değerleri SQL'de yeniden yazar; eşlik testi
/// bu sabitlere bakar).
///
/// Karşılaştırmalar tam sayı aritmetiğiyle yapılır: `450 * 0.9` gibi kayan
/// noktalı çarpımlar tam sınırdaki değeri yanlış tarafa atabilir. Kalori ve
/// protein girdileri double'dır (`numeric(7,1)` / `numeric(6,1)` satırların
/// toplamı: `333.9 + 663.9 + ...` tam 1870.0 yerine 1869.9999999999998 çıkabilir);
/// bu yüzden önce veritabanının ölçeğine (onda bir) yuvarlanır, sonra tam
/// sayı olarak karşılaştırılır. Böylece sonuç, SQL'in tam `numeric` toplamıyla
/// (Raporlar) aynı çıkar.
/// Hedefi sıfır ya da negatif olan kural hiçbir zaman tutmaz (hedef tanımsız
/// iken sahte başarı üretilmez); NaN, sonsuz ve veritabanında yazılamayacak
/// kadar büyük değerler de tutmaz.
abstract final class GoalRules {
  /// Adım: hedefin en az %100'ü.
  static const int stepsMinPercent = 100;

  /// Uyku: hedefin en az %90'ı (bileklik/saat uykuyu eksik ölçer).
  static const int sleepMinPercent = 90;

  /// Kalori: hedefin %85–%110'u (uçlar dahil; raporlarla aynı bant).
  static const int caloriesMinPercent = 85;
  static const int caloriesMaxPercent = 110;

  /// Protein: hedefin en az %90'ı (raporlarla aynı).
  static const int proteinMinPercent = 90;

  static bool stepsHit(int steps, int target) =>
      target > 0 && steps * 100 >= target * stepsMinPercent;

  static bool sleepHit(int minutes, int target) =>
      target > 0 && minutes * 100 >= target * sleepMinPercent;

  /// Veritabanı ölçeğinin (onda bir) üstünde kalan değerler için üst sınır;
  /// `numeric(7,1)` en çok 99999.9 tutar, bu sınırın çok üstü gerçek değildir.
  static const double _maxScaledValue = 1e9;

  /// [value]'yu onda birlere yuvarlar; sonlu olmayan ya da aralık dışı ise
  /// `null`. `round()` NaN/sonsuzda atar, bu yüzden denetim önce yapılır.
  static int? _tenths(double value) {
    if (!value.isFinite || value.abs() > _maxScaledValue) return null;
    return (value * 10).round();
  }

  static bool caloriesHit(double kcal, int target) {
    final tenths = _tenths(kcal);
    return target > 0 &&
        tenths != null &&
        tenths * 10 >= target * caloriesMinPercent &&
        tenths * 10 <= target * caloriesMaxPercent;
  }

  static bool proteinHit(double grams, int target) {
    final tenths = _tenths(grams);
    return target > 0 &&
        tenths != null &&
        tenths * 10 >= target * proteinMinPercent;
  }
}
