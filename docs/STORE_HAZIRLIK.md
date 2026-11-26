# App Store hazırlık listesi (sahip)

Ritim'i App Store'a çıkarmak için sırayla yapılacak işler. Kod tarafı hazırdır; aşağıdakiler
yalnızca sahibin hesaplarıyla (Apple, Supabase, Google, Codemagic) yapılabilir.
Ayrıntılı inceleme notları: [apple_inceleme.md](apple_inceleme.md).

## 0. Karar: 1.0'da giriş yöntemi

- Mağaza yapısı (`ios-testflight`) Google girişini **kapalı** derler (`GOOGLE_WEB_CLIENT_ID=""`).
  Sign in with Apple olmadan Google girişi sunmak Guideline 4.8'e aykırıdır; 1.0 yalnızca e-posta
  girişiyle çıkar. Google Health bağlantısı bir hesap girişi değildir ve bundan etkilenmez.
- Google girişi sonraki sürümde Sign in with Apple ile birlikte açılacaksa: App ID'de "Sign in with Apple"
  yeteneğini aç, Supabase > Auth > Providers > Apple'ı bundle id `com.sercinyous.kisiselasistan` ile
  etkinleştir, Apple .p8 anahtarını hesap silmede token iptali için fonksiyon secret'ı olarak ekle.

## 1. İletişim ve yasal metinler

1. Yayıncı adını ve bir destek e-postası belirle.
2. Bu bilgileri `docs/gizlilik.md`, `docs/kullanim_kosullari.md` ve uygulamadaki metinlerin
   "İletişim" bölümüne yazdır (kod değişikliği, tek satır).
3. Gizlilik politikasını, kullanım koşullarını ve basit bir destek sayfasını herkese açık adreste
   yayınla (ör. GitHub Pages). Üç adresi not et; App Store Connect'te istenecek.
4. Aynı yerde "E-posta doğrulandı, uygulamaya dön" yazan bir sayfa yayınla (Supabase Site URL için).

## 2. Supabase

1. SQL Editor: `supabase/schema.sql`, ardından `supabase/cron.sql` çalıştır (ikisi de tekrar çalıştırılabilir).
2. Fonksiyonları dağıt:
   `supabase functions deploy ai-proxy generate-reports delete-account --no-verify-jwt`
