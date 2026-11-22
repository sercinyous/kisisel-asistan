// docs/gizlilik.md ile aynı içerik; birini değiştirirsen diğerini de güncelle.

/// Gizlilik metninin bir bölümü.
class PrivacySection {
  const PrivacySection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

/// Uygulama içi gizlilik metni (Ayarlar > Gizlilik).
const List<PrivacySection> privacySections = [
  PrivacySection('Kısaca', [
    'Bu uygulama, küçük bir arkadaş grubunun kullandığı kişisel bir asistandır; herkes hesap açabilir. Reklam yok, verin satılmaz, üçüncü taraf analiz ya da izleme aracı kullanılmaz.',
    'Verin Supabase üzerinde saklanır. Her kullanıcının satırları veritabanı kurallarıyla (satır düzeyi güvenlik) ayrıdır; başka bir kullanıcı senin kayıtlarını okuyamaz.',
  ]),
  PrivacySection('Topladığımız veriler', [
    'Hesap: e-posta adresin ve giriş bilgilerin (şifre ya da Google ile giriş). Şifren yalnızca kimlik doğrulama servisinde, şifrelenmiş olarak tutulur.',
    'Profil: görünen adın, profil resmin (seçtiğin maskot ya da yüklediğin fotoğraf), boy, doğum yılı, cinsiyet, saat dilimi, hedeflerin (adım, uyku, kalori, su, kilo) ve uygulama ayarların. Profil fotoğrafı yüklemeden önce telefonunda kare kırpılıp küçültülür ve özel bir depolama alanında saklanır.',
    'Sağlık verileri: izin verirsen Apple Sağlık\'tan (iPhone) ya da Google Health\'ten adım, uyku, aktif enerji, boy ve kilo okunur. Uygulamada günlük özetler (günlük adım, uyku süresi, yakılan kalori) ve antrenman kayıtları saklanır; ham dakika dakika veri sunucuya gönderilmez. Apple Sağlık içe aktarımı her hesap için ayrıca onaylanır.',
    'Kendi girdiğin kayıtlar: öğünler ve besin değerleri, su, kilo, görevler, notlar, rutinler, hatırlatıcılar ve onların tamamlanma kayıtları.',
    'Raporlar: bu verilerden hesaplanan günlük ve haftalık rapor sayıları ve kısa yorumları.',
    'Arkadaşlık: gönderdiğin ve aldığın davetler (karşı tarafın e-postası), arkadaşlık bağların ve paylaşım ayarların.',
    'AI kullanım sayaçları: günlük kaç kez AI kullandığın (kota için); içerik değil, yalnızca sayı.',
    'Hata kayıtları ve geri bildirim: uygulama çökerse hata mesajı, teknik iz, uygulama sürümü ve platform; "Sorun bildir" ile yazdığın mesaj. Bunları yalnızca uygulama sahibi görür; sen gönderdikten sonra bile okuyamazsın.',
  ]),
  PrivacySection('Yapay zekâ (Gemini)', [
    'AI ile hızlı eklemede yazdığın metin, sunucumuzdaki ai-proxy fonksiyonu üzerinden Google Gemini\'ye gönderilir ve kayda dönüştürülür. Gemini anahtarı uygulamada değil, sunucudadır.',
    'Raporların kısa yorumu için Gemini\'ye yalnızca hesaplanmış sayılar (ör. görev tamamlama oranı, ortalama uyku) gönderilir; ad, e-posta ya da notlarının metni gönderilmez.',
    'Gemini\'ye giden içerik Google\'ın Gemini API koşullarına tabidir. AI\'ya gizli kalmasını istediğin bilgileri yazma.',
  ]),
  PrivacySection('Kim neyi görür', [
    'Sen: kendi verilerinin tamamını.',
    'Arkadaşların: yalnızca senin açtığın kadarını. Adım, uyku ve kalori anahtarları ayrı ayrıdır ve varsayılan kapalıdır; açarsan arkadaşların yalnızca hedefini tutturduğun gün sayısını ve sıralamayı görür. Gerçek değerler (ör. kaç adım attığın) ayrıca "ayrıntıları paylaş" onayı verirsen görünür. Görevlerin, notların, öğünlerin, rutinlerin ve hatırlatıcıların hiçbir arkadaşla paylaşılmaz. Arkadaşlar senin e-postanı maskeli görür. Görünen adın ve profil resmin (maskot ya da fotoğraf) yalnızca kabul edilmiş arkadaşlarına görünür; fotoğrafın herkese açık bir adreste durmaz.',
    'Uygulama sahibi: sunucu yöneticisi olarak teknik olarak veritabanına erişebilir; bunu yalnızca hata ayıklama ve hesap desteği için kullanır. Hata kayıtlarını ve geri bildirimleri okur.',
    'Hizmet sağlayıcılar: Supabase (veritabanı, kimlik doğrulama, sunucu fonksiyonları) ve Google Gemini (yalnızca yukarıda anlatılan AI istekleri). Google ile giriş ve Google Health kullanırsan Google hesabın da devreye girer.',
  ]),
  PrivacySection('Cihazda saklananlar', [
    'Görünüm tercihi, seçili sağlık kaynağı, Apple Sağlık onayı, Google Health bağlantı bilgisi, son eklenen besinler ve planlanmış bildirimler telefonunda saklanır. Çıkış yaptığında bekleyen bildirimler silinir; hesabını sildiğinde bu tercihler de silinir.',
  ]),
  PrivacySection('Saklama süresi', [
    'Verilerin, sen silene ya da hesabını silene kadar saklanır. Tek tek kayıtları (görev, not, öğün vb.) uygulama içinden istediğin zaman silebilirsin.',
    'Hata kayıtları ve geri bildirimler, hesabın silinince birlikte silinir. Sunucu sağlayıcısının olağan yedekleri kısa bir süre sonra kendiliğinden yenilenir.',
  ]),
  PrivacySection('Hesabını ve verilerini silme', [
    'Hesap > Profil ve hedefler sayfasının en altındaki Hesabımı sil ekranında SİL yazıp onayladığında hesabın ve sunucudaki tüm verin hemen ve kalıcı olarak silinir: profil, profil fotoğrafın, sağlık özetleri, öğünler, görevler, notlar, rutinler, hatırlatıcılar, raporlar, arkadaşlıklar (iki taraftan da), davetler, paylaşım ayarları, hata kayıtları ve geri bildirimler.',
    'Apple Sağlık ya da Google Health\'teki kendi kayıtların bu uygulamaya ait değildir ve silinmez.',
  ]),
  PrivacySection('İletişim', [
    'Soru, düzeltme ya da silme talebin için uygulama sahibine uygulama içinden Hesap > "Sorun bildir" ile yazabilirsin.',
    'Bu metin değişirse uygulamanın yeni sürümüyle birlikte güncellenir.',
  ]),
];
