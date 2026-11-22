# Kararlar ve kalıcı notlar

Otomatik hafıza bulut oturumlarında taşınmaz; kalıcı kararlar burada tutulur. Yeni karar
alınınca bir satır eklenir. Şema için tek kaynak `supabase/schema.sql`, mimari için `docs/SPEC_*.md`.

## Ürün
- **Ritim** (Kişisel Asistan): tek kullanıcılı iOS uygulaması. Pusholder operasyonu (editörler Duhan, İlhan,
  Mehmet, Sedat; vardiya ve görevler) ile kişisel sağlık (84,5 → 78 kg hedefi, antrenman, makrolar) bir arada.
- Faz 4B: 'Pusholder' ve sahibe özel her şey ürün kodundan kalktı. Görev/not kategorisi ve rutin kapsamı herkes için
  'İş'; eski 'Pusholder' değeri yalnızca okunurken (`AppTargets.normalizeWork`, AI yanıtı çözümü) 'İş'e eşlenir,
  asla yazılmaz. Ekip isteğe bağlıdır, varsayılanı boştur; kilo hedefi varsayılanı 70/70'tir. AI komutu kullanıcının
  `work_description` alanını (tek satır, en çok 300 karakter, yalnızca bağlam) kullanır. Demo verisi nötrdür.
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
- Faz 4B: AI çağrıları sunucudaki Edge Function `ai-proxy`'den geçer (`GEMINI_API_KEY` yalnızca fonksiyon secret'ında;
  modeli `GEMINI_MODEL` secret'ı seçer; günlük kota `AI_DAILY_LIMIT`, varsayılan 100/kişi, `ai_usage` kind `ai`).
  Uygulamada `GEMINI_API_KEY` dart-define boşsa proxy modu, doluysa doğrudan çağrı (geçiş). Proxy 429 = günlük kota
  (yeniden denenmez); Gemini'nin kendi 429/5xx'i 503, 401/403/404'ü 502 olarak iletilir; 402 aynen. Yeniden
  denemeler kotadan düşer. "Raporu yeniden oluştur" günde 10 (`ai_usage` kind `report_regen`); rapor zamanlayıcısı
  yalnızca `onboarded_at` dolu kullanıcılar için üretir.

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

## Faz 4B: ilk kurulum, kılavuz ve şablonlar
Ayrıntı: `docs/superpowers/specs/2026-11-17-faz4b-cok-kullanicili-design.md` (Netleştirmeler bölümü geçerli).
- **Kapı**: giriş sonrası `user_settings.onboarded_at` boşsa `OnboardingGate` kılavuz ve soruları gösterir, doluysa ana kabuğu.
  Kapı kullanıcı kimliğiyle anahtarlıdır (hesap değişince önceki kullanıcının değeri sızmaz) ve ayar satırı yeniden
  okunurken ana kabuğu sökmez. Ayarlar okunamazsa "Tekrar dene" gösterilir; mevcut hesaplar zorlanmaz (migration `now()` yazar).
