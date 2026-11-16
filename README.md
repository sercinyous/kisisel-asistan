# Ritim — Kişisel Asistan & Operasyon Merkezi

App Store Connect adı: **Ritim: Rutin, İş ve Sağlık** · iPhone'da görünen ad: **Ritim**

Tek kullanıcılı, iOS Ad-Hoc dağıtımlı Flutter uygulaması.
Flutter · Riverpod · Supabase · Gemini (`gemini-3.8-flash`) · HealthKit · yerel bildirimler.

## Özellikler

Alt bar beş slotludur; beşi de gerçek ekrandır:

- **Kokpit**: günün rutinleri, yaklaşan görevler, beslenme ve HealthKit özeti; ay takvimi ve ay özeti.
- **Operasyon**: görevler (isteğe bağlı hatırlatma), sabitler (günlük/haftalık/aylık rutinler), notlar.
- **+ (AI giriş)**: serbest metni Gemini ile ayrıştırır (görev, öğün, antrenman, kilo, not, rutin),
  önizletir ve tek transaction'da kaydeder.
- **Sağlık**: kilo grafiği (30/90 gün, hedef çizgisi, ölçüm ekleme/silme), haftalık antrenman planı ve
  7 günlük adım, bugünün öğünleri ve antrenman günlüğü (ekle/düzenle/sil), HealthKit durumu.
- **Raporlar**: sunucuda otomatik üretilen **haftalık** ve **günlük** raporlar; iş/form yüzdeleri,
  günlük tamamlama grafiği, ortalamalar, AI değerlendirmesi, geçmiş listesi ve "Raporu yeniden oluştur".
