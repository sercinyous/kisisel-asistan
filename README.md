# Ritim — Kişisel Asistan & Operasyon Merkezi

App Store Connect adı: **Ritim: Rutin, İş ve Sağlık** · iPhone'da görünen ad: **Ritim**

Tek kullanıcılı, iOS Ad-Hoc dağıtımlı Flutter uygulaması.
Flutter · Riverpod · Supabase · Gemini (`gemini-3.8-flash`) · HealthKit ya da Google Health (Fitbit) ·
yerel bildirimler.

## Özellikler

Alt bar beş slotludur; beşi de gerçek ekrandır:

- **Kokpit**: günün rutinleri, yaklaşan görevler, beslenme ve sağlık özeti (HealthKit ya da Google Health);
  ay takvimi ve ay özeti.
- **Operasyon**: görevler (isteğe bağlı hatırlatma), sabitler (günlük/haftalık/aylık rutinler), notlar.
- **+ (AI giriş)**: serbest metni Gemini ile ayrıştırır (görev, öğün, antrenman, kilo, not, rutin),
  önizletir ve tek transaction'da kaydeder.
- **Sağlık**: kilo grafiği (30/90 gün, hedef çizgisi, ölçüm ekleme/silme), haftalık antrenman planı,
  adım / uyku / kalori kartları (dokununca **Trend** ekranı: hafta/ay, hedef tutturma, çubuk grafik),
  **Enerji dengesi** kartı (alınan, yakılan, net ve günlük yorum), bugünün öğünleri (paketli listeden
  **besin arama** ve gram/porsiyon hesabı) ve antrenman günlüğü (ekle/düzenle/sil), sağlık verisi
  kaynağının durumu. Ayrıntılar: "Trendler ve enerji dengesi".
- **Raporlar**: sunucuda otomatik üretilen **haftalık** ve **günlük** raporlar; iş/form yüzdeleri,
  günlük tamamlama grafiği, ortalamalar, AI değerlendirmesi, geçmiş listesi ve "Raporu yeniden oluştur".
