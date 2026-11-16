# Faz 2 — Tasarım sözleşmesi

Bu belge Faz 2'nin ortak sözleşmesidir. Dosya yolları, sınıf/sağlayıcı adları ve tablo
sütunları burada yazdığı gibi kullanılır; bir dilim başka bir dilimin dosyasına yazmaz.

Kullanıcı kararları (onaylandı):

1. Üç tür kayıt: **tekrarlayan** (günlük/haftalık/aylık, her dönem ayrı işaretlenir),
   **tek seferlik** (görev/randevu), **sağlık verisi**.
2. Aylık iş, gününden `monthly_lead_days` (varsayılan 3) gün önce Gün ekranına düşer ve
   işaretlenene kadar kalır. Günü geçince **gecikti** olur; ay bitince o ayın kaydı
   **yapılmadı** olarak kapanır, yeni ayınki açılır. Eski aylar birikmez.
3. Aylık işin günü hafta sonuna denk gelse de tarih sabittir.
4. Giriş ikiye ayrılır: **İş girişi** ve **Sağlık & beslenme girişi**. Birbirine karışmaz.
5. **Ayarlar** ekranı: hedefler (kilo, kalori, makro, adım, uyku), bildirimler, ekip, hesap.

UI metinleri Türkçedir. Kod yorumları Türkçe, kısa ve "neden"i açıklar.

## 1. Veritabanı (supabase/schema.sql — tek dosya, idempotent kalır)

Yeni sütunlar `alter table ... add column if not exists` ile eklenir; `create table if not
exists` blokları da yeni sütunları içerecek şekilde güncellenir (yeni kurulum = eski+alter).

### routines (ek sütunlar)
| sütun | tip | not |
|---|---|---|
| `frequency` | text not null default 'weekly' check in ('weekly','monthly') | 'weekly' = `days_of_week` kullanılır (7 gün = günlük) |
| `day_of_month` | smallint null check 1..31 | `frequency='monthly'` ise zorunlu (check constraint) |
| `scope` | text not null default 'Kişisel' check in ('Pusholder','Kişisel') | iş / kişisel ayrımı |

