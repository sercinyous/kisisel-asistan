# Faz 3 — Tasarım sözleşmesi

Faz 3: **Sağlık** ve **Raporlar** sekmeleri + **otomatik günlük ve haftalık raporlar**.
Faz 2 sözleşmesi (`docs/SPEC_FAZ2.md`) ve `CLAUDE.md` geçerliliğini korur. Görsel referans:
`preview/faz3-taslak.html` (kullanıcı onayladı; kart sırası ve içerikleri bağlayıcıdır).

Kullanıcı kararları:
1. Grafikler `fl_chart` paketiyle çizilir.
2. Günlük ve haftalık raporlar **otomatik** üretilir (sunucu tarafında, uygulama kapalıyken de).
   Kullanıcı sunucuyu kendisi bağlayacak; depo, çalıştırılmaya hazır her şeyi içerir.
3. Uygulamada ayrıca "Raporu yeniden oluştur" butonu bulunur.

## 1. Otomatik rapor mimarisi

```
pg_cron (Supabase) ──HTTP──▶ Edge Function generate-reports ──▶ Gemini
        her gün 23:45 İstanbul: günlük rapor (o gün)
        her Pazartesi 07:00 İstanbul: haftalık rapor (biten hafta, Pzt–Paz)
Uygulama ("yeniden oluştur") ──functions.invoke (kullanıcı JWT)──▶ aynı fonksiyon
```
- Sayılar SQL'de hesaplanır (`report_daily_metrics`, `report_weekly_metrics`), Gemini yalnızca
  yorum metnini yazar. Gemini başarısız olursa rapor sayılarla kaydedilir (`ai_status='failed'`),
  uygulama sayıları yine gösterir.
- Gemini anahtarı rapor için **sunucuda** durur (Edge Function secret `GEMINI_API_KEY`).

## 2. Veritabanı (supabase/schema.sql — tek dosya, idempotent; v2 → v3 yükseltmesi dahil)

### user_settings
`timezone text not null default 'Europe/Istanbul'` eklenir (rapor günü/haftası bu dilime göre).

### daily_reports (yeni)
```
id uuid pk, user_id uuid not null → auth.users on delete cascade,
report_date date not null, metrics jsonb not null default '{}',
ai_summary text, ai_status text not null default 'pending' check in ('pending','ok','failed'),
generated_at timestamptz not null default now(), unique (user_id, report_date)
```
### weekly_reports
`ai_status` (aynı check) ve `generated_at` eklenir. Mevcut sayısal sütunlar doldurulmaya devam eder;
tam sayı kümesi `metrics` jsonb içindedir.

RLS: iki rapor tablosunda `authenticated` yalnızca **kendi satırını okur** (select politikası ve
select GRANT). Yazma yalnızca service_role (Edge Function) ile yapılır.

### SQL fonksiyonları (yalnızca service_role çalıştırır; authenticated/anon için REVOKE)
- `report_daily_metrics(p_user uuid, p_day date) returns jsonb`
- `report_weekly_metrics(p_user uuid, p_week_start date) returns jsonb`  (p_week_start Pazartesi)
- `save_daily_report(p_user, p_day, p_metrics jsonb, p_summary text, p_status text)`
- `save_weekly_report(p_user, p_week_start, p_metrics jsonb, p_summary text, p_status text)`
  (upsert; weekly sayısal sütunları metrics'ten doldurur)

Gün sınırları kullanıcının `timezone`'una göredir. `metrics` şekli (her iki rapor; haftalıkta
toplam/ortalama + `days` dizisi):
```
{ "period": {"start":"YYYY-MM-DD","end":"YYYY-MM-DD"},
  "work":  {"tasks_total":n,"tasks_done":n,"routines_planned":n,"routines_done":n,"rate":0..100},
  "form":  {"workouts_planned":n,"workouts_done":n,"protein_days_hit":n,"calorie_days_in_range":n,"rate":0..100},
  "nutrition": {"calories":x,"protein_g":x,"carbs_g":x,"fat_g":x,"days_logged":n},   // haftalıkta günlük ortalama
  "health": {"steps":n,"sleep_minutes":n,"active_kcal":n,"days_with_data":n},        // haftalıkta ortalama
  "weight": {"start_kg":x|null,"end_kg":x|null,"change_kg":x|null},
  "targets": {"calories":n,"protein_g":n,"steps":n,"sleep_minutes":n},
  "days": [ {"date":"YYYY-MM-DD","work_rate":0..100|null,"form_rate":0..100|null,
             "calories":x,"protein_g":x,"steps":n,"sleep_minutes":n,"workouts":n} ]   // yalnız haftalık
}
```
Kurallar: `work.rate` = (tasks_done + routines_done) / (tasks_total + routines_planned); payda 0 ise null.
Görev "o döneme ait" = `due_at` o aralıkta; "done" = status='done'. Rutinler: haftalık/günlük rutinler
`days_of_week` ve `created_at`'e göre planlanır; aylık rutin, günü o aralığa düşüyorsa planlanır
(gün = min(day_of_month, ayın son günü)); tamamlanma `routine_completions` dönem anahtarından okunur.
`form.workouts_planned` = category='spor' rutinlerinin o aralıktaki planlı sayısı;
`workouts_done` = `fitness_logs` (log_type='workout') sayısı. Protein tutturma: günlük protein ≥ hedefin %90'ı.
Kalori aralığı: hedefin %85–%110'u. `form.rate` = (min(workouts_done, planned) + protein_days_hit) /
(planned + gün sayısı). Bu kurallar Dart tarafında tekrar hesaplanmaz; uygulama `metrics`'i gösterir.