- **Ayarlar** (Kokpit'ten): hedefler, profil (boy, doğum yılı, cinsiyet; Enerji dengesi bunları kullanır),
  bildirim tercihleri, sessiz saatler, ekip, bağlantılar (sağlık verisi kaynağı: Apple Health |
  Google Health, Google hesabı).
  Ekranı açmak bildirim izni istemez; izin yalnızca "İzin iste" ile ya da bildirimler eşitlenirken sorulur.
- **İlk kurulum ve kılavuz**: yeni hesap ilk girişte 5 kartlık tanıtımı ve kısa soruları görür (görünen ad, boy,
  doğum yılı, cinsiyet, kilo, hedef kilo, amaç, isteğe bağlı iş tanımı). Önerilen günlük hedefler (kalori = bazal × 1,4
  −500 / 0 / +300, protein 1,8 g/kg, 8000 adım, 7,5 saat uyku) düzenlenebilir; ardından bildirim izni, sessiz saatler,
  başlangıç rutinleri ve sağlık kaynağı seçilir. Mevcut hesaplar zorlanmaz; Ayarlar > "Kılavuzu yeniden göster"
  tanıtımı yeniden açar. Ayarlar'da "Arkadaşlar" satırı da vardır.
- **Şablonlar**: görev, sabit, öğün ve antrenman ekleme formlarının başındaki "Şablondan başla" çipleri formu doldurur
  (her alan düzenlenir). Öğün şablonlarının değerleri yaklaşıktır.

**Düzenle / sil her yerde**: görev, rutin, not, öğün ve antrenman satırlarında (Kokpit gün ve ay
görünümü dahil) uzun basış menüsü (Düzenle / Sil) ve sola kaydırarak silme; silmeden önce onay sorulur,
"Vazgeç" satırı geri getirir. Operasyon listelerindeki üç nokta menüsü de durur. Rutin silinince
tamamlama geçmişi de gider.

**Görünüm**: koyu (saf OLED siyah, varsayılan) ve açık (beyaz) tema. Ayarlar > Görünüm'den Sistem / Açık /
Koyu seçilir; seçim hemen uygulanır, cihazda saklanır (Supabase'e yazılmaz) ve "Sistem" iPhone'un açık/koyu
ayarını uygulama açıkken de izler. İki temanın ekran görüntüleri: `test/screenshots/out/` (01–15 koyu,
16–30 açık).

## Klasör mimarisi (feature-first)

```
kisisel_asistan/
├── pubspec.yaml
├── analysis_options.yaml
├── codemagic.yaml                      # iOS Ad-Hoc .ipa derlemesi
├── dart_defines.example.json           # yerel derleme anahtar şablonu
├── supabase/
│   ├── schema.sql                      # tablolar, indeksler, RLS, RPC, rapor fonksiyonları, seed
│   ├── cron.sql                        # otomatik raporların zamanlaması (pg_cron)
│   ├── functions/generate-reports/     # Edge Function: rapor üretimi (Deno)
│   └── tests/                          # şema ve rapor fonksiyonu testleri (yerel PostgreSQL)
├── ios_setup/
│   ├── Info.plist.additions.xml        # Info.plist'e eklenecek anahtarlar
│   └── Runner.entitlements             # HealthKit yetkisi
├── tool/
│   ├── configure_ios.sh                # ios/ klasörünü otomatik yapılandırır (Google girişi dahil)
│   └── test/                           # configure_ios.sh testi (PlistBuddy taklidiyle, macOS gerekmez)
├── assets/data/foods_tr.json           # paketli besin listesi (100 g değerleri; bkz. "Besin listesi")
├── preview/                            # onaylanan ekran taslakları (HTML)
├── test/
│   └── screenshots/                    # örnek veriyle ekran görüntüsü üretimi (out/*.png)
└── lib/
    ├── main.dart                       # başlatma: Supabase, bildirim, tarih
    ├── main_demo.dart                  # tarayıcı demosu (bellekte örnek veri, sunucu yok)
    ├── demo/                           # demo_backend.dart (sahte depolar), demo_data.dart (60 günlük
    │                                   # örnek veri, profil), demo_foods.dart (örnek besin listesi)
    ├── app.dart                        # MaterialApp + yapılandırma hata ekranı
    ├── core/
    │   ├── config/
    │   │   ├── env.dart                # --dart-define anahtarları
    │   │   └── app_targets.dart        # görev/not kategori listeleri
    │   ├── theme/                      # app_theme.dart (koyu + açık palet, AppColors),
    │   │                               # theme_mode.dart (tercih), app_theme_scope.dart (kök)
    │   ├── utils/date_utils.dart
    │   ├── widgets/                    # bento.dart, app_bottom_bar.dart, item_actions.dart
    │   │                               # (uzun basış menüsü + sola kaydırarak silme)
    │   └── services/
    │       ├── supabase_providers.dart # client + oturum akışı
    │       ├── health_service.dart     # HealthKit: adım, uyku, aktif kalori + kaynak sözleşmesi
    │       ├── health_source.dart      # sağlık verisi kaynağı tercihi (Apple | Google)
    │       ├── google_auth.dart        # Google ile giriş (google_sign_in 7)
    │       ├── google_health_api.dart  # Google Health API v4 REST istemcisi
    │       ├── notification_service.dart # saatli hatırlatma + rutin bildirimi
    │       ├── notification_plan.dart  # bekleyen bildirim planı (saf mantık)
    │       └── notification_sync.dart  # bekleyen bildirimleri veritabanıyla eşitler
    └── features/
        ├── auth/presentation/          # auth_gate.dart, sign_in_screen.dart
        ├── shell/presentation/         # home_shell.dart (5 slot: 4 sekme + AI butonu)
        ├── kokpit/
        │   ├── domain/kokpit_models.dart
        │   ├── data/kokpit_repository.dart
        │   └── presentation/           # kokpit_providers.dart, kokpit_screen.dart
        ├── ai_quick_add/
        │   ├── domain/parsed_entry.dart
        │   ├── data/                   # gemini_parser_service.dart, quick_add_repository.dart
        │   └── presentation/           # ai_quick_add_controller.dart, ai_quick_add_modal.dart
        ├── routines/                   # tekrarlayan işler (günlük/haftalık/aylık)
        │   ├── domain/routine.dart     # model + saf tekrar/dönem mantığı
        │   ├── data/routines_repository.dart
        │   └── presentation/routines_providers.dart
        ├── settings/                   # hedefler, bildirim tercihleri, ekip
        │   ├── domain/user_settings.dart
        │   ├── data/settings_repository.dart
        │   └── presentation/           # settings_providers.dart, settings_screen.dart
        ├── operations/
        │   ├── domain/                 # task_item.dart, note_item.dart
        │   ├── data/                   # tasks_repository.dart, notes_repository.dart
        │   └── presentation/           # operations_screen.dart
        ├── health/                     # Sağlık sekmesi
        │   ├── domain/health_models.dart   # ölçüm, kilo, öğün (NutritionLog), antrenman (WorkoutLog)
        │   ├── domain/goal_rules.dart      # hedef tutturma eşikleri (tek yer)
        │   ├── domain/trend_stats.dart     # hafta/ay özeti: tutan gün, yüzde, ortalama, seri (saf Dart)
        │   ├── domain/energy_balance.dart  # bazal, net, yorum bantları, telafi (saf Dart)
        │   ├── domain/food_item.dart       # besin satırı, porsiyon, gram hesabı
        │   ├── data/health_repository.dart
        │   ├── data/food_catalog.dart      # paketli listeyi okur, Türkçe duyarsız arama
        │   ├── data/google_health_source.dart  # Google Health kaynağı (okuma + antrenman aktarımı)
        │   └── presentation/           # health_providers.dart, health_source_providers.dart,
        │                               # health_screen.dart, weight_card.dart,
        │                               # activity_cards.dart, meals_section.dart, workouts_section.dart,
        │                               # trend_providers.dart, trend_screen.dart, trend_chart.dart,
        │                               # energy_providers.dart, energy_card.dart, energy_detail_screen.dart,
        │                               # *_form_sheet.dart, healthkit_card.dart
        └── reports/                    # Raporlar sekmesi (günlük ve haftalık)
            ├── domain/report_models.dart
            ├── data/reports_repository.dart
            └── presentation/           # reports_providers.dart, reports_state.dart, reports_screen.dart,
                                        # reports_weekly_view.dart, reports_daily_view.dart, reports_chart.dart
```

Faz 2'de her özellik aynı kalıbı izler: `domain/` (modeller) → `data/` (repository) → `presentation/` (provider + ekran).

## Trendler ve enerji dengesi

Sağlık sekmesindeki **Adım**, **Uyku** ve **Kalori** kartları ile Kilo kartının altındaki **Enerji dengesi**
kartı bu iki özelliğe açılır. Hepsi cihazda, mevcut tablolardan (`daily_health_metrics`, `nutrition_logs`,
`fitness_logs`) hesaplanır; yeni sunucu tablosu ya da rapor yoktur. **Sayılar tahminidir ve tıbbi tavsiye
değildir**; yağ yakımının ölçümü değildir.

### Trend: hedef tutturma

Trend ekranı Hafta (Pazartesi–Pazar) ve Ay (takvim ayı) arasında geçer, önceki/sonraki dönem oklarıyla
gezilir; gelecek günler çubukta boştur ve hesaba girmez. Eşikler tek yerdedir
(`lib/features/health/domain/goal_rules.dart`, `GoalRules`):

| Metrik | Gün "tuttu" sayılır | Veri |
| --- | --- | --- |
| Adım | adım ≥ günlük adım hedefinin %100'ü | `daily_health_metrics.steps` |
| Uyku | uyku ≥ uyku hedefinin %90'ı (bileklik ve saatler uykuyu eksik ölçer) | `daily_health_metrics.sleep_minutes` |
| Kalori | hedefin %85–%110'u (uçlar dahil) | o günün öğün toplamı |
| Protein (Kalori sekmesinde ikincil satır) | protein ≥ hedefin %90'ı | o günün öğün toplamı |

- Kalori ve protein kuralı Raporlar sekmesiyle aynıdır. **Adım ve uyku için Raporlar'da tutturma kuralı
  yoktur**; bu iki kural Trend'e özgüdür.
- **Verisi olmayan gün paydaya girmez** ve "veri yok" diye ayrı gösterilir (adım/uyku değeri 0 ya da o gün öğün
  kaydı yok). Kimseyi veri girmediği için "hedefi tutturamadı" saymaz. Bu yüzden Raporlar'daki oranlarla bire bir
  aynı olmaz: Raporlar'ın `form.rate` paydası, verisiz günler dahil geçen gün sayısını içerir; Trend'in
  yüzdesi yalnızca verisi olan günler üzerindendir. Ekran "5/6 gün hedefte" gibi yazar ve verisiz günleri
  "N gün veri yok, hesaba girmedi" notuyla belirtir.
- **Bugün "devam ediyor"**: hedefi zaten tutturduysa tutan gün sayılır; tutturmadıysa paydaya ve ortalamaya
  girmez. Verisiz ve devam eden gün seriyi bozmaz; veri olup hedefi tutturmayan gün bozar. "Mevcut seri"
  yalnızca geçerli dönemde gösterilir; geçmiş dönemde dönem içindeki "en uzun seri" görünür.
- Hiç veri yoksa ekran "Bu dönemde veri yok" der (yüzde ve ortalama gösterilmez).

### Besin listesi

Öğün formunda "Besin ara" paketli `assets/data/foods_tr.json` listesinde arar (Türkçe karakter, büyük/küçük
harf ve takma ad duyarsız: "SUT" → Süt, "İnek" → süt). Seçilen besin için gram (varsayılan 100; virgül kabul
edilir) ya da porsiyon çipi girilir; kcal ve makrolar forma dolar ve elle değiştirilebilir. `quantity_text`
"2 adet · 100 g" biçimindedir, kayıt `source = 'manual'` kalır. Elle giriş her zaman çalışır; gram boş, 0 ya da
negatifse hesap uygulanmaz.

Liste satırı alanları: `id`, `name`, `aliases`, `category`, `kcal100`, `protein100`, `carbs100`, `fat100`,
`portions`, `source` (`USDA FDC <kimlik> | TürKomp <kod>`), `verification` (`iki kaynak` | `tek kaynak`).
Her satır USDA FoodData Central ve Türkiye Gıda Kompozisyon Veri Tabanı (TürKomp) ile çapraz doğrulanır;
doğrulanamayan satır eklenmez. `test/foods_data_test.dart` biçimi, kaynak izini ve Atwater tutarlılığını
(`kcal ≈ 4·protein + 4·karbonhidrat + 9·yağ`, tolerans max(%15, 10 kcal)) denetler.
**Durum: liste dolu** (198 satır, USDA SR Legacy 2018-04, hepsi `tek kaynak`). TürKomp bu ortamdan erişilemedi; TürKomp çapraz doğrulaması yapılmadı. Tarayıcı demosu yalnızca liste boşsa `lib/demo/demo_foods.dart` örneğine düşer.

### Enerji dengesi

Profil gerekir: **Ayarlar > Profil**'de boy (100–250 cm), doğum yılı ve cinsiyet (Kadın / Erkek /
Belirtmek istemiyorum). Eksikse kart "Dengeyi hesaplamak için boy, yaş ve cinsiyet gerekli" der ve Ayarlar'a
götürür.

- **Bazal** (Mifflin-St Jeor): `10·kg + 6,25·cm − 5·yaş + k`; erkek +5, kadın −161, belirtmeyen −78. Kilo,
  o güne kadarki son tartıdır; yoksa Ayarlar'daki başlangıç kilosu. Bugün için bazal, günün geçen oranıyla
  ölçeklenir ve kartta "Şu ana kadar" yazar (saat eşiği yoktur; gece yarısını geçince bugün/dün yeniden
  hesaplanır).
- **Yakılan** = bazal + aktif kalori (Apple Health ya da Google Health). Antrenman kalorisi aktif kalorinin
  içindedir; o gün sağlık satırı yoksa ya da aktif kalori 0 ise antrenman kayıtlarının kalorisi yedek olur
  (çift sayım yok) ve kart "aktif kalori verisi yok, tahmin bazala dayanıyor" der.
- **Alınan** = o günün öğün toplamı. **O gün hiç öğün yoksa yorum üretilmez**: "Henüz öğün girilmedi", grafikte
  boşluk, toplamlara girmez.
- **Net** = alınan − yakılan. Yorum bantları (`EnergyBands`, `lib/features/health/domain/energy_balance.dart`):

  | Net (kcal) | Yorum |
  | --- | --- |
  | ≤ −1000 | "Çok yüksek kalori açığı: yeterince yediğinden emin ol" (övgü yok) |
  | −1000 … −150 | "Bugün yağ yaktın" |
  | −150 … +150 | "Bugün yerinde saydın, yağ almadın" |
  | +150 … +500 | "Bugün biraz kaçırdın, telafi edebilirsin" + telafi: yaklaşık yürüyüş dakikası (3,5 MET, kiloya göre) ya da yarın o kadar az |
  | ≥ +500 | "Bugün fazla geçti; bir günle bozulmaz, yarın toparla" |

  Bant uçları: −1000 çok yüksek açık, −150 "yağ yaktın", +150 "biraz kaçırdın", +500 "fazla geçti".
- **18 yaşından küçük** kullanıcıya yorum ve açık hedefi gösterilmez, yalnızca sayılar.
- **Hafta/ay özeti**: yalnızca yorum üretilebilen (öğünü olan) günlerin net toplamı, "N gün üzerinden"; 7 güne
  ölçeklenmez. **Tahmini yağ değişimi** = Σnet ÷ 7700 kcal/kg, aynı N gün içindir.
- Sınırlar: bazal formül bir tahmindir; aktif kalori cihaza ve kaynağa göre değişir ve uygulama kapalıyken veri
  gelmez; makro ve kalori girişleri kullanıcı/Gemini tahminidir. Bu yüzden sayıları gerçek cihazda Fitbit /
  Sağlık uygulamasıyla karşılaştır.

## Kurulum

`ios/` klasörü depoda tutulmaz ve **yalnızca Codemagic ile derleyeceksen Mac gerekmez**: derleme
`ios/` yoksa onu kendisi oluşturur ve yapılandırır (bkz. "TestFlight ile test"); 1. ve 2. adımı atla.
Mac'te yerel çalıştırmak ya da Xcode'da elle değişiklik yapmak istersen:

1. **iOS projesini oluştur** (Mac'te, bu klasörde). `com.ornek` yerine Bundle ID'nin son parçası
   hariç kısmını yaz (`com.ornek.kisiselAsistan` → `com.ornek`):
   ```bash
   flutter create --no-pub --platforms=ios --org com.ornek --project-name kisisel_asistan .
   ```
   `flutter create` kilit dosyasını yeniden yazar; depodaki sürümlere dön:
   ```bash
   git checkout -- pubspec.lock
   ```
2. **iOS'u yapılandır** (HealthKit, Info.plist, iOS 15, bildirim delegesi; `GOOGLE_IOS_CLIENT_ID` verilirse Google girişi):
   ```bash
   flutter pub get
   ```
   ```bash
   bash tool/configure_ios.sh
   ```
   `ios/` klasörünü depoya koymak isteğe bağlıdır. Xcode'da elle değişiklik (ek yetki, uzantı,
   uygulama simgesi) yaptıysan koy: Codemagic depodaki klasörü kullanır, yeniden oluşturmaz.
3. **Supabase**: yeni proje aç → SQL Editor'da `supabase/schema.sql` dosyasını çalıştır →
   kendi hesabını Google ile ya da e-posta + şifreyle aç (kayıt herkese açıktır).
   Başlangıç satırı kullanıcı oluştuğu anda açılır. Authentication > Sign In / Providers altında
   "Allow new users to sign up" seçeneği **açık** olmalı (Google ile ilk giriş ve e-postayla "Kayıt ol"
   yeni kullanıcı oluşturur). Ayrıntı: "Google ile giriş".
4. **Anahtarlar**: `dart_defines.example.json` dosyasını `dart_defines.json` olarak kopyala ve doldur.
5. **Çalıştır** (HealthKit gerçek cihaz ister):
   ```bash
   flutter run --dart-define-from-file=dart_defines.json
   ```

## Faz 4B kurulumu (çok kullanıcılı)

Sıra önemli: **önce yeni yapı TestFlight'a düşer, sonra SQL çalıştırılır** (eski yapı 'Pusholder' yazar; tetikleyici 'İş'e çevirir).

1. **Supabase > Authentication > Sign In / Providers**: "Allow new users to sign up" **AÇIK** (kayıt herkese açık; davet kapısı kaldırıldı). "Confirm email" açık olsun: e-postayla kayıt olan onay e-postası alır; kapalıysa bir adrese gönderilmiş arkadaşlık isteğini o adresle doğrulamadan kayıt olan da görür.
2. **Google sağlayıcısı**: Google Cloud'da Web OAuth istemcisi aç, Supabase > Providers > Google'a Web + iOS kimliklerini yaz ("Skip nonce checks" açık). Ayrıntı: "Google ile giriş". Testing modunda arkadaşların Gmail'lerini **Audience > Test users**'a ekle.
3. **SQL**: `supabase/schema.sql` dosyasını çalıştır, sonra `supabase/cron.sql`. Dashboard'dan elle hesap açmak için doğrudan Add user (Auto Confirm) yeterli. Eski kurulumda Before User Created kancası seçildiyse artık her kaydı geçirir; istersen Hooks'tan kaldırabilirsin.
4. **Fonksiyonlar ve secret'lar**:
   ```bash
   supabase secrets set GEMINI_API_KEY=... GEMINI_MODEL=gemini-3.8-flash AI_DAILY_LIMIT=100 CRON_SECRET=...
   supabase functions deploy ai-proxy --no-verify-jwt
   supabase functions deploy generate-reports --no-verify-jwt
   ```
   İsteğe bağlı: `REPORT_REGEN_DAILY_LIMIT` (varsayılan 10). Uygulama `GEMINI_API_KEY` dart-define'ı boşsa `ai-proxy` kullanır.
5. **Codemagic `app_secrets`**: `GOOGLE_WEB_CLIENT_ID` (ve mevcut `GOOGLE_IOS_CLIENT_ID`). `GEMINI_API_KEY` artık gerekmez.
6. **TestFlight daveti**: arkadaşları App Store Connect > Kullanıcılar ve Erişim'den ekle (dahili) ya da harici test grubuna e-postayla davet et.
7. **Arkadaş ekleme**: uygulamada Kokpit > kişi ikonu > e-posta ile istek. İstek henüz kaydolmamış bir e-postaya da gönderilebilir; kişi kaydolunca gelen kutusunda görür.

**Sahibin kontrol listesi**: [ ] Sign up açık, Confirm email açık [ ] Google sağlayıcısı + Web istemcisi [ ] Test kullanıcıları eklendi [ ] Yeni yapı TestFlight'ta [ ] schema.sql + cron.sql çalıştı [ ] secret'lar + iki fonksiyon dağıtıldı [ ] Codemagic `GOOGLE_WEB_CLIENT_ID` [ ] TestFlight davetleri [ ] iki hesapla giriş ve arkadaşlık denemesi [ ] `flutter analyze` / `flutter test` temiz.

## Otomatik raporlar

Günlük ve haftalık raporlar sunucuda, uygulama kapalıyken de üretilir:

```
pg_cron ──HTTP──▶ Edge Function generate-reports ──▶ Gemini
  her gün 00:15 İstanbul          → biten günün günlük raporu (daily_reports)
  her saat :20                    → geç veriyle kirlenen raporları yeniler
  her Pazartesi 07:00 İstanbul    → biten haftanın raporu   (weekly_reports)
Uygulama "Raporu yeniden oluştur" ──▶ aynı fonksiyon (kullanıcı oturumuyla)
```

Sayılar veritabanında hesaplanır (`report_daily_metrics`, `report_weekly_metrics`); Gemini yalnızca yorum
metnini yazar. Gemini yanıt vermezse rapor sayılarla kaydedilir (`ai_status = 'failed'`), uygulama sayıları
yine gösterir. Kurulum bir kez yapılır:

1. **Şemayı güncelle**: SQL Editor'da `supabase/schema.sql` dosyasını (yeniden) çalıştır. Var olan veriyi
   silmez; rapor tablolarını ve fonksiyonlarını ekler.
2. **Supabase CLI'yi projeye bağla** (bilgisayarında, bu klasörde; `PROJE-REF` proje ayarlarındaki
   "Reference ID"):
   ```bash
   supabase login
   ```
   ```bash
   supabase link --project-ref PROJE-REF
   ```
