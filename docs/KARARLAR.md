# Kararlar ve kalıcı notlar

Otomatik hafıza bulut oturumlarında taşınmaz; kalıcı kararlar burada tutulur. Yeni karar
alınınca bir satır eklenir. Şema için tek kaynak `supabase/schema.sql`, mimari için `docs/SPEC_*.md`.

## Ürün
- **Ritim** (Kişisel Asistan): tek kullanıcılı iOS uygulaması. Pusholder operasyonu (editörler Duhan, İlhan,
  Mehmet, Sedat; vardiya ve görevler) ile kişisel sağlık (84,5 → 78 kg hedefi, antrenman, makrolar) bir arada.
- App Store Connect adı "Ritim: Rutin, İş ve Sağlık"; bundle id `com.sercinyous.kisiselasistan`;
  SKU `kisiselasistan-ios`.
- Aylık sabitler (ör. ayın 15'i maaş ödemesi) bitiş gününden 3 gün önce görünür, gün geçince "gecikti" olur,
  ay sonunda "yapılmadı" diye kapanır. Tarih hafta sonuna denk gelse de kaymaz.
- Tek seferlik olaylar (dişçi, kontrol) ayrı görev olarak girilir; rutinler günlük, haftalık ve aylık tekrar eder.
- AI girişi iki ayrı kapı: **İş** ve **Sağlık ve beslenme**. İkisi birbirine karışmaz.
- Kokpit Gün ve Ay görünümü; Ayarlar'da hedefler (kilo, kalori), bildirimler, görünüm, ekip, hesap.
- Günlük ve haftalık raporlar sunucuda otomatik üretilir (Edge Function `generate-reports` + pg_cron).
  Dağıtım (fonksiyon, secret, Vault, `supabase/cron.sql`) kullanıcı tarafında bekliyor; o zamana kadar
  Raporlar sekmesi boş kalır.

## Tasarım
- İki tema: saf OLED siyah (varsayılan) ve açık. Ayrıntı `CLAUDE.md` §2 ve `docs/SPEC_FAZ3.md` §10.
- Alt bar yüzen cam kapsül, etiketsiz, 5 slot. Yeni sekme eklenmez.
- Bir skill'in önerisi `CLAUDE.md` ile çelişirse `CLAUDE.md` kazanır (ör. ham renk ve `Theme.of(context)`
  yerine `AppColors` getter'ları).

## Yapay zeka (Gemini)
- Model `gemini-3.8-flash`, `thinkingLevel: low`, `temperature` verilmez, `responseSchema` kullanılır.
  Model kalkarsa uygulama yeniden yazılmaz: `GEMINI_MODEL` dart-define ile değişir.
- Hata 404 = model bulunamadı. Hata 402 = ön ödemeli bakiye ya da fatura bitti (AI Studio > Billing).

## Dağıtım
- Codemagic: `ios-testflight` (main'e push) ve `ios-adhoc` (elle). `ios/` CI'da `flutter create` ile üretilir,
  `tool/configure_ios.sh` yamalar. Derleme numarası = TestFlight'taki son numara + 1.
- Ortam grubu `app_secrets`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY`, isteğe bağlı `GEMINI_MODEL`,
  `GOOGLE_IOS_CLIENT_ID`. `SUPABASE_URL` yalnızca `https://<ref>.supabase.co` biçiminde olmalı (yol eklenmez).
- App Store Connect bağlantısı: Codemagic'te `kisisel-asistan-asc`.

## Sağlık verisi kaynağı
- Varsayılan Apple Health (HealthKit). Fitbit Web API 2 Kas 2026'da kapandı; halefi Google Health API
  (`https://health.googleapis.com/v4/`). Google OAuth "Testing" modunda yenileme belirteci yaklaşık 7 günde
  biter; uygulama "Google'a yeniden bağlan" durumunu gösterir.
- Aynı anda tek kaynak veri yazar (çift sayım olmasın).
- Google oturumu: iOS GIDSignIn tek yuvalı olduğundan eşzamanlı sessiz geri yüklemeler tek yerel çağrıda toplanır; `connect`/`disconnect`
  aynı yuvayı bekler. Sessiz yolda yalnızca `org.openid.appauth.oauth_token` hatası "yeniden bağlan" (expired) sayılır; ağ/5xx/JSON
  olmayan yanıt ve tanınmayan `PlatformException` geçici hatadır (network).
- Google antrenmanları kullanıcının kendi (manual/ai) kayıtlarıyla çift sayılmaz: aynı oturum (çakışan aralık, ya da ≤ 60 dk boşluk ve
  uyumlu tür) aktarılmaz; kullanıcı kaydı kalır, çiftlenen Google kopyası silinir. Ev işi, bahçe, meditasyon, düz yürüyüş ve 10 dk'dan
  kısa oturumlar aktarılmaz.

## Faz 4A: sağlık detayı ve düzenleme
Ayrıntı: `docs/superpowers/specs/2026-11-17-faz4a-saglik-detay-design.md` (Netleştirmeler bölümü geçerli), plan
`docs/superpowers/plans/2026-11-17-faz4a-saglik-detay.md`, kullanıcıya dönük özet README "Trendler ve enerji dengesi".
- **Hedef tutturma eşikleri tek yerde** (`GoalRules`): kalori hedefin %85–%110'u (uçlar dahil), protein ≥ %90
  (ikisi Raporlar ile aynı), adım ≥ %100, uyku ≥ hedefin %90'ı (saatler uykuyu eksik ölçer). Adım ve uyku için
  Raporlar'da kural yoktur; bunlar Trend'e özgü yeni kurallardır. Karşılaştırmalar tam sayı aritmetiğiyle yapılır;
  kalori ve protein (double) önce veritabanı ölçeğine (onda bir) yuvarlanır, böylece 1 ondalıklı satırların toplamı
  SQL'in tam `numeric` toplamıyla (Raporlar) aynı yana düşer. Protein hedefi 0 ise Trend'de protein satırı gösterilmez.
  Faz 4B'nin sunucu özeti aynı eşikleri SQL'de yazarsa iki tarafa eşlik testi konur.
- **Verisiz gün paydada yok** ve "veri yok" diye ayrı sayılır; kimse veri girmediği için "tutturamadı" olmaz.
  Raporlar'ın `form.rate` paydası değişmedi (geçen gün sayısı); iki yüzde bu yüzden bire bir aynı olmaz.
- **Bugün "devam ediyor"**: hedefi tutturduysa tutan gün, yoksa paydada ve ortalamada yok. Verisiz gün seriyi
  bozmaz; veri olup tutturulmayan gün bozar. "Mevcut seri" yalnızca geçerli dönemde, geçmiş dönemde dönem içi
  "en uzun seri". Hafta Pazartesi başlar, ay takvim ayıdır, gelecek günler hesaba girmez.
- **Trend yeri**: Sağlık kartlarından açılan tek sayfa (Adım | Uyku | Kalori, Hafta | Ay). Raporlar sekmesine
  ve sunucu raporlarına trend ya da denge eklenmedi. Kartlardaki 7 günlük çubuk grafiğin kendi dokunması kapalıdır
  (fl_chart dokunuşu yutardı); kartın her yeri Trend'i açar, gün değerleri Semantics etiketinde ve Trend'dedir.
- **Besin listesi paketli JSON** (`assets/data/foods_tr.json`): sunucusuz, çevrimdışı, demoda ve testte aynı dosya.
  Satırlar USDA FoodData Central ve TürKomp ile çapraz doğrulanır (`iki kaynak`); yalnızca bir kaynakta olup yaygın
  değerlerle ±%5 uyuşan satır `tek kaynak`; doğrulanamayan satır listeye girmez, değer uydurulmaz. Atwater testi:
  `|kcal − (4·protein + 4·karb + 9·yağ)| ≤ max(%15·kcal, 10 kcal)`. **Durum: liste boş (`[]`)**: bu ortamdan her
  iki kaynağa ağ erişimi yoktu. Doldurulana kadar `test/foods_data_test.dart` "en az 60 satır" testi liste boşken (`[]`)
  atlanır, böylece Codemagic "Testler" adımı IPA derlemesini durdurmaz; 1-59 satırda yeniden kırmızı olur, 60 satırdan
  itibaren normal çalışır. Bekleyen iş: listeyi USDA FDC ve TürKomp'tan doldurmak. Öğün formu liste boşken "Listede yok" der, elle giriş çalışır. Tarayıcı demosu boş listede
  `lib/demo/demo_foods.dart` örnek listesine düşer (`verification: 'demo'`, kaynak "doğrulanmamış").
- **Öğün formu**: arama Türkçe karakter ve büyük/küçük harf duyarsız (`ç→c ğ→g ı→i ö→o ş→s ü→u`, `İ/I/ı`
  hepsi `i`); gram alanı virgül kabul eder; boş/0/negatif gramda hesap uygulanmaz. Kayıt `source = 'manual'`
  kalır, `quantity_text` "2 adet · 100 g".
- **Profil** (`user_settings.height_cm` 100–250, `birth_year` 1900–2100, `sex`): `female` | `male` |
  `unspecified`, `null` = henüz cevaplanmadı; profil eksik = üçünden biri `null`. Tanınmayan değer okunurken
  `null` olur. Faz 4B onboarding'i aynı alanları yazar.
- **Enerji dengesi**: bazal Mifflin-St Jeor (erkek +5, kadın −161, belirtmeyen −78); kilo = o güne kadarki son
  tartı, yoksa `start_weight_kg`. Yakılan = bazal + aktif kalori; aktif kalori yoksa/0 ise antrenman kayıtlarının
  kalorisi yedek (çift sayım yok) ve "aktif kalori verisi yok" notu. Bugün için bazal günün geçen oranıyla
  ("Şu ana kadar"; saat eşiği yok). Bantlar (`EnergyBands`): net ≤ −1000 çok yüksek açık (övgü yok), −1000…−150
  yağ yaktın, ±150 yerinde saydın, +150…+500 biraz kaçırdın (telafi: 3,5 MET yürüyüş dakikası ya da yarın o kadar
  az), ≥ +500 fazla geçti. Tahmini yağ = Σnet ÷ 7700 kg. 18 yaş altına yorum yok, yalnızca sayılar.
  Çok yüksek açık günü detayda da övülmez: çubuk uyarı (amber) renginde, dönemde böyle gün varsa "Tahmini yağ" çipi
  nötr ve "yeterince yediğinden emin ol" notu çıkar. Enerji sağlayıcıları öğün, antrenman ve kilo kaydı yazan her
  yolda tazelenir; AI giriş (+) dahil (`QuickAddController._refreshAfterSave`).
- **Öğünü olmayan gün yorum üretmez** ("Henüz öğün girilmedi"), grafikte boşluk olur, hafta/ay toplamına girmez;
  toplam yalnızca öğünü olan N gün üzerindendir, 7 güne ölçeklenmez. Tüm sayılar "tahmini"dir, tıbbi tavsiye
  değildir.
- **Düzenle / sil**: her liste satırında uzun basış menüsü (Düzenle / Sil) ve sola kaydırarak sil (onaylı,
  "Vazgeç" satırı geri getirir); ortak bileşen `lib/core/widgets/item_actions.dart`. Kokpit (gün, ay, ay günü
  listesi), Operasyon (üç nokta menüsü kalır), öğün ve antrenman satırları kapsanır; silme Operasyon'daki mevcut
  yolu kullanır, bildirim planı ve sağlayıcılar tazelenir. "Görev başlıkları" = başlığı düzenle/sil olarak
  yorumlandı. Rutin silinince tamamlama geçmişi de gider (mevcut cascade). Kaydırarak silmede silinecek kaydın
  `onDelete`'i onay beklenmeden önce yakalanır (onay açıkken liste kayarsa komşu silinmesin); anahtarsız listelerde
  satır sarmalayıcıları kayıt kimliğiyle anahtarlanır.
- **Tarayıcı demosu**: 60 günlük adım/uyku/kalori/öğün geçmişi, dolu profil (180 cm, 1990, erkek). Son üç haftadan
  eski günlerin bazısında sağlık ya da öğün verisi bilerek yoktur (boş gün durumları görünsün); son üç hafta
  Raporlar demosuyla tutarlı kalsın diye eksiksizdir.

## Güvenlik kuralları
- `service_role` ya da secret anahtar uygulamaya, repoya, sohbete girmez. Yalnızca anon/publishable anahtar.
- `.p8`, `.p12`, parola ve anahtar değerleri sohbete yapıştırılmaz; yalnızca Codemagic'e girilir.
- Gerçek Google client id repoya gömülmez; yalnızca Codemagic'te `GOOGLE_IOS_CLIENT_ID`.
- Supabase MCP salt-okunur ve tek projeye kilitli (`.mcp.json`); yazan araçlar `.claude/settings.json` ile
  engelli. Yalnızca şema, politika, advisor ve log sorgulanır; kullanıcı tablolarında SELECT çalıştırılmaz.
  Salt-okunur kip prompt injection ile veri sızmasını engellemez, bu yüzden bu kural elle uygulanır.

## Süreç
- Hız kuralı: dosya başına analyze/test yok, iş bitince tek seferlik kontrol.
- Son kapsamlı inceleme yapı kurulduktan sonra yapılır.
- Bekleyenler: Gemini faturası, otomatik rapor dağıtımı, özel uygulama ikonu, Google Health PR'ı, besin listesinin
  (`assets/data/foods_tr.json`) USDA FDC ve TürKomp'tan doğrulanarak doldurulması, Faz 4A sayılarının gerçek
  cihazda Fitbit/Sağlık uygulamasıyla karşılaştırılması.