`category` check listesine `'finans'` eklenir: ('operasyon','spor','beslenme','kisisel','finans').
Aylık işin bir aydaki günü = `min(day_of_month, o ayın son günü)` (31 → Şubat'ta 28/29).

### routine_completions
`completed_on` **dönem anahtarıdır**: haftalık/günlük rutinde o gün; aylık rutinde o ayın
1'i. `unique (routine_id, completed_on)` aynen kalır.

### user_settings (yeni; kullanıcı başına tek satır)
```
user_id uuid primary key default auth.uid() references auth.users on delete cascade
start_weight_kg numeric(5,2) not null default 84.5   check 30..250
target_weight_kg numeric(5,2) not null default 78    check 30..250
daily_calories integer not null default 2000         check 800..6000
daily_protein_g integer not null default 170         check 0..500
daily_carbs_g integer not null default 180           check 0..800
daily_fat_g integer not null default 65              check 0..400
daily_steps integer not null default 10000           check 1000..60000
sleep_minutes integer not null default 450           check 180..900
notifications_enabled boolean not null default true
routine_notifications boolean not null default true
monthly_lead_days smallint not null default 3        check 0..14
monthly_remind_time time not null default '09:00'
event_remind_minutes smallint not null default 30    check 0..1440
quiet_hours_enabled boolean not null default true
quiet_start time not null default '23:00'
quiet_end time not null default '07:30'
team_members text[] not null default '{Duhan,İlhan,Mehmet,Sedat}'
updated_at timestamptz not null default now()
```
RLS (owner_all politikası), `authenticated` için select/insert/update/delete GRANT, `anon`
için REVOKE, `set_updated_at` trigger'ı. RLS/GRANT döngü ve listelerine eklenir.

### quick_add_entries(payload jsonb)
Mevcut dizilere ek olarak `routines` dizisini kabul eder:
`{title, scope, category, frequency, days_of_week int[], day_of_month int, time_of_day "HH:MM"|null}`
→ `routines` tablosuna yazar (`notify` true). Dönüşe `routine_count` eklenir. Tek transaction.

### Seed
Mevcut 'operasyon' rutinleri `scope='Pusholder'`, diğerleri 'Kişisel'. İki aylık örnek eklenir:
"Maaş ödemeleri" (monthly, 15, Pusholder, finans, 10:00) ve "Aylık push performans raporu"
(monthly, 1, Pusholder, operasyon, 10:00). `user_settings` satırı varsayılanlarla eklenir.

## 2. Dart katmanları ve dosya sahipliği

### Temel (Foundation) — herkesin bağımlı olduğu katman
```
lib/features/settings/domain/user_settings.dart
    class UserSettings { ...tüm alanlar; const UserSettings.defaults(); fromMap; toMap; copyWith }
    saat alanları için: class TimeOfDayValue { final int hour, minute; "HH:mm" parse/format }
lib/features/settings/data/settings_repository.dart
    settingsRepositoryProvider
    Future<UserSettings> fetch()   // satır yoksa varsayılanı upsert edip döner
    Future<UserSettings> save(UserSettings)
lib/features/settings/presentation/settings_providers.dart
    userSettingsProvider : AsyncNotifierProvider<UserSettingsNotifier, UserSettings>  (save())
    settingsOrDefaultProvider : Provider<UserSettings>   // yüklenene kadar varsayılan
lib/features/settings/presentation/settings_screen.dart     // Temel yalnızca iskelet; D doldurur

lib/features/routines/domain/routine.dart
    enum RoutineFrequency { weekly, monthly }
    class Routine { id,title,scope,category,frequency,daysOfWeek,dayOfMonth,hour,minute,notify,isActive,sortOrder;
                    fromMap; toInsertMap; copyWith; bool get isDaily; String? get timeLabel }
    enum OccurrenceStatus { done, dueToday, upcoming, overdue, missed }
    class RoutineOccurrence { routine, periodKey (DateTime, yerel gün), dueDate, completed, status;
                              int daysUntilDue(today) }
    saf fonksiyonlar (birim testli):
      DateTime monthlyDueDate(Routine r, int year, int month)
      DateTime periodKeyFor(Routine r, DateTime day)
      List<RoutineOccurrence> occurrencesForDay(routines, completions, day)         // yalnız weekly
      List<RoutineOccurrence> monthlyForDay(routines, completions, today, leadDays) // penceredeki + geciken, tamamlananlar o gün görünmeye devam eder
      List<RoutineOccurrence> monthlyForMonth(routines, completions, year, month, today)
    class RoutineCompletionKey { routineId, periodKey }  (Set üyeliği için == / hashCode)
lib/features/routines/data/routines_repository.dart
    routinesRepositoryProvider (oturum kullanıcı id'sine bağlı, kokpitRepositoryProvider gibi)
    fetchActive(), fetchAll(), fetchCompletions(from, to),
    setCompleted({routineId, periodKey, completed}), create(Routine), update(Routine), delete(id)
lib/features/routines/presentation/routines_providers.dart
    activeRoutinesProvider      : FutureProvider<List<Routine>>
    todayOccurrencesProvider    : AsyncNotifierProvider<..., TodayOccurrences>
        TodayOccurrences { List<RoutineOccurrence> daily; List<RoutineOccurrence> monthly; }
        toggle(RoutineOccurrence)   // mevcut _overrides/_writeSeq yarış koruması korunur
    monthOverviewProvider       : FutureProvider.family<MonthOverview, DateTime>  (ayın 1'i)
        MonthOverview { month, monthly: List<RoutineOccurrence>, tasks: List<TaskItem>,
                        weeklyPlanned, weeklyDone, health: MonthHealthSummary }
    toggleMonthly(ref, occurrence)  // Ay ekranından işaretleme; ilgili sağlayıcıları tazeler

lib/features/operations/data/tasks_repository.dart
    tasksRepositoryProvider
    fetchOpen(), fetchInRange(from, to), fetchUpcoming({from, limit}), create(...), update(...),
    complete(id), reopen(id), delete(id)
lib/features/operations/data/notes_repository.dart
    notesRepositoryProvider; fetchAll({category}), create, update, delete
lib/features/health/data/health_repository.dart
    healthRepositoryProvider
    fetchDailyMetrics(from, to), fetchWeights(from, to), fetchNutritionTotals(from, to),
    upsertHealthMetrics(day, snapshot)
    class MonthHealthSummary { avgSteps, avgSleepMinutes, avgCalories, avgProteinG,
                               weightStartKg, weightEndKg, daysWithData }
lib/core/services/notification_sync.dart
    notificationSyncProvider   // kokpit_providers.dart'tan buraya taşınır
```
Temel ayrıca: `RoutineItem`'ı kaldırıp Kokpit'i yeni sağlayıcılara geçirir (davranış aynı),
`AppTargets`'taki sayısal hedefleri `settingsOrDefaultProvider`'a bağlar (`AppTargets` yalnızca
kategori listeleri için kalır), `flutter_localizations` ekleyip `MaterialApp`'e `tr_TR`
yerelini verir (tarih/saat seçiciler Türkçe olsun), test sahtelerini (test/helpers/fakes.dart)
günceller. Temel bittiğinde `flutter analyze` (0 hata/uyarı) ve `flutter test` yeşildir.

### Dilim B — Kokpit Gün / Ay  (sahip: lib/features/kokpit/**, test/widget/kokpit_*)
- Başlıkta sağ üstte dişli → `SettingsScreen` (Navigator.push).
- Başlığın altında `SegmentedButton`: **Gün | Ay**.
- **Gün:** kalori/makro kartı, sağlık kartı (hedefler ayarlardan), "Bugünün rutinleri",
  "Yaklaşan aylık işler" (yalnızca varsa; her satırda durum: "3 gün kaldı" / "Bugün" /
  "2 gün gecikti" ve işaret kutusu), "Bugün ve yaklaşanlar" (tek seferlik görev/randevular).
- **Ay:** ay değiştirici (‹ Kasım 2026 ›), takvim ızgarası (Pzt başlangıç; gün hücresinde
  nokta: aylık iş = sarı, randevu/görev = mavi; bugün vurgulu; güne dokununca altında o günün
  listesi), "Aylık sabitler" listesi (durum rozeti: Yapıldı / Bekliyor / Bugün / Gecikti /
  Yapılmadı; geçmiş ayda salt okunur), "Bu ayın randevuları", "Ay özeti" (rutin tamamlama %,
  görev tamamlama, ort. adım, ort. uyku, ort. kalori, kilo değişimi).
- 375pt genişlikte ve metin ölçeği 1.3'te taşma olmamalı (widget testi).

### Dilim C — İki ayrı AI girişi  (sahip: lib/features/ai_quick_add/**, ilgili testler,
ve lib/features/shell/presentation/home_shell.dart)
- `enum QuickAddMode { work, health }`.
- İş modu şeması: `tasks`, `notes`, `routines`. Sağlık modu şeması: `nutrition`, `workouts`,
  `weights`. Her iki şemada `other_domain` (boolean) + `other_domain_summary` (string):
  metin diğer alana aitse model kayıt üretmez, bunu işaretler.