3. **Gizli anahtarları ver.** `CRON_SECRET` için uzun, rastgele bir değer üret (örn. `openssl rand -hex 32`)
   ve bir yere not et; 5. adımda aynısı gerekecek. `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY`
   fonksiyona Supabase tarafından kendiliğinden verilir, elle eklenmez.
   ```bash
   supabase secrets set GEMINI_API_KEY=AI-STUDIO-ANAHTARIN CRON_SECRET=URETTIGIN-DEGER
   ```
   İsteğe bağlı: `GEMINI_MODEL` (varsayılan `gemini-3.8-flash`).
4. **Fonksiyonu dağıt.** Kimliği fonksiyonun kendisi doğrular (zamanlayıcı gizli anahtarı ya da kullanıcı
   oturumu), bu yüzden geçidin JWT denetimi kapatılır:
   ```bash
   supabase functions deploy generate-reports --no-verify-jwt
   ```
5. **Vault değerlerini koy** (SQL Editor; kendi değerlerinle, bir kez):
   ```sql
   select vault.create_secret('https://PROJE-REF.supabase.co', 'project_url');
   select vault.create_secret('URETTIGIN-DEGER', 'cron_secret');
   ```
6. **Zamanlamayı kur**: SQL Editor'da `supabase/cron.sql` dosyasını çalıştır. Sonunda iki iş listelenir
   (`kisisel-asistan-gunluk-rapor`, `kisisel-asistan-haftalik-rapor`). Dosya yeniden çalıştırılabilir.
