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

## 7. Temel katmanın gerçekleşen API'si

Aşağıdaki imzalar koddaki son hâldir; H ve R dilimleri bunlara güvenebilir. Sözleşmeden sapmalar
**(ek)** ya da **(sapma)** olarak işaretlidir.

### Veritabanı (supabase/schema.sql, sürüm 3)
- `user_settings.timezone text not null default 'Europe/Istanbul'`. Dart `UserSettings` bu sütunu okumaz/yazmaz
  (upsert sütunu vermediği için değer korunur).
- `daily_reports` (yeni) ve `weekly_reports.ai_status / generated_at`. İki tabloda `authenticated` yalnızca
  `select` (politika `<tablo>_owner_select`); sürüm 2'nin `weekly_reports_owner_all` politikası ve yazma
  GRANT'leri kaldırılır. `service_role`: rapor tablolarında tam yetki + `user_settings` üzerinde `select`.
- Fonksiyonlar (hepsi `security definer`, yalnızca `service_role` çalıştırır):
  `report_daily_metrics(p_user uuid, p_day date) → jsonb`,
  `report_weekly_metrics(p_user uuid, p_week_start date) → jsonb` (Pazartesi değilse hata 22023),
  `save_daily_report(p_user, p_day, p_metrics jsonb, p_summary text, p_status text) → void`,
  `save_weekly_report(p_user, p_week_start, p_metrics jsonb, p_summary text, p_status text) → void`,
  **(ek)** ortak gövde `report_period_metrics(p_user, p_from date, p_to date, p_with_days boolean) → jsonb`.