- Ayrı sistem talimatları. İş talimatı ekip adlarını ayarlardan alır ve tekrarlayan işleri
  ("her ayın 15'i maaş ödemesi", "her pazartesi 11:00 ekip toplantısı") `routines`'e yazar.
- `other_domain` gelirse önizleme yerine uyarı: "Bu bir iş kaydı gibi görünüyor." +
  "İş girişine geç" butonu (metin taşınır). Karışık metinde bu alanın kayıtları önizlenir,
  diğer alan için aynı uyarı önizlemenin üstünde gösterilir.
- + butonu: Operasyon sekmesinde doğrudan iş girişi, Sağlık sekmesinde doğrudan sağlık
  girişi, Kokpit ve Raporlar'da iki seçenekli seçim sayfası.
- Kayıttan sonra ilgili sağlayıcılar tazelenir (rutinler, görevler, beslenme, bildirim eşitleme).

### Dilim D — Ayarlar + bildirimler  (sahip: lib/features/settings/presentation/settings_screen.dart,
lib/core/services/notification_service.dart, lib/core/services/notification_sync.dart, ilgili testler)
- Ayarlar ekranı bölümleri: **Hedefler** (başlangıç/hedef kilo, kalori, protein, karbonhidrat,
  yağ, adım, uyku), **Bildirimler** (tüm bildirimler, rutin bildirimleri, aylık iş kaç gün
  önce + saat, randevu kaç dk önce, sessiz saatler aç/kapa + başlangıç/bitiş), **Ekip**
  (isim ekle/sil), **Bağlantılar** (HealthKit durumu + yeniden bağlan, bildirim izni durumu),
  **Hesap** (e-posta, çıkış). Doğrulama veritabanı check sınırlarıyla aynı. Kaydet → başarı
  bildirimi; bildirimler yeniden eşitlenir.
