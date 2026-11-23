/// Hedef türü (`user_settings.goal_mode`) ve kas yapma temposu
/// (`user_settings.gain_rate`). Bilgilendirme amaçlıdır, tıbbi tavsiye değildir.
enum GoalMode {
  fatLoss('fat_loss', 'Yağ yakma'),
  recomp('recomp', 'Kas yaparken yağ yakma'),
  leanGain('lean_gain', 'Kas yapma'),
  maintain('maintain', 'Kiloyu koru');

  const GoalMode(this.dbValue, this.label);

  /// Veritabanı değeri: 'fat_loss', 'recomp', 'lean_gain', 'maintain'.
  final String dbValue;
  final String label;

  /// Tanınmayan ya da boş değer yağ yakmaya düşer (eski satırlar).
  static GoalMode parse(Object? value) {
    for (final g in GoalMode.values) {
      if (g.dbValue == value || g.name == value) return g;
    }
    return GoalMode.fatLoss;
  }

  /// Kalori açığıyla çalışan hedefler (Açık serisi yalnızca yağ yakmada).
  bool get usesDeficitStreak => this == GoalMode.fatLoss;

  /// Seçim kartındaki kısa açıklama.
  String get summary => switch (this) {
        GoalMode.fatLoss =>
          'Kalori açığıyla kilo verirsin; hızı Tempo belirler.',
        GoalMode.recomp =>
          'Harcamanın ~%10 altında, yüksek proteinle; tartı yavaş değişir.',
        GoalMode.leanGain =>
          'Küçük bir kalori fazlası ve yüksek proteinle kilo alırsın.',
        GoalMode.maintain => 'Harcaman kadar yersin; kilon sabit kalır.',
      };
}

/// Kas yapma temposu: günlük kalori fazlası ve tahmini haftalık artış.
enum GainRate {
  slow('slow', 250, 0.25, 'Yavaş (+250 kcal)'),
  standard('standard', 400, 0.4, 'Standart (+400 kcal)');

  const GainRate(this.dbValue, this.surplusKcal, this.kgPerWeek, this.label);

  /// Veritabanı değeri: 'slow' ya da 'standard'.
  final String dbValue;

  /// Harcamanın üstüne eklenen günlük kcal.
  final int surplusKcal;

  /// Tahmini haftalık artış (kg); bir kısmı yağdır.
  final double kgPerWeek;
  final String label;

  static GainRate parse(Object? value) {
    for (final r in GainRate.values) {
      if (r.dbValue == value || r.name == value) return r;
    }
    return GainRate.slow;
  }
}

/// Hedef türlerinin sabitleri.
abstract final class GoalRules {
  /// Kas yaparken yağ yakma: harcamanın bu oranı kadar açık.
  static const double recompDeficitShare = 0.10;

  /// Protein (g/kg): kas yaparken yağ yakma 2,2 (aralık 2,0–2,2), kas yapma
  /// 2,0 (aralık 1,8–2,0), koruma 1,6.
  static const double recompProteinPerKg = 2.2;
  static const double gainProteinPerKg = 2.0;
  static const double maintainProteinPerKg = 1.6;

  /// "Hedef serisi": alınan, hedefin ±%10'u içinde.
  static const double targetStreakTolerance = 0.10;

  /// Karşılaştırma kartlarının ufku (hafta).
  static const int projectionWeeks = 12;

  /// Kas yaparken yağ yakmada gösterilen zorunlu not.
  static const String recompStrengthNote =
      'Bu hedef haftada en az 3 gün direnç (ağırlık) antrenmanı yaparsan '
      'işe yarar; antrenman olmadan yalnızca hafif bir açık olur.';

  /// Kas yapmada tahmin notu.
  static const String gainEstimateNote =
      'Haftalık artış bir tahmindir; alınan kilonun bir kısmı yağdır. '
      'Hız; antrenman, uyku ve kişiye göre değişir.';
}