7. **Bir kez elle dene** (tüm kullanıcılar için bugünün günlük raporu):
   ```bash
   curl -X POST "https://PROJE-REF.supabase.co/functions/v1/generate-reports" \
     -H "Content-Type: application/json" \
     -H "x-cron-secret: URETTIGIN-DEGER" \
     -d '{"kind":"daily"}'
   ```
   Beklenen yanıt: `{"ok":true,"kind":"daily","date":"2026-11-16","users":1,"failed":0,"ai_failed":0}`.
   `ai_failed` 1 ise rapor yazılmış ama Gemini yorumu üretilememiştir (anahtarı ve kotayı kontrol et).
   Haftalık için gövde `{"kind":"weekly"}`; belirli bir gün/hafta için `"date":"2026-11-09"` eklenir
   (gelecek tarih reddedilir). Sonuç: `select * from daily_reports order by report_date desc limit 1;`

Notlar:
- Rapor günü ve haftası `user_settings.timezone` (varsayılan `Europe/Istanbul`) saat dilimine göre kesilir.
  `cron.sql` içindeki saatler UTC'dir ve İstanbul'a göre ayarlıdır; başka dilimde yaşıyorsan iki
  zamanlamayı değiştir.
- Uygulama rapor tablolarını yalnızca okur; satırları fonksiyon `service_role` ile yazar. Bu anahtar
  yalnızca sunucudadır, uygulamaya konmaz.