- Bildirim eşitleme kuralları:
  - `notifications_enabled=false` → hiçbir şey planlanmaz (bekleyenler silinir).
  - Haftalık/günlük rutinler: `routine_notifications` ve rutinin `notify`'ı açıksa mevcut
    tekrar eden bildirimler.
  - Aylık işler: bu ay ve gelecek ay için, tamamlanmamışsa iki tek seferlik bildirim:
    `monthly_lead_days` gün önce ve gününde, `monthly_remind_time` saatinde (rutinin kendi
    saati varsa gününde o saat). Geçmiş zamanlar atlanır.
  - Tek seferlik görevler: `remind_at` varsa o; yoksa `due_at − event_remind_minutes`.
  - Sessiz saatler açıksa, sessiz aralığa düşen bildirim `quiet_end`'e ertelenir
    (aralık gece yarısını aşabilir).
  - iOS 64 sınırı: öncelik en yakın zamanlılarda; sınır aşılırsa uzaktakiler atlanır.
  - Planlama saf bir fonksiyonla hesaplanır (`buildNotificationPlan(...)` → liste) ve birim
    testlidir; eklenti çağrıları bu listeyi uygular.

### Dilim E — Operasyon sekmesi  (sahip: lib/features/operations/presentation/**, ilgili testler)
- Üstte `SegmentedButton`: **Görevler | Sabitler | Notlar**.
- Görevler: kategori filtresi (Tümü, Pusholder, Ekip, Finans, Kişisel), açık görevler
  tarihe göre, tamamla/geri al, ekle/düzenle formu (başlık, açıklama, kategori, öncelik,
  ilgili kişi [ayarlardaki ekipten], tarih, saat, hatırlatma), sil (onaylı).
- Sabitler: kapsam filtresi (Tümü, Pusholder, Kişisel); "Günlük ve haftalık" ile "Aylık"
  grupları; ekle/düzenle formu (başlık, kapsam, kategori, sıklık, günler ya da ayın günü,
  saat, bildirim), sil (onaylı).
- Notlar: kategori filtresi, liste, ekle/düzenle/sil, sabitle.
- Sekmenin kendi + butonu yoktur; ekleme her bölümün başlığındaki "Ekle" ile ya da ortadaki
  AI butonu ile yapılır.

## 3. Ortak kurallar
- Riverpod 2.x, kod üretimi yok. Depolar `SupabaseClient` alır, oturum kullanıcı id'sine
  bağlı sağlayıcılarla verilir.
- "Bugün" her yerde cihazın yerel günüdür; `date` sütunlarına `AppDates.ymd` ile yazılır.
- await sonrası `BuildContext` kullanılmaz (önce `ScaffoldMessenger`/`Navigator` yakalanır
  ya da `mounted` kontrol edilir).
- Renk ve tema `lib/core/theme/app_theme.dart`'tan; yeni renk gerekiyorsa oraya eklenir
  (yalnızca Temel dilimi bu dosyayı değiştirir; diğerleri mevcut renkleri kullanır).
- Her dilim kendi saf mantığı için birim testi, ekranı için en az bir widget testi yazar.
- `// TODO` ve yer tutucu bırakılmaz.

