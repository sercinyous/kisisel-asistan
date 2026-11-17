/// Sabit kategori listeleri. Sayısal hedefler ve ekip üyeleri kullanıcı
/// ayarlarındadır (`settingsOrDefaultProvider`).
abstract final class AppTargets {
  /// Herkes için nötr iş kategorisi/kapsamı.
  static const String workCategory = 'İş';

  /// Eski yapıların yazdığı iş kategorisi/kapsamı değeri. Yalnızca okunurken
  /// [workCategory]'ye eşlenir (geçiş uyumu); yeni kayıtta asla yazılmaz.
  static const String legacyWorkCategory = 'Pusholder';

  static const List<String> taskCategories = [
    workCategory,
    'Ekip',
    'Finans',
    'Kişisel',
  ];
  static const List<String> noteCategories = [
    'Toplantı',
    'Fikir',
    workCategory,
    'Ekip',
    'Finans',
    'Kişisel',
  ];

  /// Eski değeri ('Pusholder') 'İş'e çevirir; diğer değerleri olduğu gibi
  /// bırakır.
  static String normalizeWork(String value) =>
      value == legacyWorkCategory ? workCategory : value;
}