- Adım, uyku ve aktif kalori uygulama açıkken HealthKit'ten eşitlenir (uygulama kapalıyken veri
  gönderilemez). Bu yüzden zamanlayıcının yazdığı rapor, o gün uygulamanın son açıldığı ana kadarki
  değeri (uygulama hiç açılmadıysa boş alanı) taşır. Uygulama her açıldığında ve öne geldiğinde son
  7 günün gün sonu değerleri yeniden okunup tabloya yazılır; ardından "Raporu yeniden oluştur" o günün
  ya da haftanın sayılarını doğru değerlerle günceller.
- Zamanlayıcı çağrılarının sonucu: `select * from net._http_response order by created desc limit 5;`
  İş geçmişi: `select * from cron.job_run_details order by start_time desc limit 5;`
- Doğrulama durumu: `schema.sql` ve rapor fonksiyonları yerel PostgreSQL 16'da sınandı
  (`supabase/tests/run_local.sh`); fonksiyonun mantığı ve istek akışı Node ile sınandı
  (`node --experimental-strip-types --test supabase/functions/generate-reports/*.test.mjs`).
  **Gerçek bir Supabase projesinde denenmedi:** `index.ts` (Deno + supabase-js bağlantısı) yalnızca tür
  denetiminden geçti, çalıştırılmadı; `cron.sql` (pg_cron, pg_net, Vault) ve yukarıdaki `supabase` CLI
  komutları bu ortamda çalıştırılamadı. İlk kurulumda 7. adımdaki elle denemeyi mutlaka yap.

## Google Health ile bağlantı

Fitbit Web API kapatıldı (2026); Fitbit cihazının verisi artık **Google Health API**
(`https://health.googleapis.com/v4/`) üzerinden okunur. Uygulama Google ile giriş yapar ve bu API'den
günlük adım, aktif kalori, gecelik uyku ve antrenmanları çeker. Apple Health (HealthKit) varsayılan kaynak
olarak kalır; **aynı anda yalnızca bir kaynak** okunur (ikisi birden toplansa adım ve uyku çift sayılırdı).

### 1. Google Cloud Console (bir kez)

1. [console.cloud.google.com](https://console.cloud.google.com) > proje seçici > **New project**
   (ör. `ritim-health`) ve projeyi seç.
2. **APIs & Services > Library** > "Google Health API" > **Enable**.
3. **Google Auth Platform** (eski adıyla OAuth consent screen) > **Get started**:
   uygulama adı `Ritim`, destek e-postası; **Audience: External**; iletişim e-postası; kaydet.
4. **Audience** > yayın durumu **Testing** kalsın > **Test users > Add users**: Fitbit verisinin bağlı olduğu
   kendi Google hesabın.
5. **Data Access > Add or remove scopes**: aşağıdaki iki salt okuma kapsamını ekle (listede bulamazsan
   "Manually add scopes" kutusuna yapıştır) ve kaydet. Başka kapsam gerekmez:
   ```
   https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
   https://www.googleapis.com/auth/googlehealth.sleep.readonly
   ```
   (adım, aktif kalori ve antrenmanlar "activity and fitness", uyku "sleep" kapsamındadır)
6. **Clients > Create client**: Application type **iOS**, Bundle ID **`com.sercinyous.kisiselasistan`**
   (App Store ID ve Team ID isteğe bağlı) > **Create**. Gösterilen **Client ID**'yi
   (`…apps.googleusercontent.com` ile biten) kopyala. iOS istemcisinin gizli anahtarı yoktur.

### 2. Codemagic

Environment variables > **`app_secrets`** grubuna `GOOGLE_IOS_CLIENT_ID` = kopyaladığın Client ID.
Bu değer gizli değildir (uygulamanın içinde durur); Secure işaretlemek zorunlu değil. Sonraki derlemede:
- `tool/configure_ios.sh` Info.plist'e `GIDClientID` ve ters çevrilmiş kimlikle URL şemasını
  (`com.googleusercontent.apps.…`, Google girişinin uygulamaya dönüş adresi) yazar,
- iki derleme adımı değeri `--dart-define=GOOGLE_IOS_CLIENT_ID` ile uygulamaya verir.

Değişken yoksa derleme yine başarılı olur; uygulamada Google seçeneği kapalı ve açıklamalı görünür.
Biçimi bozuk bir değer derlemeyi bilerek durdurur. Yerelde (Mac) aynı anahtarı `dart_defines.json`'a yaz
ve `GOOGLE_IOS_CLIENT_ID=… bash tool/configure_ios.sh` çalıştır. Betiğin Info.plist düzenlemeleri
macOS olmadan da sınanabilir: `bash tool/test/configure_ios_test.sh` (gerçek bir `flutter create` iOS
projesinde, PlistBuddy taklidiyle).

**Şema**: Google antrenmanlarını kopyasız yazmak için `supabase/schema.sql` yeniden çalıştırılmalı
(`fitness_logs.external_id`, `source = 'google'`, tekil dizin). Çalıştırılmazsa günlük değerler yine
yazılır, yalnızca antrenman aktarımı başarısız olur.

### 3. Uygulamada

1. **Ayarlar > Bağlantılar > Google Health (Fitbit) > Google ile bağlan**. Google hesabını seç;
   "Google bu uygulamayı doğrulamadı" uyarısı Testing modunda beklenir (**Devam**). İzin ekranında
   iki kutuyu da işaretle; biri eksikse uygulama "izin eksik" der ve yeniden bağlanmanı ister.
2. Aynı karttaki **Sağlık verisi kaynağı** seçiminden **Google Health**'e geç. Seçim cihazda saklanır,
   hemen bugün ve son 7 gün yeni kaynaktan okunup `daily_health_metrics`'e yazılır (eski kaynağın aynı
   günlerdeki değerlerinin üstüne; toplanmaz). Daha eski günler önceki kaynağın değerinde kalır.