### supabase/functions/generate-reports/index.ts (Deno Edge Function)
- Gövde: `{ "kind": "daily"|"weekly", "date"?: "YYYY-MM-DD" }` (date yoksa: daily = kullanıcının bugünü,
  weekly = biten son hafta).
- Yetki: (a) `x-cron-secret` başlığı `CRON_SECRET` ile eşleşirse **tüm kullanıcılar** için üretir;
  (b) aksi halde `Authorization: Bearer <kullanıcı JWT>` doğrulanır ve **yalnızca o kullanıcı** için üretir;
  ikisi de yoksa 401. Sabit zamanlı karşılaştırma. service_role istemcisi yalnızca sunucuda.
- Akış: metrics RPC → Gemini (`gemini-2.5-flash`, Türkçe, düz metin, günlük ≤ 70 kelime / haftalık ≤ 120
  kelime + en fazla 3 öneri, yalnızca verilen sayılara dayan, tıbbi tavsiye yok) → save RPC.
  Gemini hata verirse `ai_status='failed'`, özet null. Yanıt: `{ok, kind, date, users, failed}`.
- Girdi doğrulama (kind, tarih biçimi, gelecekteki tarih reddi), 30 sn zaman aşımı, kullanıcı başına hata
  diğer kullanıcıları durdurmaz. Ortam: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `GEMINI_API_KEY`,
  `CRON_SECRET`, isteğe bağlı `GEMINI_MODEL`.

### supabase/cron.sql (ayrı dosya; kullanıcı proje URL'si ve gizli anahtarı Vault'a koyduktan sonra çalıştırır)
`pg_cron` + `pg_net` etkinleştirir; iki zamanlama: `45 20 * * *` (UTC) günlük, `0 4 * * 1` (UTC) haftalık.
URL ve `CRON_SECRET` Vault'tan okunur (dosyada gizli değer yok). İdempotent (aynı adlı iş yeniden kurulur).

## 3. Dart — Temel (Foundation) katmanı
```
pubspec.yaml: fl_chart eklenir.
lib/features/health/domain/health_models.dart   (+ NutritionLog, WorkoutLog; alanlar tablo sütunlarıyla bire bir)
lib/features/health/data/health_repository.dart (+ fetchNutritionLogs(day), createNutritionLog, updateNutritionLog,
    deleteNutritionLog, fetchWorkouts(from,to), createWorkout, updateWorkout, deleteWorkout, addWeight, deleteWeight)
lib/features/reports/domain/report_models.dart
    class ReportMetrics (jsonb'den toleranslı ayrıştırma; yukarıdaki şeklin tipli erişimcileri; DayMetrics listesi)
    class DailyReport { reportDate, metrics, aiSummary, aiStatus, generatedAt }
    class WeeklyReport { weekStart, metrics, aiSummary, aiStatus, generatedAt }
    enum ReportAiStatus { pending, ok, failed }
lib/features/reports/data/reports_repository.dart
    reportsRepositoryProvider (oturum kullanıcı id'sine bağlı)
    fetchWeekly(weekStart), fetchWeeklyList({limit}), fetchDaily(day), fetchDailyList(from, to),
    regenerate({required ReportKind kind, required DateTime date})   // functions.invoke('generate-reports')
lib/features/reports/presentation/reports_providers.dart
    weeklyReportProvider.family(weekStart), weeklyReportListProvider, dailyReportProvider.family(day),
    dailyReportListProvider.family(range), regenerateReport(ref, kind, date) (ilgili sağlayıcıları tazeler)
lib/features/health/presentation/health_providers.dart
    weightSeriesProvider (son 30/90 gün), dayNutritionLogsProvider.family(day), recentWorkoutsProvider,
    weekWorkoutPlanProvider (bu hafta planlı spor rutinleri + yapılanlar), weekStepsProvider (7 gün)
test/helpers/fakes.dart + lib/demo/demo_backend.dart: yeni depo metotları ve FakeReportsRepository
lib/demo/demo_data.dart: iki sekme için örnek veri (öğün kayıtları, antrenmanlar, 3 haftalık rapor, 7 günlük rapor)
lib/main_demo.dart: reportsRepositoryProvider override
```
Not: `lib/demo/demo_backend.dart` ile `test/helpers/fakes.dart` aynı sahteleri içerir; Temel, kopyayı
kaldırıp testlerin `package:kisisel_asistan/demo/demo_backend.dart`'ı kullanmasını sağlar
(`test/helpers/fakes.dart` yalnızca `export` eder), böylece tek kaynak kalır.