## 4. Temel katmanın gerçekleşen API'si

Aşağıdaki imzalar koddaki son hâldir; dilimler bunlara güvenebilir. Sözleşmeden sapmalar
**(ek)** ya da **(sapma)** olarak işaretlidir.

### Veritabanı (supabase/schema.sql, sürüm 2)
- `routines`: `scope`, `frequency`, `day_of_month` eklendi; `category` listesinde `'finans'`;
  kısıt `routines_monthly_day`: `frequency <> 'monthly' or day_of_month is not null`.
  Aylıkta `days_of_week` yok sayılır ama tablo boş listeyi kabul etmez (`{1..7}` yazılır).
- `user_settings`: bölüm 1'deki sütunlar; RLS `user_settings_owner_all`, `authenticated` GRANT, `anon` REVOKE.
- `quick_add_entries(payload)`: `routines[]` kabul eder; dönüşte `routine_count`. Aylıkta `days_of_week`
  ne gelirse `{1..7}`; haftalıkta `day_of_month` null; boş/null `days_of_week` = her gün; `notify = true`;
  `sort_order` = kullanıcının en büyük değeri + 10. Varsayılanlar: scope `Kişisel`, category `kisisel`,
  frequency `weekly`.
- Sürüm 1 → 2 (bir kez, `scope` sütunu yokken): `operasyon` rutinleri `Pusholder` olur, iki aylık örnek
  eklenir. Her kullanıcıya `user_settings` satırı açılır.

### lib/features/routines/domain/routine.dart
```dart
enum RoutineFrequency { weekly, monthly }   // .dbValue, RoutineFrequency.fromDb(Object?)
class Routine {
  const Routine({required String id, required String title, String scope = 'Kişisel',
      String category = 'kisisel', RoutineFrequency frequency = weekly,
      List<int> daysOfWeek = everyDay, int? dayOfMonth, int? hour, int? minute,
      bool notify = true, bool isActive = true, int sortOrder = 0, DateTime? createdAt});
  static const scopeWork = 'Pusholder', scopePersonal = 'Kişisel';
  static const List<String> scopes, categories;   // veritabanı check listeleri
  static const List<int> everyDay;                // [1..7]
  final DateTime? createdAt;                      // (ek) oluşturulmadan önceki dönemler sayılmaz
  bool get isMonthly; bool get isDaily; bool get hasTime; String? get timeLabel;   // "HH:mm"
  factory Routine.fromMap(Map<String, dynamic>);
  Map<String, dynamic> toInsertMap();             // insert ve update için; id/user_id içermez
  Routine copyWith({id, title, scope, category, frequency, daysOfWeek, dayOfMonth, hour, minute,
      bool clearTime = false, notify, isActive, sortOrder});
}
class RoutineCompletionKey {                      // == / hashCode: (routineId, periodKey)
  RoutineCompletionKey(String routineId, DateTime periodKey, {DateTime? completedAt});
  final DateTime? completedAt;                    // (ek) eşitliğe dahil değil
  factory RoutineCompletionKey.fromMap(Map<String, dynamic>);
}
enum OccurrenceStatus { done, dueToday, upcoming, overdue, missed }
class RoutineOccurrence {
  final Routine routine; final DateTime periodKey, dueDate; final bool completed;
  final OccurrenceStatus status;
  RoutineCompletionKey get completionKey;
  int daysUntilDue(DateTime today);               // 0 = bugün, eksi = gecikme
}
DateTime monthlyDueDate(Routine r, int year, int month);
DateTime periodKeyFor(Routine r, DateTime day);
List<RoutineOccurrence> occurrencesForDay(Iterable<Routine>, Set<RoutineCompletionKey>, DateTime day);
List<RoutineOccurrence> monthlyForDay(Iterable<Routine>, Set<RoutineCompletionKey>, DateTime today, int leadDays);
List<RoutineOccurrence> monthlyForMonth(Iterable<Routine>, Set<RoutineCompletionKey>, int year, int month, DateTime today);
({int planned, int done}) weeklyStatsForRange(Iterable<Routine>, Set<RoutineCompletionKey>, DateTime from, DateTime to);  // (ek)
```
Davranış notları:
- `occurrencesForDay`: yalnız aktif günlük/haftalık; durum `done` ya da `dueToday`; sıra saat → `sortOrder`.
- `monthlyForDay`: bu ayın ve (pencere ay sınırını aşıyorsa) gelecek ayın dönemi ayrı kalemlerdir; aynı
  rutin iki kez görünebilir (bu ayınki gecikmiş + gelecek ayınki yaklaşıyor). Tamamlanan kalem günü gelene
  kadar ve tamamlandığı gün (`completedAt`) boyunca `done` olarak kalır, sonra düşer. `missed` üretmez.