- **Ayarlar** (Kokpit'ten): hedefler, bildirim tercihleri, sessiz saatler, ekip, bağlantı durumu.
  Ekranı açmak bildirim izni istemez; izin yalnızca "İzin iste" ile ya da bildirimler eşitlenirken sorulur.

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
│   └── configure_ios.sh                # ios/ klasörünü otomatik yapılandırır
├── preview/                            # onaylanan ekran taslakları (HTML)
├── test/
│   └── screenshots/                    # örnek veriyle ekran görüntüsü üretimi (out/*.png)
└── lib/
    ├── main.dart                       # başlatma: Supabase, bildirim, tarih
    ├── main_demo.dart                  # tarayıcı demosu (bellekte örnek veri, sunucu yok)
    ├── demo/                           # demo_backend.dart (sahte depolar), demo_data.dart
    ├── app.dart                        # MaterialApp + yapılandırma hata ekranı
    ├── core/
    │   ├── config/
    │   │   ├── env.dart                # --dart-define anahtarları
    │   │   └── app_targets.dart        # görev/not kategori listeleri
    │   ├── theme/                      # app_theme.dart (koyu + açık palet, AppColors),
    │   │                               # theme_mode.dart (tercih), app_theme_scope.dart (kök)
    │   ├── utils/date_utils.dart
    │   ├── widgets/                    # bento.dart, app_bottom_bar.dart
    │   └── services/
    │       ├── supabase_providers.dart # client + oturum akışı
    │       ├── health_service.dart     # HealthKit: adım, uyku, aktif kalori
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
        │   ├── data/health_repository.dart
        │   └── presentation/           # health_providers.dart, health_screen.dart, weight_card.dart,
        │                               # activity_cards.dart, meals_section.dart, workouts_section.dart,
        │                               # *_form_sheet.dart, healthkit_card.dart
        └── reports/                    # Raporlar sekmesi (günlük ve haftalık)
            ├── domain/report_models.dart
            ├── data/reports_repository.dart
            └── presentation/           # reports_providers.dart, reports_state.dart, reports_screen.dart,
                                        # reports_weekly_view.dart, reports_daily_view.dart, reports_chart.dart
```

Faz 2'de her özellik aynı kalıbı izler: `domain/` (modeller) → `data/` (repository) → `presentation/` (provider + ekran).

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
2. **iOS'u yapılandır** (HealthKit, Info.plist, iOS 15, bildirim delegesi):
   ```bash
   flutter pub get
   ```
   ```bash
   bash tool/configure_ios.sh
   ```
   `ios/` klasörünü depoya koymak isteğe bağlıdır. Xcode'da elle değişiklik (ek yetki, uzantı,
   uygulama simgesi) yaptıysan koy: Codemagic depodaki klasörü kullanır, yeniden oluşturmaz.
3. **Supabase**: yeni proje aç → SQL Editor'da `supabase/schema.sql` dosyasını çalıştır →
   Authentication > Users bölümünden kendi kullanıcını (e-posta + şifre) oluştur.
   Başlangıç verisi kullanıcı oluştuğu anda yüklenir. Authentication > Sign In / Providers altında
   "Allow new users to sign up" seçeneğini kapat: başka kimse hesap açamasın.
4. **Anahtarlar**: `dart_defines.example.json` dosyasını `dart_defines.json` olarak kopyala ve doldur.
5. **Çalıştır** (HealthKit gerçek cihaz ister):
   ```bash
   flutter run --dart-define-from-file=dart_defines.json
   ```

## Otomatik raporlar

Günlük ve haftalık raporlar sunucuda, uygulama kapalıyken de üretilir:

```
pg_cron ──HTTP──▶ Edge Function generate-reports ──▶ Gemini
  her gün 23:45 İstanbul          → o günün günlük raporu   (daily_reports)
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

## Tarayıcı demosu ve ekran görüntüleri

Sunucu olmadan, örnek veriyle (bugünün öğünleri, antrenmanlar, 90 günlük kilo serisi, 3 haftalık ve
7 günlük rapor) çalışan demo. Depoda `web/` klasörü tutulmaz; deneme için ayrı bir kopyada üretilir:

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
     `GEMINI_API_KEY` ekle (Secure işaretli).
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
- **Gemini anahtarı uygulamanın içinde.** Tek kişilik dağıtım (dahili TestFlight / Ad-Hoc) için kabul edilebilir; .ipa başka
  birine verilirse anahtar çıkarılabilir. Google AI Studio'da anahtara kota sınırı koy. Daha sıkı güvenlik
  için çağrı bir Supabase Edge Function arkasına alınabilir.
- **AI kaydı iki adımlıdır**: Ayrıştır → önizle → Kaydet. Kaydetme tek transaction'dır
  (`quick_add_entries` RPC): bir tablo hata verirse hiçbiri yazılmaz.
- **Makro değerleri tahmindir.** Gemini standart besin değerlerinden hesaplar; önizlemede kontrol et.
- **Spor günleri varsayımdır** (ağırlık Pzt/Sal/Per/Cum, kickboks Çar, koşu Cmt, halı saha Paz).
  `routines.days_of_week` sütunundan değiştir.
- **Hedefler** (kilo, kalori, makro, adım, uyku), bildirim tercihleri ve ekip `user_settings` tablosundadır
  (varsayılan: 2000 kcal, 170 g protein); uygulama `settingsOrDefaultProvider` üzerinden okur.
- **Tekrarlayan işler** `routines` tablosundadır: günlük/haftalık (`frequency = 'weekly'`, `days_of_week`) ya da
  aylık (`frequency = 'monthly'`, `day_of_month`; 31 → kısa ayda ayın son günü). Aylık iş, gününden
  `monthly_lead_days` gün önce Gün ekranına düşer, günü geçince gecikmiş görünür, ay bitince kapanır.
  `routine_completions.completed_on` dönem anahtarıdır: günlük/haftalıkta o gün, aylıkta ayın 1'i.
  Anahtarın anlamı sıklığa bağlı olduğu için, bir rutinin sıklığı (günlük/haftalık ↔ aylık)
  değiştirilince o rutinin eski işaretleri silinir (`routines_frequency_changed` tetikleyicisi).
- **Şema yükseltmesi**: `supabase/schema.sql` yeniden çalıştırılabilir; eski sürümle kurulmuş veritabanını
  veriyi silmeden yükseltir (yeni sütunlar, `user_settings`, iki örnek aylık iş, rapor tabloları,
  `tasks.notify`). **Bu sürümü kurmadan önce şemayı yeniden çalıştır**: uygulama görev kaydederken
  `notify` sütununu yazar.
- **Görev hatırlatması**: formdaki "Hatırlat" kapalıysa (`tasks.notify = false`) görev termini olsa da
  bildirim almaz. AI ile eklenen görevler bildirimlidir; ayrı bir hatırlatma zamanı söylenmediyse
  bildirim, Ayarlar'daki "randevu kaç dk önce" süresi kadar önce gelir. Yükseltmede, eski formda hatırlatması kapalı
  kaydedilmiş görevler (elle eklenmiş, termini var, hatırlatma saati yok) bir kez kapalıya çevrilir.
- **iOS, HealthKit okuma izninin reddini uygulamaya bildirmez**; reddedilirse değerler 0 görünür.
- **Ek tablolar**: istenen 6 tabloya ek olarak `routine_completions` (dönem bazlı tamamlanma),
  `daily_health_metrics` (HealthKit günlük özeti), `user_settings` (kullanıcı başına tek satır) ve
  `daily_reports` (günlük rapor) vardır.