## 4. Dilim H — Sağlık sekmesi (sahip: lib/features/health/presentation/**, test/widget/health_*)
Taslaktaki sıra: Kilo kartı (çizgi grafik, kesikli hedef çizgisi, son nokta vurgulu, doğrudan etiketler,
30/90 gün seçimi, "bu ay" ve "hedefe kalan" etiketleri, kilo ekle) → Antrenman (bu hafta x / plan, gün gün
yapıldı/planlı) + Adım (7 gün çubuk, ortalama) yan yana → Bugünün öğünleri (öğün bazında gruplanmış; kayıt
ekle/düzenle/sil formu: öğün, ad, miktar, kalori, protein, karbonhidrat, yağ, saat) → Antrenman günlüğü
(ekle/düzenle/sil formu: tür, başlık, süre, mesafe, kalori, not, zaman) → HealthKit kartı (durum, son eşitleme,
yeniden bağlan). Her bölümde yükleniyor / boş / hata+tekrar dene. Formlar DB sınırlarıyla doğrular.
Mutasyon sonrası ilgili sağlayıcılar tazelenir (kokpit beslenme özeti, ay özeti dahil).

## 5. Dilim R — Raporlar sekmesi (sahip: lib/features/reports/presentation/**, test/widget/reports_*)
Üstte `SegmentedButton`: **Haftalık | Günlük**.
- Haftalık (taslaktaki sıra): hafta seçici (‹ 10 – 16 Kasım ›, gelecek haftaya gidilmez) → İş ve Form yüzde
  kartları yan yana → Günlük tamamlama grafiği (gün başına iş + form çubukları; renk + lejant etiketi) →
  ortalamalar ızgarası (kalori, protein, kilo değişimi, adım, uyku, aktif kalori) → AI haftalık değerlendirme
  kartı (ai_status: ok → metin; failed → "Yorum üretilemedi" + sayılar; rapor yoksa "Bu hafta için rapor henüz
  oluşmadı" + "Raporu oluştur") + "Raporu yeniden oluştur" → Geçmiş haftalar listesi (dokununca o haftaya gider).
- Günlük: gün seçici → o günün iş/form kartları, beslenme ve sağlık sayıları hedeflerle → AI günlük değerlendirme
  → son 7 günün kısa listesi.
- Yeniden oluşturma sırasında buton meşgul durumda; hata olursa satır içi hata + tekrar dene.

## 6. Ortak kurallar
- `CLAUDE.md` geçerli: OLED siyah, `BentoGrid`/`BentoCard`, `AppColors`/`AppRadii`/`AppSpacing`, ham hex yok.
- Grafik erişilebilirliği: seri yalnızca renkle ayrılmaz (lejant etiketi + doğrudan değer etiketi);
  grafiklere `Semantics` özeti; dokunma hedefleri ≥ 44pt.
- 375pt genişlik ve metin ölçeği 1.3'te taşma yok (widget testi).
- Hız kuralı: dosya başına analyze/test yok; dilim sonunda tek seferlik kontrol. Testler önce yazılır
  (test-önce), ama topluca en sonda çalıştırılır.
- `// TODO` ve yer tutucu yok.
