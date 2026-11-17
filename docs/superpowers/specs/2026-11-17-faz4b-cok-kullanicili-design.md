# Faz 4B — Çok kullanıcılı Ritim (tasarım)

Durum: onay bekliyor. Tarih: 2026-11-17. Önkoşul: Faz 4A (profil sütunları orada eklenir).

## Amaç ve neden
Uygulamayı 3–5 arkadaş da kullanacak: Google hesabıyla girsinler, ilk girişte kısa kılavuz ve sorularla kendi
hedeflerini kursunlar, birbirini uygulama içinden eklesinler. Sahibin işi (Pusholder adı, ekip, görev, not)
hiçbir başkasına görünmeyecek; yalnızca sağlık hedefi özeti, kişinin izin verdiği kadar paylaşılacak.

## Hedefler
1. Google ile giriş (Supabase Auth); e-posta/şifre girişi kalır.
2. Yeni hesapta tanıtım kılavuzu ve doldurulacak alanları soran ilk kurulum.
3. Tüm alanlarda taslaklar: formlarda şablon çipleri, yeni hesaba başlangıç seti, nötr varsayılanlar.
4. Arkadaşlar: uygulama içi istek (e-posta ile), gelen davet kutusu, kabul/red, hedef özetini paylaşma.
5. Gemini çağrısı sunucudan geçer; anahtar uygulamada olmaz; kişi başına günlük kota.
6. "Pusholder" ve sahibe özel her şey ürün kodundan kalkar.

## Hedef dışı
E-posta gönderimi (davet uygulama içidir); push bildirimi; mesajlaşma, gruplar, sıralama tabloları; App Store
yayını (gerekirse Apple ile giriş sonra); hesap silme; Google hesabı bağlama (`linkIdentity`); 10'dan fazla kullanıcı.

## Karşıt hedefler
- Sahibin işi, ekip adları, görev/not/kilo/öğün verisinin başka hesapta görünmesi.
- Bir e-postanın uygulamada hesabı olup olmadığının dışarıdan anlaşılması (e-posta sorgulama).
- Arkadaşların birbirinin ham tablolarını okuyabilmesi.
- Sahibin mevcut verisinin kaybolması ya da kullanılamaz hâle gelmesi.

## Kısıtlar
`CLAUDE.md` kuralları; alt bar 5 slot kalır. `service_role` anahtarı uygulamaya girmez. Google OAuth "Testing"
modunda arkadaşların Gmail adresleri Cloud Console'da test kullanıcısı olarak eklenmeli (sahip yapar).
Arkadaşların uygulamayı kurması TestFlight davetine bağlıdır (uygulama dışı, sahip yapar). Eski TestFlight
yapısı yeni şemayla bozulmamalı.

## Tasarım

### 1. Google ile giriş
- Giriş ekranı: "Google ile devam et" ana düğme, "E-posta ile giriş" ikincil.
- Akış: `google_sign_in` (temel kapsamlar: e-posta, profil) → kimlik belirteci →
  `supabase.auth.signInWithIdToken(provider: google, …)`. Gerekenler: Google Cloud'da Web OAuth istemcisi
  (`serverClientId`), Supabase > Authentication > Providers > Google'da bu istemci ve iOS istemcisi
  "Authorized Client IDs"te. Yeni isteğe bağlı değişken `GOOGLE_WEB_CLIENT_ID` (Codemagic); boşsa Google girişi
  gizlenir. Mevcut `GOOGLE_IOS_CLIENT_ID` aynı kalır.