- **Adımlar**: 5 kartlık tanıtım (atlanabilir) → sorular → önerilen hedefler → bildirim izni + sessiz saatler → başlangıç
  rutinleri → sağlık kaynağı (Apple Health izni; Google Health sonra Ayarlar'dan). Zorunlu: görünen ad, boy, doğum yılı,
  cinsiyet, kilo, amaç; hedef kilo boşsa mevcut kilo, iş tanımı isteğe bağlı. Doğum yılı üst sınırı bu yıl − 10.
- **Öneri formülü** (`GoalSuggestion`, tıbbi tavsiye değil): kalori = 4A bazalı × 1,4 + (ver −500 / koru 0 / al +300);
  protein 1,8 g/kg; yağ kalorinin %27'si, karbonhidrat kalan; adım 8000; uyku 450 dk. Açık hedefi 1200 kcal altına
  inmez ve 18 yaş altına açık uygulanmaz (4A reşit olmayana açık hedefi koymaz). Hedefler düzenlenebilir; cevaplar
  değişmedikçe düzenleme korunur, hesabı etkileyen cevap değişince yeniden önerilir.
- **Yazım**: tartı kaydı (kilo cevabı) → seçilen rutinler (kişisel kapsam) → EN SON tek `user_settings` kaydı
  (`onboarded_at = now()`). Ayar yazılana kadar kurulum bitmiş sayılmaz; hatada yeniden deneme önceki adımları
  tekrarlamaz. Başlangıç rutinleri varsayılan seçili değildir; hiçbiri seçilmezse boş başlanır.
- `UserSettings.toMap` `onboarded_at`'i yalnızca doluysa yazar (eski bir kopya kurulumu geri almasın); görünen ad ve iş
  tanımı boşsa null yazılır. Ayarlar > Profil'de ikisi de düzenlenir; ayar satırı yoksa istemci yalnızca `user_id` açar
  (varsayılanları veritabanı verir).
- **Kılavuzu yeniden göster** (Ayarlar): yalnızca 5 tanıtım kartı; hiçbir şey yazmaz.
- **Şablonlar** (`lib/core/templates/`): görev, rutin, öğün, antrenman sabit Türkçe listeleri; yeni kayıt formlarında
  "Şablondan başla" çipleri (düzenlemede yok). Seçince form dolar, her alan düzenlenir. Öğün şablonlarının kalori ve
  makroları yaygın porsiyonlar için YAKLAŞIKTIR (formda belirtilir); paketli besin listesinin doğrulanmış satırlarının
  yerini tutmaz.

### Faz 4B: çok kullanıcı, arkadaşlar, ai-proxy
- **Kayıt** (2026-11-22 itibarıyla geçersiz, aşağıdaki açık kayıt kararına bak): "Allow new users to sign up" AÇIK; `auth.users` üzerindeki `signup_invite_gate` tetikleyicisi davetsiz e-postayı reddeder ("Bu e-posta için davet yok"). İsteğe bağlı Before User Created kancası `public.hook_before_user_created` (okunur 403). Sahip elle hesap açacaksa tetikleyiciyi geçici kapatır, işi bitince açar.
- **Davet eşleşmesi** yalnızca doğrulanmış e-posta (`email_confirmed_at`) ya da hedef kullanıcı ile; Supabase'te "Confirm email" açık önerilir (kapalıysa davet edilen adresle kayıt olan daveti görür; sızıntı açılan anahtar kadar).
- **Arkadaşlık**: istek e-postayla, her durumda "İstek gönderildi"; en çok 20 bekleyen istek; kabulde sıralı çift `friendships`. Paylaşım `friend_sharing` anahtarları (adım/uyku/kalori), hepsi varsayılan kapalı. Arkadaş yalnızca hedef tutan gün sayısını görür (`friend_goal_summary`, Pzt–Paz, her zaman 3 satır, paylaşılmıyorsa `shared=false`); ham veri asla. İstemci yazımı yalnızca kendi `friend_sharing` satırı; geri kalanı RPC.
- **ai-proxy**: Gemini çağrıları Edge Function'dan geçer; anahtar yalnızca secret'ta (`GEMINI_API_KEY`, `GEMINI_MODEL`, `AI_DAILY_LIMIT` varsayılan 100). Günlük kota `consume_ai_quota` (atomik, kullanıcı saat dilimine göre); "Raporu yeniden oluştur" günde 10. Hatalar Türkçe: 401/429/402/404. `GEMINI_API_KEY` dart-define boşsa istemci proxy kullanır.
- **Nötr 'İş'**: 'Pusholder' herkes için 'İş' olur; eski değer yalnızca okunurken eşlenir, şema tetikleyicisi yazımı çevirir. Yeni satır varsayılanları nötr (70 kg, 2000 kcal, 120 g protein, 8000 adım, 450 dk uyku); ekip varsayılan boş. `work_description` AI komutuna veri olarak eklenir.
- **Onboarding**: bkz. yukarıdaki Faz 4B bölümü; mevcut hesaplar migration ile `onboarded_at = now()` alır. Raporlar yalnızca `onboarded_at` dolu kullanıcılara üretilir.
- **Google giriş**: bkz. Güvenlik kuralları; Gmail test kullanıcıları Google Cloud'da elle eklenir.
- **Besin listesi**: `foods_tr.json` 198 satır, USDA SR Legacy 2018-04'ten, hepsi `tek kaynak`. TürKomp bu ortamdan erişilemedi (bağlantı kurulamadı), hiçbir satırda TürKomp kodu yok; çapraz doğrulama yapılmadı. Atwater'ı geçemeyen 12 satır çıkarıldı.
- **Dağıtım sırası**: yeni yapı TestFlight'a düşünce SQL çalıştırılır (eski yapı 'İş' satırlarını kapsam filtresinde göremeyebilir; kabul edildi).

## Güvenlik kuralları
- `service_role` ya da secret anahtar uygulamaya, repoya, sohbete girmez. Yalnızca anon/publishable anahtar.
- `.p8`, `.p12`, parola ve anahtar değerleri sohbete yapıştırılmaz; yalnızca Codemagic'e girilir.
- Gerçek Google client id repoya gömülmez; yalnızca Codemagic'te `GOOGLE_IOS_CLIENT_ID`.
- Google ile giriş (Faz 4B): `google_sign_in` → kimlik belirteci → `signInWithIdToken`; Web istemci kimliği yalnızca Codemagic'te `GOOGLE_WEB_CLIENT_ID` (boşsa Google düğmesi gizli). Tek `GoogleSignIn.instance.initialize` çağrısı Google Health ile paylaşılır; uygulamadan çıkış Google yuvasına dokunmaz; Health yalnızca Ayarlar'dan bağlanınca bağlı sayılır.
- Supabase MCP salt-okunur ve tek projeye kilitli (`.mcp.json`); yazan araçlar `.claude/settings.json` ile
  engelli. Yalnızca şema, politika, advisor ve log sorgulanır; kullanıcı tablolarında SELECT çalıştırılmaz.
  Salt-okunur kip prompt injection ile veri sızmasını engellemez, bu yüzden bu kural elle uygulanır.
- Görev kategorileri kullanıcı yönetimlidir: `user_settings.task_categories` jsonb (null = İş/Ekip/Finans/Kişisel);
  aç/kapat, taslak ve özel kategori Ayarlar'da; `tasks.category` 1..40 karakter serbest; AI yalnızca açıkları önerir.

## Süreç
- Hız kuralı: dosya başına analyze/test yok, iş bitince tek seferlik kontrol.
- Son kapsamlı inceleme yapı kurulduktan sonra yapılır.
- Bekleyenler: Gemini faturası, `ai-proxy` ve `generate-reports` dağıtımı, özel uygulama ikonu, Google Health PR'ı,
  besin listesinin TürKomp ile çapraz doğrulanması (erişim gelince), Faz 4A sayılarının gerçek cihazda
  karşılaştırılması, `flutter analyze`/`flutter test` ilk tam koşusu, gerçek Google girişinin iki hesapla denenmesi,
  arkadaş akışının iki hesapla uçtan uca denenmesi.
- Günlük rapor 00:15'te (İstanbul) biten gün için üretilir; geç gelen veri raporu dirty işaretler, saatlik refresh sayıları yeniler; AI yorumu yalnızca ai_basis değişince ve report_refresh kotası (6/gün) içinde.
- Sağlık yazmaları işlem başında kullanıcıyı sabitler (HealthWriteGuard; her await sonrası kullanıcı/kaynak/Google nesli denetlenir); Google Health izleri Supabase kullanıcısına göre saklanır, kullanıcı değişince açık yeniden bağlanma gerekir, anahtarın hesabı kayıtlı hesapla eşleşmeli; daily_health_metrics.source tutulur, grafikler seçili kaynağı okur (kaynaksız eski satır = Apple Health), aynı kaynağın sıfır okuması yalnızca var olan satırı günceller, HealthKit geçmiş gün sıfırı yazılmaz.
- Rapor yenileme kiralıdır: claim_dirty_reports dirty'yi temizlemez, claim_token/claimed_at ile 15 dk kiralar; dirty yalnızca başarılı kayıtta ve dirty_version değişmediyse temizlenir (karşılaştır-ve-temizle), hata kirayı bırakır, ölü işçinin kirası süre dolunca yeniden alınır.
- Arkadaş paylaşımı iki katmanlı: share_steps/sleep/calories yalnızca hedef gün sayısını açar; ham değerler ayrı açık onayla (friend_sharing.share_details, varsayılan false, eski anahtardan geri doldurulmaz) ve sunucuda (friend_leaderboard) uygulanır. Seçili sağlık kaynağı user_settings.health_source'ta tutulur (boş = Apple); rapor, sıralama ve hedef gün sayısı (friend_goal_summary) yalnızca o kaynağın satırını okur (kaynaksız satır = Apple); kaynak değişince kullanıcının mevcut raporları dirty işaretlenir.
- Apple Health içe aktarma onayı uygulama kullanıcısına aittir (`apple_health_consent:<uid>`); cihazdaki HealthKit izni yetmez. Onaysız kullanıcı için HealthKit okunmaz, bugün/geçmiş gün yazılmaz (ConsentGatedHealthSource + HealthWriteGuard); onay Sağlık kartındaki "Bu hesap için onayla" ya da onboarding Apple adımıyla verilir. Eski kurulumlarda kimse kendiliğinden onaylı sayılmaz. Kaynak tercihi de kullanıcıya göre (`health_source:<uid>`).
- Yol haritası: `docs/yol_haritasi.html` tek kaynak; her özellik/düzeltmede güncellenip aynı Artifact adresine yeniden yayınlanır (CLAUDE.md §7).
- Hesap silme sunucuda: delete-account Edge Function (JWT doğrulanır, service_role yalnızca fonksiyon ortamında) arkadaşlıkları iki yönden ve kullanıcıya giden/gelen tüm friend_requests'i açıkça siler, sonra auth.admin.deleteUser; geri kalan tüm public satırları auth.users ON DELETE CASCADE ile gider (account_delete_test bunu tüm public uuid sütunlarında doğrular). İstemci ardından bildirim kuyruğunu kapatır, cihazdaki `*:<uid>` tercihlerini siler ve çıkış yapar. Hata takibi ve 'Sorun bildir' dış servis değil Supabase: public.app_errors (günde kişi başı 50, yalnızca ekleme) ve public.feedback (yalnızca ekleme); kullanıcı kendi kaydını da okuyamaz. Gizlilik metni docs/gizlilik.md ve lib/features/settings/domain/privacy_text.dart'ta aynı tutulur.
- İlk kurulum sırası (Faz 5): tanıtım → profil (ad, doğum yılı, isteğe bağlı cinsiyet, saat dilimi) → sağlık kaynağı → boy/kilo (bu kurulumda Apple Sağlık izni verildiyse son ölçümle ön dolu) → hedefler (VKİ, hareket düzeyi, Mifflin–St Jeor × katsayı, protein 1,6 g/kg, adım 8000, hedef kilo sağlıklı VKİ'ye göre) → rutinler + bildirimler. Hareket düzeyi `user_settings.activity_level`; saat dilimi `complete_onboarding` gövdesindeki `timezone` ile yazılır. `UserSettings.defaults()` schema.sql varsayılanlarına eşittir (protein 120, karbonhidrat 220, adım 8000).
- Faz 5 Hatırlatıcılar: `reminders` + `reminder_done` (bileşik FK, sahip RLS); bildirimler eşitleme kuyruğunda resync'ten sonra planlanır (anahtar `reminder:<id>[:gün]`, yük `reminder:<id>:<sahip>`); bildirimdeki "Yaptım" kalıcı kutuya yazılır, yalnızca sahibi oturumdayken işlenir; AI hızlı eklemede hatırlatıcılar RPC dışında ayrı insert ile yazılır.
- Faz 5 sağlık ekleri: su (water_logs, user_settings.daily_water_ml=2000) ve haftalık check-in (weekly_checkins) ayrı tablolar, sahip RLS; rapor metriklerine (report_period_metrics) eklenmedi. Kilo hedefi tahmini son 8 haftanın doğrusal regresyonuyla, istemcide hesaplanır.
- Uygulama ikonu: mint topaç (ios_setup/AppIcon.appiconset, tek 1024 px); configure_ios.sh derlemede kopyalar.
- Topaç animasyonu: lib/core/widgets/ritim_top (spin/settle/idle, hareket azaltmada durağan); açılış, AI hızlı giriş ve ilk kurulum karşılamasında.
- Sadeleştirme: sekmeler Kokpit / İşler / + / Sağlık / İçgörü. Kokpit yalnızca bugün (kalori, işler/adım/uyku, su, en çok 5 satırlık "Bugünün işleri"); Ay görünümü İşler › Takvim'e, ay özeti İçgörü › Ay'a taşındı. Ayarlar yerine profil ikonundan açılan Hesap menüsü ve 5 alt sayfa (her sayfa yalnızca kendi alanlarını kaydeder). Sağlık Özet/Beslenme/Hareket; İşler Görevler/Rutinler/Notlar, günlük ve aylık rutinler Rutinler'den işaretlenir. Kart iç boşluğu 20; yeni renk rolleri sleep, water.
- Sağlık kaynağı: aynı anda yalnızca biri etkin; Bağlantılar'da seçili olmayan kaynak "Pasif" etiketiyle soluk görünür ve okunmadığı yazılır.
- Açık kayıt (2026-11-22): davet kapısı kaldırıldı; herkes Google ya da e-posta (uygulamada "Kayıt ol") ile hesap açar. `signup_invite_gate` tetikleyicisi Supabase'de silinemediği için kalır, `enforce_signup_invite()` ve `hook_before_user_created()` her zaman izin verir; `has_pending_invite` silindi. Arkadaşlık istekleri değişmedi (kayıtsız e-postaya gönderilen istek kayıttan sonra görünür).
- Profil avatarı (2026-11-22): üç tür — baş harfler (varsayılan, AppColors rol rengiyle), 16 maskot (assets/mascots, flutter_svg) ya da fotoğraf (image_picker; Dart'ta ortadan kare kırpılıp 512 px JPEG). Seçim `user_settings.avatar_kind/avatar_mascot/avatar_color/avatar_version` sütunlarında, yalnızca `saveAvatar` ile yazılır (genel ayar kaydı dokunmaz). Fotoğraf özel `avatars` kovasında `<uid>/avatar.jpg` (upsert); sahip kendi klasörüne yazar, kabul edilmiş arkadaşlar `avatar_can_read` ile okur; istemci imzalı adresi (kullanıcı, sürüm) başına oturum boyunca önbellekte tutar. `my_friends` ve `friend_leaderboard` avatar alanlarını döndürür (dönüş tipi değiştiği için her tanımdan önce drop). Hesap silme `avatars/<uid>/` dosyalarını da siler. Web demosunda fotoğraf seçenekleri gizli.
- Avatar sertleştirme (2026-11-22): Storage yazma/silme politikası yalnızca tam yol `<uid>/avatar.jpg`; tür fotoğraftan çıkınca dosya silinir (bir yineleme, sonra ErrorReporter). İmzalı adres 1 saat geçerli, önbellekte 50 dk; null/hata önbelleğe alınmaz. Arkadaşlarda Google profil resmi gösterilmez. `auth.users` tetikleyicileri DROP edilmez, yalnızca yoksa oluşturulur (schema.sql tamamen yeniden çalıştırılabilir). `ensure_user_settings()` (security definer) eksik ayar satırını açar; `fetch()` ağ hatasında bir kez yineler.