- `metrics` kuralları (bölüm 2'ye ek kesinleştirmeler):
  - Oranlar tam sayıdır (yuvarlanır). `work.rate` paydası 0 ise `null`. `form.rate` paydası gün sayısını
    içerdiğinden veri olmasa da `0` çıkar; yalnızca dönemin tamamı gelecekteyse `null`.
  - **(ek)** Henüz gelmemiş günler (kullanıcının saat dilimine göre) planlı sayılmaz; `days` içinde bu
    günlerin `work_rate` ve `form_rate` değeri `null`dır. İçinde bulunulan hafta böylece kısmi üretilebilir.
  - Rutin, oluşturulduğu günden önce ve pasifken planlı sayılmaz (aylık rutinde de gün bazında).
    Rutin tamamlanması yalnızca planlı olduğu gün/dönem için sayılır.
  - Protein/kalori tutturma yalnızca öğün kaydı olan günlerde değerlendirilir; sınırlar dahildir
    (protein ≥ hedef × 0.9; hedef × 0.85 ≤ kalori ≤ hedef × 1.10).
  - Haftalıkta `nutrition.*` yalnızca kayıt girilen günlerin, `health.*` yalnızca değeri > 0 olan günlerin
    ortalamasıdır; hiç veri yoksa `0` ve `days_logged` / `days_with_data` = 0 (arayüz "veri yok" göstermeli).
  - `weight.end_kg` = dönemdeki son ölçüm; `start_kg` = dönemden önceki son ölçüm, yoksa dönemdeki ilk
    ölçüm; `change_kg` = end − start (biri yoksa `null`).
  - Bozuk `timezone` değeri `Europe/Istanbul` sayılır.

### Edge Function (supabase/functions/generate-reports)
- `index.ts` (Deno bağlantıları), **(ek)** `handler.ts` (istek akışı; bağımlılıklar dışarıdan verilir),
  `logic.ts` (saf mantık). Testler: `logic.test.mjs`, `handler.test.mjs` (Node).
- Yanıt: `{ok, kind, date, users, failed, ai_failed}` — **(ek)** `ai_failed`: raporu yazılan ama yorumu
  üretilemeyen kullanıcı sayısı. `failed`: raporu hiç yazılamayan kullanıcı sayısı. Durum kodları: 200;
  400 (gövde/tarih; tek kullanıcıda gelecekteki tarih), 401, 405, 500 (hiçbir rapor yazılamadı).
- Haftalıkta `date` haftanın herhangi bir günü olabilir; Pazartesi'ye çekilir. İçinde bulunulan hafta
  üretilebilir; hafta başı bugünden sonraysa reddedilir.
- **(sapma)** Dağıtım `--no-verify-jwt` ile yapılır (kimliği fonksiyon doğrular); aksi halde pg_cron çağrısı
  geçitte reddedilir.

### lib/core/utils/date_utils.dart **(ek)**
```dart
static DateTime AppDates.weekStart(DateTime d);        // haftanın Pazartesi'si, yerel gece yarısı
static DateTime AppDates.addDays(DateTime d, int days); // takvim günü ekler
```

### lib/features/health/domain/health_models.dart
```dart
class NutritionLog {
  const NutritionLog({required String id, required String foodName, required DateTime eatenAt,
      String mealType = 'snack', String? quantityText, double calories = 0, double proteinG = 0,
      double carbsG = 0, double fatG = 0, String source = 'manual'});
  static const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];
  static const int foodNameMaxLength = 200;
  static const double caloriesMax = 99999.9, macroMax = 9999.9;   // numeric(7,1) / numeric(6,1); alt sınır 0
  factory NutritionLog.fromMap(Map<String, dynamic>);
  Map<String, dynamic> toWriteMap();              // id / user_id / source içermez; eaten_at UTC
  NutritionLog copyWith({id, mealType, foodName, quantityText, bool clearQuantityText = false,
      calories, proteinG, carbsG, fatG, eatenAt, source});
}
class WorkoutLog {
  const WorkoutLog({required String id, required DateTime loggedAt, String workoutType = 'other',
      String? title, int? durationMin, double? distanceKm, int? caloriesBurned, String? notes,
      String source = 'manual'});
  static const workoutTypes = ['weights', 'kickboxing', 'running', 'football', 'other'];
  static const int durationMinMin = 1, durationMinMax = 600;
  static const double distanceKmMax = 9999.99;    // alt sınır 0; calories_burned ≥ 0
  factory WorkoutLog.fromMap(Map<String, dynamic>);
  Map<String, dynamic> toWriteMap();              // log_type = 'workout' dahil; logged_at UTC
  WorkoutLog copyWith({id, workoutType, title, durationMin, distanceKm, caloriesBurned, notes, loggedAt,
      source, clearTitle, clearDurationMin, clearDistanceKm, clearCaloriesBurned, clearNotes});
}
abstract final class WeightLimits { static const double minKg = 30, maxKg = 250; }   // (ek)
```

### lib/features/health/data/health_repository.dart (ek metotlar)
```dart
Future<List<NutritionLog>> fetchNutritionLogs(DateTime day);          // yerel gün, saat sırasıyla
Future<NutritionLog> createNutritionLog(NutritionLog log);            // id yok sayılır; source 'manual'
Future<NutritionLog> updateNutritionLog(NutritionLog log);
Future<void> deleteNutritionLog(String id);
Future<List<WorkoutLog>> fetchWorkouts(DateTime from, DateTime to);   // [from, to), YENİDEN ESKİYE
Future<WorkoutLog> createWorkout(WorkoutLog workout);                 // id yok sayılır; source 'manual'
Future<WorkoutLog> updateWorkout(WorkoutLog workout);
Future<void> deleteWorkout(String id);
Future<WeightEntry> addWeight(double weightKg, {DateTime? at});       // at yoksa şimdi
Future<void> deleteWeight(String id);
```

### lib/features/health/presentation/health_providers.dart (health_repository.dart'ı export eder)
```dart
const List<int> weightSeriesWindows = [30, 90];
final weightSeriesProvider      : FutureProvider.family<List<WeightEntry>, int>          // anahtar: gün sayısı; eskiden yeniye
final dayNutritionLogsProvider  : FutureProvider.family<List<NutritionLog>, DateTime>    // anahtar: yerel gün başı
const int recentWorkoutsDays = 30;
final recentWorkoutsProvider    : FutureProvider<List<WorkoutLog>>                       // yeniden eskiye
class WorkoutPlanDay { DateTime date; List<Routine> planned; List<WorkoutLog> done; bool get isPlanned, isDone; }
class WeekWorkoutPlan { DateTime weekStart; List<WorkoutPlanDay> days /* Pzt..Paz, 7 */; int get plannedCount, doneCount; }
WeekWorkoutPlan buildWeekWorkoutPlan(Iterable<Routine>, Iterable<WorkoutLog>, DateTime weekStart);   // saf (ek)
final weekWorkoutPlanProvider   : FutureProvider<WeekWorkoutPlan>                        // bu hafta
final weekStepsProvider         : FutureProvider<List<DailyHealthMetric>>                // bugünle biten 7 gün, tam 7 kalem
int? averageSteps(Iterable<DailyHealthMetric> days);                                      // (ek) verisi olan günler
void invalidateHealthData(ProviderContainer container);                                   // (ek)
```
`invalidateHealthData`: öğün/antrenman/kilo yazıldıktan sonra çağrılır; yukarıdaki dört veri sağlayıcısını,
`todayNutritionProvider`'ı (Kokpit) ve `monthOverviewProvider`'ı tazeler. `weekStepsProvider` HealthKit
eşitlemesine bağlıdır, bu çağrıyla tazelenmez. Mutasyon kalıbı:
`final container = ProviderScope.containerOf(context, listen: false); await repo.x(...); invalidateHealthData(container);`
AI hızlı giriş (`ai_quick_add_controller.dart`) kayıttan sonra ilgili Sağlık sağlayıcılarını da tazeler.

### lib/features/reports/domain/report_models.dart
```dart
enum ReportKind { daily, weekly }            // .apiValue → 'daily' | 'weekly'
enum ReportAiStatus { pending, ok, failed }  // ReportAiStatus.fromDb(Object?) — bilinmeyen = pending
class DayMetrics { DateTime date; int? workRate, formRate; double calories, proteinG;
                   int steps, sleepMinutes, workouts; static DayMetrics? tryParse(Object?); }
class ReportMetrics {
  DateTime? periodStart, periodEnd;
  int tasksTotal, tasksDone, routinesPlanned, routinesDone; int? workRate;
  int workoutsPlanned, workoutsDone, proteinDaysHit, calorieDaysInRange; int? formRate;
  double calories, proteinG, carbsG, fatG; int daysLogged;
  int steps, sleepMinutes, activeKcal, daysWithData;
  double? weightStartKg, weightEndKg, weightChangeKg;
  int? targetCalories, targetProteinG, targetSteps, targetSleepMinutes;
  List<DayMetrics> days;                     // eskiden yeniye; günlük raporda boş
  int? get routineRate, taskRate;            // (ek) payda 0 ise null
  bool get hasNutrition, hasHealth;          // (ek) daysLogged > 0 / daysWithData > 0
  static const ReportMetrics empty;
  factory ReportMetrics.fromJson(Object? json);   // eksik anahtar, null, metin sayı, int/double: hata vermez
}
class DailyReport  { DateTime reportDate; ReportMetrics metrics; String? aiSummary; ReportAiStatus aiStatus;
                     DateTime? generatedAt; bool get hasSummary; factory DailyReport.fromMap(Map<String, dynamic>); }
class WeeklyReport { DateTime weekStart; ReportMetrics metrics; String? aiSummary; ReportAiStatus aiStatus;
                     DateTime? generatedAt; DateTime get weekEnd; bool get hasSummary;
                     factory WeeklyReport.fromMap(Map<String, dynamic>); }
```
`hasSummary`: `aiStatus == ok` ve metin dolu. Oranlar 0..100'e sıkıştırılır.

### lib/features/reports/data/reports_repository.dart (report_models.dart'ı export eder)
```dart
final reportsRepositoryProvider : Provider<ReportsRepository>
Future<WeeklyReport?> fetchWeekly(DateTime weekStart);                 // haftanın herhangi bir günü; yoksa null
Future<List<WeeklyReport>> fetchWeeklyList({int limit = 12});          // yeniden eskiye
Future<DailyReport?> fetchDaily(DateTime day);                         // yoksa null
Future<List<DailyReport>> fetchDailyList(DateTime from, DateTime to);  // iki uç DAHİL, yeniden eskiye
Future<void> regenerate({required ReportKind kind, required DateTime date});   // hata: ReportGenerationException
class ReportGenerationException implements Exception { final String message; }  // (ek) toString() = message (Türkçe, gösterilebilir)
String reportErrorMessage(int status, Object? details);                          // (ek)
```

### lib/features/reports/presentation/reports_providers.dart (reports_repository.dart'ı export eder)
```dart
typedef ReportRange = ({DateTime from, DateTime to});                  // iki uç dahil
final weeklyReportProvider     : FutureProvider.family<WeeklyReport?, DateTime>      // anahtar: AppDates.weekStart(...)
final weeklyReportListProvider : FutureProvider<List<WeeklyReport>>
final dailyReportProvider      : FutureProvider.family<DailyReport?, DateTime>       // anahtar: yerel gün başı
final dailyReportListProvider  : FutureProvider.family<List<DailyReport>, ReportRange>
ReportRange lastSevenDays(DateTime day);                               // (ek) day ile biten 7 gün
Future<void> regenerateReport(WidgetRef ref, ReportKind kind, DateTime date);
```
`regenerateReport` başarıda da hatada da ilgili türün sağlayıcılarını tazeler; hatayı
(`ReportGenerationException`) çağırana iletir. Rapor yok = sağlayıcı değeri `null` (hata değil).

### Sahteler (lib/demo/demo_backend.dart; test/helpers/fakes.dart yalnızca bunu export eder)
- `FakeHealthRepository({metrics, weights, nutrition, nutritionLogs, workouts})`: yeni depo metotları bellekte
  uygulanır; ek alanlar `nutritionLogs`, `workouts`, `writeError`, `deletedIds`. `fetchNutritionTotals`, hazır
  `nutrition` toplamlarına `nutritionLogs` toplamını ekler.
- `FakeKokpitRepository({nutrition, error, health})`: `health` verilirse özet o deponun öğün kayıtlarından hesaplanır.
- `FakeReportsRepository({weekly, daily, weeklyBuilder, dailyBuilder})`: `weekly`, `daily`, `fetchError`,
  `regenerateError`, `regenerateGate` (Completer), `regenerated` (`({ReportKind kind, DateTime date})`; haftalıkta
  Pazartesi). `regenerate`, üretici verilmişse raporu listeye yazar.
- Demo (`lib/demo/demo_data.dart`): `DemoData.reports`; `demoWeeklyReport(weekStart, now)`,
  `demoDailyReport(day, now)`; bugünün 4 öğün kalemi, son iki haftanın antrenmanları, 90 günlük kilo serisi,
  3 haftalık rapor (bu hafta kısmi), dünle biten 7 günlük rapor (bugününki yok → "Raporu oluştur" durumu).
  `lib/main_demo.dart` `reportsRepositoryProvider`'ı override eder.

Widget testinde tipik override listesine `reportsRepositoryProvider` (R) eklenir; H için mevcut
`healthRepositoryProvider` + `routinesRepositoryProvider` yeterlidir.

## 8. Birleştirme (entegrasyon) notları

- **Bildirim izni**: `NotificationService.hasPermission()` izin durumunu pencere açmadan okur
  (iOS `checkPermissions`, Android `areNotificationsEnabled`). `notificationPermissionProvider` bunu kullanır;
  Ayarlar'ı açmak izin sormaz. Ayarlar'daki "İzin iste" butonu `requestPermission()` çağırır.
  `notificationSyncProvider` bildirimler açıkken izni eskisi gibi ister. Sahte: `FakeNotificationService`
  `hasPermission()` + `permissionRequests` sayacı.
- **`tasks.notify boolean not null default true`** (schema.sql; sütun yoksa eklenir ve o anda, bir kez,
  `source = 'manual'` + termini olan + `remind_at` boş görevler `false` yapılır). `TaskItem.notify`,
  `TasksRepository.create(..., bool notify = true)`, `toWriteMap()['notify']`. Görev formu: "Hatırlat" kapalı →
  `notify = false`, `remind_at = null`; düzenlemede anahtar `notify` değerinden açılır. `quick_add_entries`
  görevleri `notify = true` yazar. `buildNotificationPlan` `notify = false` görevi atlar.
- **Ekran görüntüsü testi** (`test/screenshots/app_screens_test.dart`): demo verisini (`DemoData.seed`) kullanır,
  Sağlık (09–11) ve Raporlar (12–15) görüntülerini de üretir. Görüntüler güne/saate bağlı olduğundan test
  yalnızca `--update-goldens` ile çalışır; olağan `flutter test` çalışmasında atlanır.
- **Demo**: `FakeReportsRepository.regenerateDelay` ve `DemoData.seed(now, regenerateDelay:)`; tarayıcı demosunda
  "Raporu oluştur" 900 ms sürer.

## 9. Son inceleme düzeltmeleri (davranış ve API ekleri)

- **HealthKit geçmiş günleri**: `HealthService.readPastDays({int days = HealthService.backfillDays /* 7 */, DateTime? now})
  → List<HealthDayReading>` (`typedef HealthDayReading = ({DateTime day, HealthSnapshot snapshot})`); pencereler saf
  `healthDayWindows(now, {pastDays})` ile hesaplanır: adım/enerji `[gün 00:00, ertesi 00:00)` (bugünde şu ana kadar),
  uyku `[önceki gün 18:00, o gün 18:00)` (bugünde en geç şu an). `HealthRepository.upsertHealthDays(days)` verisi olan
  günleri tek istekte yazar. `backfillHealthKit(container)` (health_providers.dart): bugünün okumasını bekler, geçmiş
  günleri okuyup yazar, `weekStepsProvider` ve `monthOverviewProvider`'ı tazeler; `resyncHealthKit(container)` önce
  `healthTodayProvider`'ı tazeler, sonra aynısını yapar. `healthTodayProvider` doğrudan `invalidate` edilmez; yenileme
  hep `resyncHealthKit` ile yapılır (Kokpit ve Sağlık yenilemesi, "Tekrar dene"/"Bağlan", Ayarlar'daki yeniden bağlanma).
- **Açılış ve öne geliş** (`home_shell.dart`): açılışta `backfillHealthKit`; `resumed` olduğunda saat, bugünün rutinleri,
  yaklaşanlar, `invalidateHealthData` (Sağlık sekmesi, Kokpit beslenme özeti, Ay özeti), `resyncHealthKit` ve dört rapor
  sağlayıcısı tazelenir.
- **AI görevinde hatırlatma**: `ParsedTask.remindAt` yalnızca kullanıcı ayrı bir hatırlatma zamanı söylediyse doludur
  (terminle aynı an boş sayılır). Boşsa bildirim `due_at − event_remind_minutes` anındadır; kayıt anındaki anlık planlama
  (`QuickAddController.save`) ve `buildNotificationPlan` aynı kuralı uygular. `SavedTask.dueAt` eklendi.
- **Rutin sıklığı değişimi**: `routines_frequency_changed` tetikleyicisi (schema.sql) sıklığı değişen rutinin
  `routine_completions` satırlarını siler; `FakeRoutinesRepository.update` aynısını yapar.
- **Form sayfaları**: kayıt bitince `closeOpsSheet(navigator, route)` (operations_widgets.dart) çağrılır; `route`, kayıttan
  önce `ModalRoute.of(context)` ile alınır ve yalnızca hâlâ en üstteyse kapatılır (kayıt sürerken kapatılan sayfa alttaki
  rotayı kapatmasın).
- **Operasyon**: `notifyRoutineChange` `weekWorkoutPlanProvider`'ı da tazeler; `OpsTasksNotifier.applySaved(TaskItem)` bu
  oturumda tamamlanmış görevin listede tutulan kopyasını formdan kaydedilen hâliyle değiştirir.
- **Bildirim eşitleme**: `notificationSyncProvider` turlarının eklenti çağrıları tek sıraya dizilir; bayatlayan tur
  (sağlayıcı tazelenmiş) eklentiye dokunmaz.
- **Sahteler**: `FakeHealthService(snapshot, {pastDays})` + `pastDayReads`; `FakeHealthRepository.upsertHealthMetrics` /
  `upsertHealthDays` verisi olan okumayı `metrics`'e yazar, `upsertedDays` yazılan günleri tutar.
