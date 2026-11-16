# Kişisel Asistan & Operasyon Merkezi

Tek kullanıcılı, iOS Ad-Hoc dağıtımlı Flutter uygulaması.
Flutter · Riverpod · Supabase · Gemini (`gemini-2.5-flash`) · HealthKit · yerel bildirimler.

## Klasör mimarisi (feature-first)

```
kisisel_asistan/
├── pubspec.yaml
├── analysis_options.yaml
├── codemagic.yaml                      # iOS Ad-Hoc .ipa derlemesi
├── dart_defines.example.json           # yerel derleme anahtar şablonu
├── supabase/
│   └── schema.sql                      # tablolar, indeksler, RLS, RPC, seed
├── ios_setup/
│   ├── Info.plist.additions.xml        # Info.plist'e eklenecek anahtarlar
│   └── Runner.entitlements             # HealthKit yetkisi
├── tool/
│   └── configure_ios.sh                # ios/ klasörünü otomatik yapılandırır
├── preview/
│   └── operasyon-merkezi-onizleme.html # tarayıcı önizlemesi (örnek veri)
└── lib/
    ├── main.dart                       # başlatma: Supabase, bildirim, tarih
    ├── app.dart                        # MaterialApp + yapılandırma hata ekranı
    ├── core/
    │   ├── config/
    │   │   ├── env.dart                # --dart-define anahtarları
    │   │   └── app_targets.dart        # görev/not kategori listeleri
    │   ├── theme/app_theme.dart        # koyu tema, renk sistemi
    │   ├── utils/date_utils.dart
    │   ├── widgets/module_roadmap_view.dart
    │   └── services/
    │       ├── supabase_providers.dart # client + oturum akışı
    │       ├── health_service.dart     # HealthKit: adım, uyku, aktif kalori
    │       ├── notification_service.dart # saatli hatırlatma + rutin bildirimi
    │       └── notification_sync.dart  # bekleyen bildirimleri veritabanıyla eşitler
    └── features/
        ├── auth/presentation/          # auth_gate.dart, sign_in_screen.dart
        ├── shell/presentation/         # home_shell.dart (4 sekme + AI butonu)
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
        ├── health/
        │   ├── domain/health_models.dart
        │   ├── data/health_repository.dart
        │   └── presentation/           # health_screen.dart
        └── reports/                    # sekme
```

Faz 2'de her özellik aynı kalıbı izler: `domain/` (modeller) → `data/` (repository) → `presentation/` (provider + ekran).

## Kurulum

1. **iOS projesini oluştur** (Mac'te, bu klasörde). `com.ornek` yerine kendi kimliğini yaz:
   ```bash
   flutter create --platforms=ios --org com.ornek --project-name kisisel_asistan .
   ```
2. **iOS'u yapılandır** (HealthKit, Info.plist, iOS 15, bildirim delegesi):
   ```bash
   flutter pub get
   ```
   ```bash
   bash tool/configure_ios.sh
   ```
3. **Supabase**: yeni proje aç → SQL Editor'da `supabase/schema.sql` dosyasını çalıştır →
   Authentication > Users bölümünden kendi kullanıcını (e-posta + şifre) oluştur.
   Başlangıç verisi kullanıcı oluştuğu anda yüklenir. Authentication > Sign In / Providers altında
   "Allow new users to sign up" seçeneğini kapat: başka kimse hesap açamasın.
4. **Anahtarlar**: `dart_defines.example.json` dosyasını `dart_defines.json` olarak kopyala ve doldur.
5. **Çalıştır** (HealthKit gerçek cihaz ister):
   ```bash
   flutter run --dart-define-from-file=dart_defines.json
   ```

## Ad-Hoc dağıtım (Codemagic)

1. developer.apple.com: App ID oluştur (HealthKit yetkisi açık), iPhone'unun UDID'ini Devices'a ekle,
   bu App ID + cihaz için **Ad Hoc** provisioning profile üret.
2. Codemagic > Teams > Code signing identities: dağıtım sertifikasını (.p12) ve profili yükle.
3. Codemagic > Environment variables: `app_secrets` grubuna `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `GEMINI_API_KEY` ekle (Secure).
4. `codemagic.yaml` içindeki `com.ornek.kisiselAsistan` değerini iki yerde kendi Bundle ID'nle değiştir.
5. `main` dalına push → `.ipa` Artifacts altında. Codemagic'in kurulum bağlantısından iPhone'a yükle.

## Bilinmesi gerekenler

- **Gemini anahtarı uygulamanın içinde.** Tek kişilik Ad-Hoc dağıtım için kabul edilebilir; .ipa başka
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
- **Şema yükseltmesi**: `supabase/schema.sql` yeniden çalıştırılabilir; eski sürümle kurulmuş veritabanını
  veriyi silmeden yükseltir (yeni sütunlar, `user_settings`, iki örnek aylık iş).
- **iOS, HealthKit okuma izninin reddini uygulamaya bildirmez**; reddedilirse değerler 0 görünür.
- **Ek tablolar**: istenen 6 tabloya ek olarak `routine_completions` (dönem bazlı tamamlanma),
  `daily_health_metrics` (HealthKit günlük özeti) ve `user_settings` (kullanıcı başına tek satır) vardır.