- Hesap birleşmesi: Supabase aynı doğrulanmış e-postayı aynı kullanıcıya bağlar. Sahibin hesabı Gmail
  adresiyle açıldıysa Google girişi aynı veriyi açar; farklı e-postaysa Google yeni boş hesap açar ve sahip
  e-posta/şifreyle devam eder (README'de uyarı).
- Google Health bağlantısı (Faz 3) ayrı ve isteğe bağlı kalır.

### 2. Kılavuz ve ilk kurulum
- Tetik: `user_settings.onboarded_at is null`. Mevcut kullanıcılar için migration `onboarded_at = now()`
  (sahip zorlanmaz); Ayarlar'da "Kılavuzu yeniden göster".
- Adımlar: (1) 5 kartlık tanıtım: Kokpit, + ile iki ayrı giriş, Operasyon ve aylık sabit mantığı, Sağlık
  (trend ve denge), Raporlar ve Arkadaşlar; (2) sorular: görünen ad, boy, doğum yılı, cinsiyet (kadın/erkek/
  belirtmek istemiyorum), kilo, hedef kilo, amaç (ver/koru/al), isteğe bağlı iş tanımı ("ne iş yapıyorsun",
  AI'nın seni anlaması için); (3) hesaplanan önerilen hedefler (kalori = bazal × 1,4 − 500/0/+300; protein 1,8 g/kg;
  adım 8000; uyku 7,5 saat) düzenlenebilir; (4) bildirim izni ve sessiz saatler; (5) başlangıç rutinleri seçimi
  (taslak listesi); (6) sağlık kaynağı (Apple Health izni; Google Health sonra Ayarlar'dan).
- Sonuç tek kayıtla `user_settings`'e yazılır; seçilen rutinler eklenir; `onboarded_at = now()`.
- Yeni sütunlar (`display_name`, `work_description`, `onboarded_at`; `height_cm`, `birth_year`, `sex` 4A'da).

### 3. Taslaklar ve nötr varsayılanlar
- Formlarda şablon çipleri (Türkçe sabit listeler, `lib/core/templates/`): görev (randevu, ödeme, telefon,
  alışveriş…), rutin (su iç, yürüyüş, vitamin, haftalık plan, aylık fatura/kira), öğün (4A besin listesiyle
  "yumurta + ekmek" gibi), antrenman (yürüyüş, ağırlık, koşu, yoga, bisiklet). Seçince form dolar, düzenlenir.
- Şema varsayılanları nötrleşir: `team_members` boş, hedef ve kilo varsayılanları genel değerler (yalnızca
  yeni satırlar; sahibin satırı değişmez). Onboarding gerçek değerleri yazar.
- Pusholder kaldırma: `tasks.category`, `notes.category`, `routines.scope` değeri 'Pusholder' → 'İş';
  mevcut satırlar taşınır; eski TestFlight yapısı 'Pusholder' gönderirse bir tetikleyici 'İş'e çevirir
  (geçiş uyumu). `parsed_entry.dart`, `routine.dart`, `app_targets.dart`, AI komutu ve demo verisi nötrleşir;
  AI komutu `work_description` kullanır. Ekip bölümü isteğe bağlı kalır, varsayılan boş.

### 4. Arkadaşlar
- Giriş (A, kullanıcı seçti): Kokpit başlığında kişi ikonu (bekleyen davet rozeti) → Arkadaşlar ekranı;
  Ayarlar'da bir satır daha.
- Ekran: Davetler (kabul/reddet); Arkadaşlar (ad, bu haftanın adım/uyku/kalori hedef günleri; paylaşmayan
  "paylaşmıyor"); Arkadaş ekle (e-posta); giden bekleyen istekler (iptal); Paylaşım anahtarları (adım, uyku,
  kalori; varsayılan kapalı); arkadaşlıktan çık.
- Veri: `friend_requests` (gönderen, hedef e-posta küçük harf, hedef kullanıcı boş olabilir, durum, tarihler;
  bekleyen istekte tekil), `friendships` (sıralı çift), `friend_sharing` (kullanıcı başına üç anahtar).
  Tablolarda RLS yalnızca kendi satırı; arkadaşlar arası ham erişim yok.
- İşlevler (security definer, `authenticated`): `send_friend_request(e-posta)` — her durumda aynı cevap
  ("İstek gönderildi"), kendine ve tekrar isteği kabul etmez, kullanıcı başına en çok 20 bekleyen;
  `my_incoming_requests()` — doğrulanmış e-posta ya da hedef kullanıcı eşleşmesiyle (hesabı sonradan açılan
  kişi de görür: "hesabına invite düşsün"); `respond_friend_request(id, kabul)`; `friend_goal_summary(arkadaş,
  hafta)` — yalnızca arkadaşlıkta ve ilgili anahtar açıkken tutturulan gün sayıları, başka hiçbir alan.
- Davet sayısı uygulama açılınca ve öne gelince yenilenir; push yok.

### 5. Gemini sunucudan
- Edge Function `ai-proxy`: oturum belirteci zorunlu; istemci Gemini `generateContent` gövdesini (komut ve
  şema) üretmeye devam eder, mevcut ayrıştırma ve testler kalır; fonksiyon modeli kendisi seçer
  (`GEMINI_MODEL` secret), gövde boyutunu ve `maxOutputTokens`'ı sınırlar, günlük kota uygular (`ai_usage`
  tablosu; varsayılan 100/gün/kişi, secret ile ayarlı), aşımda 429 ve Türkçe mesaj döner. `GEMINI_API_KEY`
  yalnızca fonksiyon secret'ında.
- İstemci: `GEMINI_API_KEY` dart-define boşsa proxy modu; doluysa doğrudan çağrı (geçiş için). Sahip proxy'yi
  doğrulayınca anahtarı Codemagic'ten siler. Hata eşleme: 401 oturum, 429 kota, 402 fatura, 404 "AI sunucusu
  kurulmamış".

## Yaklaşımlar
- Davet: (a) uygulama içi istek — **kullanıcı seçti**; (b) e-posta gönderimi: gönderici hesabı ve domain gerekir;
  (c) davet kodu.
- Giriş: (a) yerel `google_sign_in` + `signInWithIdToken` — **seçildi**; (b) tarayıcılı OAuth: kötü akış.
- Arkadaş verisi: (a) security definer özet işlevi — **seçildi**, sızıntı yüzeyi en küçük; (b) arkadaşa tablo
  okuma izni: ham veriye erişim.
- Gemini: (a) ince proxy — **seçildi**; (b) komut üretimini sunucuya taşımak: Dart→TS port, büyük iş;
  (c) anahtar uygulamada: arkadaşların telefonunda.
- Pusholder: (a) herkes için nötr 'İş' — **seçildi**; (b) sahip bayrağıyla gizlemek; (c) kullanıcıya özel etiket adı.

## Kullanıcının kararları
Pusholder ve ekip kimseye görünmesin; iş detayı paylaşılmasın; denge alanlarını sisteme ekle; Gemini maliyeti
kendisinden kesilebilir (3–5 kişi); kayıtta kılavuz ve sorular; Arkadaşlar girişi Kokpit başlığı (A); davet
uygulama içi istek olarak hesaba düşer.

## Benim kararlarım (itiraz edilebilir)
Paylaşılan tek şey sağlık hedef günleri, varsayılan kapalı; ince proxy; nötr 'İş' kategorisi ve geçiş tetikleyicisi;
Google hesap bağlama kapsam dışı; önerilen hedef formülleri; 100/gün kota; push yok.

## Sahip kurulumları (uygulama dışı)
Google Cloud: Web OAuth istemcisi, arkadaşların Gmail'leri test kullanıcısı. Supabase: Google sağlayıcısı,
Edge Function dağıtımı (`ai-proxy`, `generate-reports`), secret'lar. Codemagic: `GOOGLE_WEB_CLIENT_ID`.
App Store Connect: arkadaşları TestFlight'a ekleme.

## Builder'a bırakılan
Ekran düzenleri, şablon listelerinin içeriği, tanıtım metinleri, rozet ve boş durum tasarımı, SQL ayrıntıları,
test yazımı, `CLAUDE.md` ve `KARARLAR.md` güncellemeleri ("tek kullanıcılı" ifadesi).

## Doğrulama
`flutter analyze`, tüm testler, SQL testleri (RLS ve işlevlerde yetki sınırları dahil: bir kullanıcı başkasının
satırını ve ham verisini okuyamaz), Edge Function testleri, web demo. Gerçek Google girişi, iki hesapla arkadaşlık
ve kota gerçek projede denenmeden bitmiş sayılmaz.