3. Kokpit ve Sağlık kartları etkin kaynağı gösterir: "Google Health · 14:05" ya da "HealthKit · 14:05".
   Ayarlar'daki Google satırı hesabı ve son eşitlemeyi gösterir; **Şimdi eşitle** ve **Bağlantıyı kes**
   (onaylı) buradadır. Apple Health'e dönmek için kaynağı yeniden **Apple Health** yap.

Okunanlar (uygulama açılışında, öne gelişte ve elle yenilemede; HealthKit yoluyla aynı kurallar):
- **Adım** ve **aktif kalori**: yerel takvim günü başına toplam (`dailyRollUp`).
- **Uyku**: önceki gün 18:00 → o gün 18:00 penceresindeki uyku evreleri (hafif, derin, REM, uykuda;
  uyanık ve huzursuz hariç); çakışan oturumlar bir kez sayılır, pencereyi aşan kısım kırpılır.
- **Antrenmanlar**: son 7 gün ve bugün, antrenman günlüğüne "Google" işaretiyle eklenir. Aynı antrenman
  yeniden eşitlemede kopyalanmaz; düzenlediğin kayıt ezilmez, sildiğin kayıt geri gelmez.
  Kendi kaydınla çift sayılmaz: elle ya da AI ile yazdığın bir antrenmanla aynı oturum olan (zamanı çakışan,
  ya da türü uyumlu ve en çok 60 dk arayla) Google kaydı aktarılmaz; Google'dan önce aktarılmış bir kayıt
  sonradan aynı oturumu yazarsan silinir (senin kaydın kalır). Ev işi, bahçe, meditasyon, düz yürüyüş ve
  10 dakikadan kısa kayıtlar antrenman sayılmaz, aktarılmaz.

### Haftalık yeniden bağlanma (Testing modu sınırı)

Yayın durumu **Testing** olan ve harici kullanıcıya açık projelerde Google, yenileme anahtarını
(refresh token) **7 gün** geçerli verir. Süre dolunca uygulama sessizce yenileyemez ve kartlarda
**"Google oturumunun süresi doldu. Google'a yeniden bağlan."** yazar; dokununca tek adımda yeniden
bağlanırsın, veri kaybolmaz ve uygulamanın geri kalanı çalışmaya devam eder. Sınırı kaldırmanın yolu
projeyi "In production" durumuna almaktır (yeni verilen anahtarlar için; mevcut olanlar yenilenmeden
bağlanılması gerekir). Google, Health API kapsamlarının tümünü kısıtlı (restricted) sayar ve 100'den fazla
kullanıcı için güvenlik incelemesi (OAuth doğrulaması) ister; doğrulanmamış bir uygulamanın tek kişilik
kullanımda nasıl davrandığı burada **denenmedi**. Bu yüzden tek kişilik kullanımda haftada bir yeniden
bağlanmak güvenli ve pratik yoldur.

**Sorun giderme**: "bu derlemede yapılandırılmamış" → `GOOGLE_IOS_CLIENT_ID` eksik ya da hatalı;
"Google Health API … etkin değil" → 1.2. adım; "izin eksik" → yeniden bağlan ve iki kutuyu işaretle;
"Biraz sonra tekrar dene" → Google'ın geçici yoğunluğu (429/5xx). İzni Google tarafından da kaldırabilirsin:
myaccount.google.com > Güvenlik > Üçüncü taraf erişimi.

**Doğrulama durumu**: REST istemcisi, API'nin resmi keşif belgesindeki (revizyon 20261114) uç noktalar,
alanlar ve kapsamlarla yazıldı ve sahte HTTP ile sınandı. Gerçek bir Google hesabı ve iPhone ile bu
ortamda denenmedi; ilk bağlantıda Ayarlar'daki son eşitleme saatini ve Kokpit değerlerini Fitbit
uygulamasıyla karşılaştır.

## Google ile giriş

Giriş ekranında **Google ile devam et** ana yoldur, **E-posta ile giriş** ikincildir. Akış: `google_sign_in`
(yalnızca e-posta ve profil) → kimlik belirteci → `supabase.auth.signInWithIdToken(provider: google)`.
Google Health bağlantısıyla aynı `GoogleSignIn.instance.initialize` çağrısını paylaşır (`clientId` iOS,
`serverClientId` Web); çıkış yapmak Google Health bağlantısına dokunmaz. Google Health yalnızca Ayarlar'dan
bağlanınca bağlı sayılır.

1. **Google Cloud Console > Clients > Create client**: Application type **Web application** > Client ID'yi kopyala
   (iOS istemcisi "Google Health ile bağlantı" adımında zaten var). Testing modunda arkadaşların Gmail adreslerini
   **Audience > Test users**'a ekle.
2. **Supabase > Authentication > Providers > Google**: aç; **Client IDs** alanına Web ve iOS istemci
   kimliklerini virgülle yaz; "Skip nonce checks" kutusunu işaretle (yerel iOS girişi nonce göndermez).
3. **Codemagic > `app_secrets`**: `GOOGLE_WEB_CLIENT_ID` = Web istemci kimliği (gizli değil). Boşsa ya da
   `GOOGLE_IOS_CLIENT_ID` yoksa Google düğmesi gizlenir; tarayıcı demosunda da gizlidir. Yerelde aynı anahtarı
   `dart_defines.json`'a yaz.

