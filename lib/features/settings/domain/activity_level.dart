/// Günlük hareket düzeyi: bazal enerjinin çarpanı (Mifflin–St Jeor × katsayı).
/// [dbValue] `user_settings.activity_level` sütunundaki değerdir.
enum ActivityLevel {
  sedentary('sedentary', 'Hareketsiz', 'Masa başı, çok az yürüyüş', 1.2),
  light('light', 'Az hareketli', 'Haftada 1–3 gün hafif egzersiz', 1.375),
  moderate('moderate', 'Orta', 'Haftada 3–5 gün egzersiz', 1.55),
  active('active', 'Hareketli', 'Haftada 6–7 gün egzersiz', 1.725),
  veryActive('very_active', 'Çok hareketli', 'Ağır iş ya da günde iki antrenman',
      1.9);

  const ActivityLevel(this.dbValue, this.label, this.description, this.factor);

  final String dbValue;
  final String label;
  final String description;
  final double factor;

  /// Veritabanı değerini çözer; `null` ve tanınmayan değer `null` döner.
  static ActivityLevel? tryParse(Object? value) {
    for (final level in values) {
      if (level.dbValue == value) return level;
    }
    return null;
  }
}
