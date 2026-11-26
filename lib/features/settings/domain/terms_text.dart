// docs/kullanim_kosullari.md ile aynı içerik (test/features/settings/legal_docs_sync_test.dart denetler).

import 'privacy_text.dart';

/// Uygulama içi kullanım koşulları (giriş ekranı ve Hesap > Kullanım koşulları).
const List<PrivacySection> termsSections = [
  PrivacySection('Hizmet', [
    'Ritim; görev, rutin, hatırlatıcı ve sağlık hedeflerini tek yerde takip etmen için hazırlanmış kişisel bir asistandır. Uygulamayı kullanarak bu koşulları kabul etmiş olursun.',
    'Ritim ücretsizdir; özellikler değişebilir, eklenebilir ya da kaldırılabilir. Hizmet "olduğu gibi" sunulur; kesintisiz ya da hatasız çalışacağı garanti edilmez.',
  ]),
  PrivacySection('Yaş ve hesap', [
    'Ritim\'i kullanmak için en az 13 yaşında olmalısın; 18 yaşından küçüksen velinin onayıyla kullanmalısın.',
    'Google ya da e-posta ile hesap açabilirsin. Hesabının ve şifrenin güvenliğinden sen sorumlusun.',
    'Hesabını istediğin zaman uygulama içinden silebilirsin: Hesap > Profil ve hedefler > Hesabımı sil. Silme kalıcıdır.',
  ]),
  PrivacySection('Sağlık bilgileri', [
    'Adım, uyku, kalori ve kilo gibi değerler, hesaplanan hedefler ve yapay zekâ yorumları yalnızca bilgilendirme amaçlıdır; tıbbi tavsiye, teşhis ya da tedavi yerine geçmez. Sağlığınla ilgili kararlar için bir sağlık uzmanına danış.',
    'Ritim bir tıbbi cihaz değildir. Apple Sağlık ve Google Health verileri yalnızca senin izninle ve salt okunur olarak alınır.',
  ]),
  PrivacySection('Arkadaşlar ve hikâyeler', [
    'Arkadaş özelliğinde yalnızca tanıdığın kişileri ekle. Hakaret, taciz, müstehcen ya da yasa dışı içerik (görünen ad, profil fotoğrafı, hikâye) paylaşamazsın.',
    'Rahatsız eden bir kişiyi arkadaş listesinden ya da gelen istekten Engelle ile engelleyebilir, Bildir ile bildirebilirsin. Şikayetler en geç 24 saat içinde incelenir; kurallara aykırı içerik kaldırılır ve hesabı kapatılabilir.',
  ]),
  PrivacySection('Kabul edilebilir kullanım', [
    'Uygulamayı yasalara aykırı amaçlarla, başkalarının hesaplarına erişmek ya da hizmeti bozmak için kullanamazsın.',
  ]),
  PrivacySection('Veriler ve gizlilik', [
    'Hangi verilerin toplandığı ve nasıl kullanıldığı Gizlilik Metni\'nde anlatılır.',
  ]),
  PrivacySection('Sorumluluğun sınırı', [
    'Yasaların izin verdiği ölçüde, uygulamanın kullanımından ya da kullanılamamasından doğan dolaylı zararlardan geliştirici sorumlu tutulamaz.',
  ]),
  PrivacySection('Değişiklikler ve iletişim', [
    'Bu koşullar güncellenebilir; güncel hali uygulamanın yeni sürümüyle birlikte gelir. Soruların için Hesap > Sorun bildir\'i kullanabilirsin.',
  ]),
];