**Hesap birleşmesi**: Supabase aynı doğrulanmış e-postayı aynı kullanıcıya bağlar. Hesabın Gmail adresiyle
açıldıysa Google girişi aynı veriyi açar; başka bir e-postayla açıldıysa Google **yeni boş hesap** açar
ve eski hesabına e-posta/şifreyle girmeye devam edersin.

**Açık kayıt**: herkes Google ile ya da e-posta formundaki "Hesabın yok mu? Kayıt ol" ile hesap açabilir.
E-posta kaydında "Confirm email" açıksa uygulama "Onay e-postası gönderildi, gelen kutunu (ve spam) kontrol et."
der. Eski davet kapısı kaldırıldı: `signup_invite_gate` tetikleyicisi Supabase'de silinemediği için yerinde
durur ama her kaydı geçirir.

**Doğrulama durumu**: giriş mantığı sahte Google ve Supabase ile sınandı; gerçek Google girişi gerçek projede
iki hesapla denenmeden bitmiş sayılmaz.

## Tarayıcı demosu ve ekran görüntüleri

Sunucu olmadan, örnek veriyle (bugünün öğünleri, antrenmanlar, 90 günlük kilo serisi, 60 günlük adım /
uyku / kalori geçmişi, dolu profil, 3 haftalık ve 7 günlük rapor) çalışan demo. Trend ekranı, Enerji dengesi
ve besin arama bu veriyle çalışır; son üç haftadan eski günlerin bazısında sağlık verisi ya da öğün yoktur
(boş günler görünsün diye). Google Health seçeneği sahte bir hesapla çalışır (giriş penceresi açılmaz,
Google'a veri isteği gitmez; yalnızca `google_sign_in_web` eklentisi sayfa açılırken Google'ın giriş betiğini
yükler, kullanılmaz). Depoda `web/` klasörü tutulmaz; deneme için ayrı bir kopyada üretilir:

```bash
flutter create --platforms=web --project-name kisisel_asistan .
```
```bash
flutter build web -t lib/main_demo.dart --release --no-web-resources-cdn --no-wasm-dry-run
```

Ekran görüntüleri aynı örnek veriyle üretilir (`test/screenshots/out/*.png`). Görüntüler günün tarihine
bağlı olduğu için bu test olağan `flutter test` çalışmasında atlanır, yalnızca şu komutla çalışır:

```bash
flutter test --update-goldens test/screenshots/app_screens_test.dart
```

## TestFlight ile test (önerilen)

Uygulama App Store Connect'e yüklenir, iPhone'a **TestFlight** uygulamasından kurulur. Dahili test
(kendi hesabın) Apple incelemesi beklemez, cihaz UDID'si gerekmez; her `main` push'unda yeni yapı gelir.

**Ön koşul:** ücretli Apple Developer Program üyeliği.

1. **App ID** — developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > **+** >
   App IDs > App. Bundle ID'yi açıkça yaz (ör. `com.adsoyad.kisiselasistan`) ve **HealthKit**
   yetkisini işaretle. Bu kimlik sonradan değiştirilemez.