3. Secrets: `GEMINI_API_KEY`, `CRON_SECRET`, `GEMINI_MODEL` (Google AI Studio'da geçerli model adını doğrula),
   `AI_DAILY_LIMIT`. Vault: `project_url` ve `cron_secret`.
4. Authentication > Sign In / Providers > Email: **Confirm email açık**, en kısa şifre 8,
   sızdırılmış şifre koruması açık.
5. Authentication > SMTP: özel gönderici (Resend, Postmark, Brevo vb.). Varsayılan Supabase
   posta sınırı kayıtları bozar; e-posta hız sınırını yükselt. İstersen CAPTCHA aç.
6. Authentication > URL Configuration: Site URL = 1.4'teki "E-posta doğrulandı" sayfası.
7. Authentication > Email Templates > **Reset Password**: bağlantı yerine Türkçe metin ve
   `{{ .Token }}` kodu koy; Email OTP uzunluğu 6 kalsın (uygulama 6 haneli kod bekler).
8. Database > Advisors: uyarı varsa geliştiriciye ilet.
9. Authentication > Users: demo kullanıcıyı oluştur (e-posta onaylı), sonra
   `supabase/seed_review_demo.sql` dosyasını çalıştır. **Gönderim günü seed'i yeniden çalıştır.**

## 3. Google

1. Gemini API faturalandırmasını aç; Google Cloud'da API anahtarına bütçe/kota uyarısı koy.
2. Google Health (isteğe bağlı): OAuth izin ekranını gizlilik adresi ve destek e-postasıyla
   Production'a al ve Health kapsamları için doğrulamayı tamamla. Bitmediyse mağaza yapısına
   `GOOGLE_IOS_CLIENT_ID` verme; uygulama Apple Sağlık ile çalışmaya devam eder.

## 4. Apple Developer portalı

1. App ID `com.sercinyous.kisiselasistan`: **HealthKit** yeteneği açık (Sign in with Apple yalnızca
   bölüm 0'daki ikinci yol seçilirse).
2. Push Notifications gerekmez (bildirimler yereldir).
3. App Store dağıtım profilini oluştur.

## 5. Codemagic

1. `app_secrets` grubundan `GEMINI_API_KEY`'i **sil** (doluysa derleme artık durur). Anahtar daha önce
   bir TestFlight/Ad-Hoc yapısına girdiyse Google AI Studio'da anahtarı döndür ve yeni anahtarı yalnızca
   Supabase secret'ına koy.
2. Code signing: App Store dağıtım sertifikası ve profili (Ad-Hoc değil); "Fetch profiles".
3. `ios-testflight` iş akışını çalıştır. Yapı numarası TestFlight ve App Store'daki en büyük numaranın
   bir fazlasıdır. Her onaylı sürümden sonra `pubspec.yaml` içindeki `version` artırılır.
4. Derleme günlüğünde `UYARI: AppDelegate` satırı olmamalı.

## 6. Gerçek cihaz denemesi (TestFlight)

1. Uygulama kapalıyken rutin, iş ve hatırlatıcı bildirimleri geliyor.
2. Uygulama kapalıyken bildirimdeki "Yaptım" basılınca, açılışta iş tamamlanmış görünüyor.
3. Demo hesapla '+' (AI ile ekle) ve İçgörü > "Raporu oluştur" çalışıyor.
4. Kayıt ol, onay e-postası geliyor, "Onay e-postasını yeniden gönder" çalışıyor.
5. "Şifremi unuttum": kod e-postası geliyor, yeni şifre kabul ediliyor.
6. Apple Sağlık izni isteniyor; adım, uyku, aktif enerji ve antrenman okunuyor.
7. Hesap silme yeni bir deneme hesabıyla çalışıyor.

## 7. App Store Connect

1. **Uygulama kaydı**: ad "Ritim", birincil dil Türkçe, bundle id `com.sercinyous.kisiselasistan`, SKU serbest.
2. **Kategori**: Birincil Sağlık ve Fitness, ikincil Verimlilik.
3. **Yaş derecelendirmesi**: anketi dürüstçe doldur; sağlık/beslenme konuları, kullanıcı içeriği
   (arkadaşlarla hikâye paylaşımı) var. Uygulama 13 yaş altı için değildir.
4. **Gizlilik politikası adresi** ve **destek adresi**: bölüm 1.3.
5. **App Privacy** (hepsi kimliğe bağlı, izleme yok, yalnızca uygulama işlevi için):
   - İletişim bilgisi: e-posta adresi, ad
   - Sağlık ve fitness: sağlık (adım, uyku, kilo, ölçüler, öğün), fitness (antrenman, aktif enerji)
   - Kullanıcı içeriği: fotoğraflar (profil, vücut fotoğrafı, hikâye), diğer içerik (işler, notlar), müşteri desteği
   - Tanımlayıcılar: kullanıcı kimliği
   - Kullanım verisi: ürün etkileşimi (AI kullanım sayaçları)
   - Tanılama: çökme verisi
6. **Metin taslakları (TR)**:
   - Alt başlık: `İşler, rutinler ve sağlık tek yerde`
   - Anahtar kelimeler: `ajanda,yapılacaklar,rutin,hatırlatıcı,alışkanlık,sağlık,kalori,su,adım,uyku`
   - Tanıtım metni: `Gününü tek ekrandan yönet: işler, rutinler, sağlık ve haftalık içgörüler.`
   - Açıklama:
     > Ritim; işlerini, rutinlerini, hatırlatıcılarını ve sağlık verilerini tek sade ekranda toplar.
     > "+" ile yazdığını yapay zekâ işe, öğüne ya da hatırlatıcıya çevirir. Su, öğün, kilo ve ölçülerini
     > kaydet; günlük ve haftalık raporlarla ilerlemeni gör. İstersen birkaç arkadaşınla hikâye paylaş.
     > Apple Sağlık ile çalışır (adım, uyku, aktif enerji ve antrenman okur; yazmaz).
     > Ritim tıbbi tavsiye vermez.
7. **Ekran görüntüleri** (6,9" ve 6,5", koyu tema, demo hesap): Kokpit, İşler, '+' AI ekle,
   Sağlık, İçgörü raporu, Giriş. Tarayıcı demosuyla üretilebilir (README > Tarayıcı demosu).
8. **İnceleme notları**: `docs/apple_inceleme.md` metnini yapıştır; demo hesabın e-posta ve şifresini gir.
   Hesap silmeyi denemek için incelemecinin yeni hesap açması istenir.
9. **Export compliance**: yalnızca standart HTTPS/TLS kullanılıyor; "muaf şifreleme" seç
   (`ITSAppUsesNonExemptEncryption = NO`).
10. Yapıyı sürüme seç, "Gönder" (Submit for Review).