- `monthlyForMonth`: geçmiş ayda işaretsiz = `missed`; rutinin oluşturulduğu aydan önceki aylar boş.

### lib/features/routines/data/routines_repository.dart
```dart
final routinesRepositoryProvider : Provider<RoutinesRepository>
Future<List<Routine>> fetchActive();
Future<List<Routine>> fetchAll();                                        // pasifler dahil
Future<Set<RoutineCompletionKey>> fetchCompletions(DateTime from, DateTime to);  // dönem anahtarı, iki uç DAHİL
Future<void> setCompleted({required String routineId, required DateTime periodKey, required bool completed});
Future<Routine> create(Routine routine);                                 // id yok sayılır
Future<Routine> update(Routine routine);
Future<void> delete(String id);
```

### lib/features/routines/presentation/routines_providers.dart
```dart
final activeRoutinesProvider   : FutureProvider<List<Routine>>
final todayOccurrencesProvider : AsyncNotifierProvider<TodayOccurrencesNotifier, TodayOccurrences>
class TodayOccurrences { final List<RoutineOccurrence> daily, monthly; }
TodayOccurrencesNotifier.toggle(RoutineOccurrence) : Future<void>   // iyimser; hata rethrow
final monthOverviewProvider    : FutureProvider.family<MonthOverview, DateTime>   // anahtar: ayın 1'i
class MonthOverview { DateTime month; List<RoutineOccurrence> monthly; List<TaskItem> tasks;
                      int weeklyPlanned, weeklyDone; MonthHealthSummary health; int get tasksDone; }
Future<void> toggleMonthly(WidgetRef ref, RoutineOccurrence occurrence);          // hata rethrow
```
- `todayOccurrencesProvider` kendi okumasını yapar (`activeRoutinesProvider`'a bağlı değildir); rutin
  ekleyip/silince ikisini de `invalidate` edin. `monthly_lead_days` ayarını izler.
- `toggle` başarılı olunca `monthOverviewProvider`'ı, aylık işte ayrıca `notificationSyncProvider`'ı tazeler.
- `weeklyPlanned/weeklyDone` içinde bulunulan ayda bugüne kadardır; gelecek ayda 0.
- `MonthOverview.tasks`: takvim anı (`TaskItem.scheduledAt`) o aya düşenler, tamamlananlar dahil.

### lib/features/settings/**
```dart
class TimeOfDayValue implements Comparable<TimeOfDayValue> {
  const TimeOfDayValue(int hour, int minute);
  static TimeOfDayValue? tryParse(Object?);   // "HH:mm" | "HH:mm:ss"
  String format();                            // "HH:mm"
  int get minutesSinceMidnight;
}
class UserSettings {
  double startWeightKg, targetWeightKg;
  int dailyCalories, dailyProteinG, dailyCarbsG, dailyFatG, dailySteps, sleepMinutes;
  bool notificationsEnabled, routineNotifications; int monthlyLeadDays; TimeOfDayValue monthlyRemindTime;
  int eventRemindMinutes; bool quietHoursEnabled; TimeOfDayValue quietStart, quietEnd;
  List<String> teamMembers;
  const UserSettings.defaults(); factory UserSettings.fromMap(Map<String, dynamic>);
  Map<String, dynamic> toMap();               // user_id / updated_at içermez
  UserSettings copyWith({...tüm alanlar});
}
final settingsRepositoryProvider : Provider<SettingsRepository>
Future<UserSettings> fetch();                 // satır yoksa varsayılanı oluşturur
Future<UserSettings> save(UserSettings settings);
final userSettingsProvider      : AsyncNotifierProvider<UserSettingsNotifier, UserSettings>
UserSettingsNotifier.save(UserSettings) : Future<UserSettings>   // hata rethrow, eski değer korunur
final settingsOrDefaultProvider : Provider<UserSettings>         // yüklenene kadar / hatada varsayılan
class SettingsScreen extends ConsumerWidget   // iskelet: AppBar "Ayarlar" + yükleme/hata/özet
```
`UserSettingsNotifier.save` bildirimleri yeniden eşitlemez; Dilim D kayıttan sonra
`notificationSyncProvider`'ı tazeler.

### lib/features/operations/**
```dart
class TaskItem { ...mevcut alanlar; DateTime? completedAt;          // (ek)
  DateTime? get scheduledAt;                                         // (ek) dueAt ?? remindAt
  Map<String, dynamic> toWriteMap();                                 // (ek) durum hariç düzenlenebilir sütunlar
  TaskItem copyWith({title, description, category, priority, status, assignee, dueAt, remindAt, completedAt,
      clearDescription, clearAssignee, clearDueAt, clearRemindAt, clearCompletedAt}); }
class NoteItem { id, title, content, category, isPinned, createdAt, updatedAt;   // domain/note_item.dart (ek)
  fromMap; toWriteMap(); copyWith({title, content, category, isPinned}); }

final tasksRepositoryProvider : Provider<TasksRepository>
Future<List<TaskItem>> fetchOpen();                                  // done olmayanlar, termine göre
Future<List<TaskItem>> fetchInRange(DateTime from, DateTime to);     // scheduledAt ∈ [from, to), done dahil
Future<List<TaskItem>> fetchUpcoming({DateTime? from, int limit = 6});
Future<TaskItem> create({required String title, String? description, String category = 'Kişisel',
    String priority = 'medium', String? assignee, DateTime? dueAt, DateTime? remindAt});
Future<TaskItem> update(TaskItem task);                              // toWriteMap alanları; durum değişmez
Future<void> complete(String id); Future<void> reopen(String id); Future<void> delete(String id);

final notesRepositoryProvider : Provider<NotesRepository>
Future<List<NoteItem>> fetchAll({String? category});                 // sabitlenenler üstte, sonra updated_at azalan
Future<NoteItem> create({required String title, String content = '', String category = 'Kişisel', bool isPinned = false});
Future<NoteItem> update(NoteItem note); Future<void> delete(String id);
```

### lib/features/health/**
```dart
// domain/health_models.dart (health_repository.dart bu dosyayı export eder)
class DailyHealthMetric { DateTime day; int steps, activeKcal, sleepMinutes; fromMap }
class WeightEntry { String id; double weightKg; DateTime loggedAt; fromMap }
class DailyNutritionTotal { DateTime day; double calories, proteinG, carbsG, fatG; int entryCount;
  static List<DailyNutritionTotal> fromLogRows(List<Map<String, dynamic>>); }
class MonthHealthSummary { int? avgSteps, avgSleepMinutes; double? avgCalories, avgProteinG,
  weightStartKg, weightEndKg; int daysWithData; double? get weightChangeKg;
  factory MonthHealthSummary.from({required metrics, required nutrition, required weights}); }

final healthRepositoryProvider : Provider<HealthRepository>
Future<List<DailyHealthMetric>> fetchDailyMetrics(DateTime from, DateTime to);       // yerel gün, iki uç DAHİL
Future<List<WeightEntry>> fetchWeights(DateTime from, DateTime to);                  // [from, to)
Future<List<DailyNutritionTotal>> fetchNutritionTotals(DateTime from, DateTime to);  // [from, to), yerel güne göre
Future<void> upsertHealthMetrics(DateTime day, HealthSnapshot snapshot);
```

### Kokpit ve çekirdek
- `lib/core/services/notification_sync.dart`: `notificationSyncProvider : FutureProvider<void>` (davranış
  eskisiyle aynı; aylık rutinler haftalık tekrar olarak planlanmaz).
- `lib/features/kokpit/presentation/kokpit_providers.dart`: `kokpitClockProvider`, `upcomingRemindersProvider`
  (`tasksRepositoryProvider.fetchUpcoming()`), `todayNutritionProvider`, `healthTodayProvider`
  (`healthRepositoryProvider.upsertHealthMetrics`). `todayRoutinesProvider` ve `RoutineItem` kaldırıldı.
- `KokpitRepository` yalnızca `fetchNutritionFor(DateTime day)` içerir; `NutritionSummary` kokpit_models'te kaldı.
- `AppTargets`: yalnızca `taskCategories`, `noteCategories`. `teamMembers` ayarlara taşındı.
- `GeminiParserService(..., UserSettings settings = const UserSettings.defaults())` **(ek)**: hedefler ve ekip
  adları talimata buradan girer; `geminiParserServiceProvider` `settingsOrDefaultProvider`'ı izler.
- `AppColors.forRoutineCategory('finans')` → `AppColors.warning`.
- `MaterialApp`: `locale: Locale('tr', 'TR')`, `GlobalMaterialLocalizations.delegates`.

### Test sahteleri (test/helpers/fakes.dart)
Hepsi bellekte durum tutar; yazmalar sonraki okumalara yansır.
- `FakeRoutinesRepository({routines, completions})`: `routines`, `completions`, `fetchError`, `writeError`,
  `toggleGate` (Completer; hata ile tamamlanırsa `setCompleted` hata verir), `toggles`
  (`({routineId, periodKey, completed})`), `fetchActiveCount`.
- `FakeTasksRepository({tasks})`: `tasks`, `fetchError`, `writeError`, `completedIds`, `reopenedIds`, `deletedIds`.
- `FakeNotesRepository({notes})`: `notes`, `fetchError`, `writeError`, `deletedIds`.
- `FakeHealthRepository({metrics, weights, nutrition})`: `fetchError`, `upsertError`, `upsertedHealth`.
- `FakeSettingsRepository({settings})`: `settings`, `fetchError`, `saveError`, `saveGate`, `saved`, `fetchCount`.
- `FakeKokpitRepository({nutrition, error})`; `FakeNotificationService({permissionGranted})` artık
  `lastRoutines` / `lastReminders` da tutar.

Widget testinde tipik override listesi: `routinesRepositoryProvider`, `tasksRepositoryProvider`,
`kokpitRepositoryProvider`, `healthRepositoryProvider`, `settingsRepositoryProvider`, `healthServiceProvider`
(ve gerekiyorsa `notificationServiceProvider`).

Not: Riverpod'da süren bir `build` sırasında `state` atanırsa `provider.future` o değerle tamamlanır;
testlerde kesin sonucu görmek için `pumpEventQueue()` / `pumpAndSettle()` sonrası `container.read(provider)` okuyun.

## 5. Tasarım dili (kullanıcı kararı — tüm dilimler için bağlayıcı)
- Saf OLED siyah zemin (`AppColors.background` = #000000); açık tema yok.
- Kartlar Bento Grid: `lib/core/widgets/bento.dart` → `BentoGrid(children: [BentoCell(span: 1|2, child: BentoCard(...))])`.
  Ekranlardaki kartlar elle `Container` yerine `BentoCard` ile kurulur; yarım genişlikte iki kart
  yan yana (span 1 + span 1), tam genişlik kart span 2.
- Alt bar: `lib/core/widgets/app_bottom_bar.dart` → `AppBottomBar(currentIndex, onSelect, onCreate)`;
  etiketsiz 5 slot (Kokpit, Operasyon, +, Sağlık, Raporlar). `home_shell.dart` bunu kullanır;
  FloatingActionButton ve BottomAppBar kullanılmaz. Dilim C + yönlendirmesini `onCreate` içinde yapar.
- Yarıçap/boşluk: `AppRadii`, `AppSpacing`. Bileşenlerde ham hex yok.
- Hız kuralı: dosya başına analyze/test çalıştırılmaz; dilim sonunda tek seferlik kontrol yapılır.