2. **Uygulama kaydı** — appstoreconnect.apple.com > Uygulamalar > **+** > Yeni Uygulama:
   platform iOS, ad (mağazada benzersiz olmalı; bu proje için "Ritim: Rutin, İş ve Sağlık", iPhone'da
   görünen ad "Ritim"), dil Türkçe, Bundle ID'yi listeden seç, SKU serbest (ör. `kisiselasistan-ios`),
   Kullanıcı Erişimi **Tam Erişim** (sınırlı erişimde Codemagic'in API anahtarı uygulamayı göremeyebilir).
   Kaydedince Uygulama Bilgileri sayfasındaki **Apple ID** (sayısal) değerini not et.
3. **Dahili test grubu** — uygulamanın TestFlight sekmesi > Dahili Test > **+**: bir grup aç,
   kendini ekle ve "Yapıları otomatik dağıt" seçeneğini aç.
4. **API anahtarı** — App Store Connect > Kullanıcılar ve Erişim > Entegrasyonlar > App Store Connect API
   > Ekip Anahtarları > **+**: rol **App Manager**. `.p8` dosyasını indir (yalnızca bir kez
   indirilebilir), Issuer ID ve Key ID'yi not et.
5. **Codemagic** (codemagic.io):
   - Depoyu ekle (`sercinyous/kisisel-asistan`), yapılandırma olarak `codemagic.yaml` seçili kalsın.
   - Team settings > Team integrations > **Developer Portal** > Manage keys: 4. adımdaki anahtarı
     ekle, adını `kisisel-asistan-asc` yap (ya da `codemagic.yaml` içindeki
     `integrations.app_store_connect` değerini kendi verdiğin adla değiştir).
   - Team settings > **Code signing identities**: iOS Distribution sertifikası ekle (yoksa
     Codemagic orada oluşturur), sonra "iOS provisioning profiles" bölümünde Bundle ID'n için
     **App Store** profilini çek (Fetch profiles).
   - Environment variables: `app_secrets` grubuna `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
     `GEMINI_API_KEY` ekle (Secure işaretli). İsteğe bağlı `GOOGLE_IOS_CLIENT_ID`: bkz.
     "Google Health ile bağlantı".
6. **`codemagic.yaml`** — en üstteki `definitions.vars` bloğunda iki değeri doldur:
   `BUNDLE_ID` (1. adım) ve `APP_STORE_APPLE_ID` (2. adım). İmzalama ayarları bu değeri okur.
   Örnek değerlerle derleme ilk adımda bilerek durur.
7. **Derle** — `main`'e push et ya da Codemagic'te **iOS TestFlight** iş akışını başlat. Yapı
   numarası App Store Connect'teki son numaranın bir fazlası olur.
8. **Kur** — yükleme bitince Apple yapıyı işler (genellikle 5–30 dk) ve e-posta gönderir. iPhone'da
   TestFlight uygulamasını aç, Ritim'i kur.

**Kurulumdan önce Supabase hazır olmalı** (Kurulum > 3. adım ve "Otomatik raporlar"): uygulama
açılınca giriş ekranı gelir ve Supabase'deki kullanıcınla giriş yapılır.

**Bilmen gerekenler**
- TestFlight yapıları 90 gün geçerlidir; yeni push yeni yapı getirir.
- Şifreleme sorusu (Export Compliance) sorulmaz: Info.plist'te `ITSAppUsesNonExemptEncryption = false`.
- Dış test (başkalarına göndermek) Apple'ın beta incelemesini ister; o zaman `submit_to_testflight: true`
  ve `beta_groups` eklenir, App Store Connect'te gizlilik politikası adresi istenir.
- Simge şu an Flutter'ın varsayılan simgesidir; değiştirmek için `ios/` klasörünü depoya koyup
  `ios/Runner/Assets.xcassets/AppIcon.appiconset` içini güncelle.

### Mac ve Xcode ile (alternatif)

`ios/` oluşturulup yapılandırıldıktan sonra (Kurulum > 1–2) Xcode'da `ios/Runner.xcworkspace`
dosyasını aç ve Signing & Capabilities'te ekibini seç. Arşivi Xcode'un Product > Archive menüsüyle
**değil**, anahtarlar gömülsün diye Flutter ile üret (aksi hâlde uygulama "Yapılandırma eksik"
ekranıyla açılır):
```bash
flutter build ipa --dart-define-from-file=dart_defines.json
```
Ardından `build/ios/archive/Runner.xcarchive` dosyasını açıp Xcode Organizer'da
Distribute App > App Store Connect ile yükle. Yapı numarasını her yüklemede artır
(`pubspec.yaml` içindeki `version: 1.0.0+N`).

## Ad-Hoc dağıtım (Codemagic, alternatif)

UDID'si eklenmiş cihazlara App Store Connect olmadan kurmak için. Codemagic'te **iOS Ad-Hoc**
iş akışı yalnızca elle başlatılır.

1. developer.apple.com: App ID oluştur (HealthKit yetkisi açık), iPhone'unun UDID'ini Devices'a ekle,
   bu App ID + cihaz için **Ad Hoc** provisioning profile üret.
2. Codemagic > Team settings > Code signing identities: dağıtım sertifikasını ve profili ekle.
3. `app_secrets` grubu ve `codemagic.yaml` içindeki `BUNDLE_ID` TestFlight bölümündeki gibi.
4. İş akışını başlat → `.ipa` Artifacts altında; Codemagic'in kurulum bağlantısından iPhone'a yükle.

Depoda `ios/` klasörü yoksa her iki iş akışı da onu `flutter create` ile, Bundle ID'ne göre oluşturur
(`--org` = Bundle ID'nin son parçası hariç kısmı), `tool/configure_ios.sh` ile yapılandırır ve
uygulama ile `RunnerTests` kimliklerini Bundle ID'ne eşitler. Depoda `ios/` varsa o kullanılır;
aynı yapılandırma ve kimlik adımları onun üzerinde çalışır.

## Bilinmesi gerekenler

- **Rapor yorumları için Gemini anahtarı sunucudadır** (Edge Function secret); aşağıdaki not yalnızca
  AI hızlı giriş için geçerlidir.
- **AI çağrıları `ai-proxy` üzerinden gider** (Faz 4B); Gemini anahtarı uygulamada değil, fonksiyon secret'ındadır. Günlük kota kullanıcı başınadır.
- **AI kaydı iki adımlıdır**: Ayrıştır → önizle → Kaydet. Kaydetme tek transaction'dır
  (`quick_add_entries` RPC): bir tablo hata verirse hiçbiri yazılmaz.
- **Makro değerleri tahmindir.** Gemini standart besin değerlerinden hesaplar; önizlemede kontrol et.
- **Spor günleri varsayımdır** (ağırlık Pzt/Sal/Per/Cum, kickboks Çar, koşu Cmt, halı saha Paz).
  `routines.days_of_week` sütunundan değiştir.
- **Hedefler** (kilo, kalori, makro, adım, uyku), bildirim tercihleri ve ekip `user_settings` tablosundadır
  (varsayılan: 2000 kcal, 170 g protein); uygulama `settingsOrDefaultProvider` üzerinden okur.
- **Profil** (`user_settings.height_cm`, `birth_year`, `sex`) Enerji dengesi içindir; boş olabilir
  (`sex`: `female` | `male` | `unspecified`). `schema.sql` bu sütunları `add column if not exists` ile
  ekler; **bu sürümü kurmadan önce şemayı yeniden çalıştır**.
- **Tekrarlayan işler** `routines` tablosundadır: günlük/haftalık (`frequency = 'weekly'`, `days_of_week`) ya da
  aylık (`frequency = 'monthly'`, `day_of_month`; 31 → kısa ayda ayın son günü). Aylık iş, gününden
  `monthly_lead_days` gün önce Gün ekranına düşer, günü geçince gecikmiş görünür, ay bitince kapanır.
  `routine_completions.completed_on` dönem anahtarıdır: günlük/haftalıkta o gün, aylıkta ayın 1'i.
  Anahtarın anlamı sıklığa bağlı olduğu için, bir rutinin sıklığı (günlük/haftalık ↔ aylık)
  değiştirilince o rutinin eski işaretleri silinir (`routines_frequency_changed` tetikleyicisi).
- **Şema yükseltmesi**: `supabase/schema.sql` yeniden çalıştırılabilir; eski sürümle kurulmuş veritabanını
  veriyi silmeden yükseltir (yeni sütunlar, `user_settings`, iki örnek aylık iş, rapor tabloları,
  `tasks.notify`, `fitness_logs.external_id` ve `source = 'google'`). **Bu sürümü kurmadan önce şemayı yeniden çalıştır**: uygulama görev kaydederken
  `notify` sütununu yazar.
- **Görev hatırlatması**: formdaki "Hatırlat" kapalıysa (`tasks.notify = false`) görev termini olsa da
  bildirim almaz. AI ile eklenen görevler bildirimlidir; ayrı bir hatırlatma zamanı söylenmediyse
  bildirim, Ayarlar'daki "randevu kaç dk önce" süresi kadar önce gelir. Yükseltmede, eski formda hatırlatması kapalı
  kaydedilmiş görevler (elle eklenmiş, termini var, hatırlatma saati yok) bir kez kapalıya çevrilir.
- **iOS, HealthKit okuma izninin reddini uygulamaya bildirmez**; reddedilirse değerler 0 görünür.
- **Sağlık verisi tek kaynaktan gelir**: Apple Health (varsayılan) ya da Google Health; seçim cihazda
  saklanır. Google bağlantısı Testing modunda haftada bir yenilenmelidir (bkz. "Google Health ile bağlantı").
- **Ek tablolar**: istenen 6 tabloya ek olarak `routine_completions` (dönem bazlı tamamlanma),
  `daily_health_metrics` (seçili sağlık kaynağının günlük özeti), `user_settings` (kullanıcı başına tek satır) ve
  `daily_reports` (günlük rapor) vardır.
