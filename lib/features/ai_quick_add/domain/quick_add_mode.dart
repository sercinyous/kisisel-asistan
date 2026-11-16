/// AI girişinin iki ayrı alanı. Kayıtlar birbirine karışmasın diye her
/// alanın kendi talimatı, şeması ve önizlemesi vardır.
enum QuickAddMode {
  work,
  health;

  QuickAddMode get other =>
      this == QuickAddMode.work ? QuickAddMode.health : QuickAddMode.work;

  /// Giriş sayfasının başlığı.
  String get title => switch (this) {
        QuickAddMode.work => 'İş girişi',
        QuickAddMode.health => 'Sağlık & beslenme girişi',
      };

  /// Seçim sayfasında ve giriş başlığının altında gösterilen kapsam.
  String get scopeHint => switch (this) {
        QuickAddMode.work => 'Görev, randevu, not ya da tekrarlayan iş.',
        QuickAddMode.health => 'Öğün, antrenman ya da kilo.',
      };

  /// "Bu bir … gibi görünüyor." cümlesindeki ad.
  String get recordNoun => switch (this) {
        QuickAddMode.work => 'iş kaydı',
        QuickAddMode.health => 'sağlık kaydı',
      };

  /// Bu alana geçiş düğmesinin metni.
  String get switchLabel => switch (this) {
        QuickAddMode.work => 'İş girişine geç',
        QuickAddMode.health => 'Sağlık girişine geç',
      };

  /// Karışık metinde: önce eldeki kalemler kaydedilir, sonra bu alana geçilir.
  String get saveAndSwitchLabel => switch (this) {
        QuickAddMode.work => 'Kaydet ve iş girişine geç',
        QuickAddMode.health => 'Kaydet ve sağlık girişine geç',
      };
}
