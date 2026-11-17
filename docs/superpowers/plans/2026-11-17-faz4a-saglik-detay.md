# Faz 4A — Sağlık derinleştirme ve düzenleme Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trend ekranları (adım, uyku, kalori), paketli besin listesi, Sağlık sekmesinde enerji dengesi ve her listede düzenle/sil.

**Architecture:** Hesaplar saf Dart sınıflarında (`GoalRules`, `TrendStats`, `EnergyBalance`), ekranlar bunları Riverpod sağlayıcılarıyla çağırır. Veri okuma mevcut `HealthRepository.fetchDailyMetrics` ve `fetchNutritionTotals` ile yapılır; yeni sunucu tablosu yok. Besin listesi pakete gömülü JSON'dur. Tek şema değişikliği `user_settings` profil sütunlarıdır.

**Tech Stack:** Flutter, Riverpod 2 (kod üretimi yok), `fl_chart`, Supabase (yalnızca profil sütunları), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-17-faz4a-saglik-detay-design.md` (Netleştirmeler bölümü dahil; çelişirse o geçerli).

## Global Constraints
- `CLAUDE.md`: renkler yalnızca `AppColors` getter'ları (asla `const` içinde), ham `Colors.*`/`Color(0x…)` yok, Bento (`BentoGrid`/`BentoCard`), alt bar 5 slot (yeni sekme yok), UI metni Türkçe, `// TODO` yok, hız kuralı (dosya başına analyze/test yok; görev sonunda bir kez).
- Eşikler tek yerde (`GoalRules`): kalori hedefin %85–%110'u (uçlar dahil); protein ≥ %90; adım ≥ %100; uyku ≥ hedefin %90'ı.
- Verisiz gün paydada yok; bugün "devam ediyor" (hedefi tutturduysa tutan gün, yoksa paydada değil); verisiz gün seriyi bozmaz, veri olup tutturulmayan gün bozar; "mevcut seri" yalnızca geçerli dönemde.
- Denge: bazal Mifflin-St Jeor (erkek +5, kadın −161, `unspecified` −78); yakılan = bazal + aktif kalori; bantlar net ≤ −1000 / −1000…−150 / ±150 / +150…+500 / ≥ +500; yağ tahmini Σnet ÷ 7700; 18 yaş altına yorum yok; yalnızca öğünü olan günler yorum üretir.
- `schema.sql` tek, idempotent betik; RLS ve yetkiler korunur. Mevcut 788 test geçmeye devam eder; web demo derlenir.

## Review Focus
1. Veri hiç yokken (boş hafta/ay, öğünsüz gün) ekranlarda NaN, 0/0 yüzde ya da sahte övgü yok; boş durum metni var.
2. Hafta Pazartesi başlar; ay 28/29/30/31 gün; gelecek günler çubukta boş ve hesaba girmez.
3. Gün değişimi: uygulama gece yarısını geçip öne gelince bugün/dün ve bazal oranı doğru yeniden hesaplanır.
4. Besin arama Türkçe karakterden bağımsız ("SUT"→Süt, "İnek", "yumurta"); gram alanı virgüllü ("150,5"), boş, 0 ve negatif değerde form bozulmaz.
5. Kokpit'ten rutin ya da görev silince bildirim planı ve ilgili sağlayıcılar tazelenir (Operasyon'daki mevcut silme yolu aynen kullanılır).
Her satırın testi ilgili görevde yazılıdır. Yeni ekranlar 375×667 ve metin ölçeği 1,3'te taşmaz.

## Dosya yapısı
- Yeni: `lib/features/health/domain/{goal_rules,trend_stats,energy_balance,food_item}.dart`, `lib/features/health/data/food_catalog.dart`, `lib/features/health/presentation/{trend_providers,trend_screen,trend_chart,energy_providers,energy_card,energy_detail_screen}.dart`, `lib/core/widgets/item_actions.dart`, `assets/data/foods_tr.json`, `test/{goal_rules,trend_stats,energy_balance,food_catalog,foods_data}_test.dart`, `test/widget/{trend_screen,energy_card,item_actions,profile_settings}_test.dart`, `supabase/tests/profile_columns_test.sql`.
- Değişen: `lib/features/settings/domain/user_settings.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/health/presentation/{health_screen,activity_cards,meal_form_sheet,meals_section,workouts_section}.dart`, `lib/features/kokpit/presentation/{kokpit_day_view,kokpit_month_view}.dart`, `lib/features/operations/presentation/{tasks_view,routines_view,notes_view}.dart`, `supabase/schema.sql`, `supabase/tests/run_local.sh`, `pubspec.yaml` (assets), `lib/demo/**`, `README.md`, `docs/KARARLAR.md`.

## Sıra (bağımlılık dalgaları; aynı dalgadaki görevler paralel çalışabilir)
Dalga 1: Görev 1, 2, 4, 9. Dalga 2: Görev 3 (2'ye), 5 (4'e), 6 (1'e), 8 (1'e). Dalga 3: Görev 7 (3 ve 6'ya). Dalga 4: Görev 10.
Paylaşılan dosya sahipliği: `schema.sql` yalnızca Görev 1; `health_screen.dart` sırayla Görev 3 sonra 7; `pubspec.yaml` yalnızca Görev 4; `settings_screen.dart` yalnızca Görev 8; `lib/demo/**` yalnızca Görev 10 (diğer görevler testlerinde kendi sahte verisini kurar).

---

### Task 1: Profil sütunları ve `UserSettings`
**Files:** Modify `supabase/schema.sql`, `supabase/tests/run_local.sh`, `lib/features/settings/domain/user_settings.dart`; Create `supabase/tests/profile_columns_test.sql`; Test `test/user_settings_test.dart` (mevcut dosya varsa genişlet).
**Interfaces:** Produces `UserSettings.heightCm: int?`, `birthYear: int?`, `sex: String?` (`'female'|'male'|'unspecified'|null`), `copyWith` ve `toMap/fromMap` anahtarları `height_cm`, `birth_year`, `sex`; `bool get profileComplete` (üçü de dolu). Tanınmayan `sex` ve aralık dışı değer `fromMap`'te `null` olur.
- [ ] Test (önce kırmızı): `fromMap` → `toMap` gidiş-dönüş; `sex: 'x'` → `null`; `height_cm: 99` → `null`; `profileComplete` yalnızca üçü doluyken true; `copyWith(sex: 'male')`.
- [ ] SQL: `alter table public.user_settings add column if not exists` ile `height_cm smallint check (height_cm between 100 and 250)`, `birth_year smallint check (birth_year between 1900 and 2100)`, `sex text check (sex in ('female','male','unspecified'))`. Sütun yetkilerini (grant) kontrol et; gerekiyorsa yeni sütunlara ekle. `profile_columns_test.sql`: betik iki kez çalışır; `height_cm = 99` ve `sex = 'x'` reddedilir; v2 ve v3 şemasından yükseltmede mevcut satır korunur; `run_local.sh` bu testi çağırır.
- [ ] Doğrula: `supabase/tests/run_local.sh` ("TÜM ŞEMA TESTLERİ GEÇTİ") ve ilgili Dart testi.
- [ ] Commit.

### Task 2: `GoalRules` ve `TrendStats` (saf Dart)
**Files:** Create `lib/features/health/domain/goal_rules.dart`, `lib/features/health/domain/trend_stats.dart`, `test/goal_rules_test.dart`, `test/trend_stats_test.dart`.
**Interfaces:** Produces
`enum TrendMetric { steps, sleep, calories }`;
`class GoalRules { static bool stepsHit(int steps, int target); static bool sleepHit(int minutes, int target); static bool caloriesHit(double kcal, int target); static bool proteinHit(double grams, int target); }`;
`enum DayStatus { hit, miss, noData, inProgress, future }`;
`class TrendDay { final DateTime day; final double? value; final DayStatus status; }`;
`class TrendStats { final List<TrendDay> days; final int hitDays; final int dataDays; final double? percent; final double? average; final int longestStreak; final int? currentStreak; static TrendStats build({required List<DateTime> days, required Map<DateTime, double> values, required bool Function(double) hit, required DateTime today, required bool isCurrentPeriod}); }` (`values` yalnızca verisi olan günleri içerir; `percent` = hitDays/dataDays ya da `null`; `average` bugün "devam ediyor"sa onu içermez).
- [ ] Test (önce kırmızı): `stepsHit(10000,10000)` true, `(9999,10000)` false; `sleepHit(405,450)` true, `(404,450)` false; `caloriesHit(1700,2000)` true, `1699` false, `2200` true, `2201` false; `proteinHit(153,170)` true, `152` false.
- [ ] Test `build`: Pzt–Paz, bugün Per, hedef 10000, `values = {Pzt:12000, Sal:8000, Per:10500}` → Pzt hit, Sal miss, Çar noData, Per hit, Cum–Paz future; `hitDays 2`, `dataDays 3`, `percent 2/3`, `average ≈ 10166.67`, `currentStreak 1`, `longestStreak 1`. Bugün 4000 → Per inProgress, `hitDays 1`, `dataDays 2`, `average 10000`, `currentStreak 0`. `[hit, noData, hit]` → `longestStreak 2`. `isCurrentPeriod: false` → `currentStreak == null`. Hiç veri yok → `percent == null`, `average == null`, `dataDays 0`.
- [ ] Uygula; doğrula; commit.

### Task 3: Trend sağlayıcıları ve ekranı
**Files:** Create `lib/features/health/presentation/{trend_providers,trend_screen,trend_chart}.dart`, `test/widget/trend_screen_test.dart`; Modify `health_screen.dart`, `activity_cards.dart` (Adım kartı dokununca trend; yeni `SleepWeekCard`, `CaloriesWeekCard`).
**Interfaces:** Consumes Görev 2. Produces `enum TrendPeriod { week, month }`; `class TrendQuery { final TrendMetric metric; final TrendPeriod period; final DateTime anchor; }` (değer eşitliği); `final trendStatsProvider = FutureProvider.family<TrendStats, TrendQuery>`; `class TrendScreen extends ConsumerStatefulWidget { const TrendScreen({super.key, this.initialMetric = TrendMetric.steps}); }`; `class TrendBarChart extends StatelessWidget` (`stats`, `target`, `metric` alır; Görev 7 de bunu çağırır).
- [ ] Test: hafta penceresi Pazartesi–Pazar, ay penceresi 1–son gün (28/29/30/31); "sonraki" oku geçerli dönemdeyken pasif; Per bugün ve sahte veriyle ekranda `2/3` ve yüzde görünür; veri yokken boş durum metni ("Bu dönemde veri yok"); kalori sekmesinde protein tutturulan gün satırı; 375×667, metin ölçeği 1,3'te taşma yok.
- [ ] Uygula: veri `fetchDailyMetrics` (adım, uyku; değer > 0 = veri var) ve `fetchNutritionTotals` (kalori/protein; `entryCount > 0` = veri var); hedefler `userSettingsProvider`'dan. Çubuk grafik `fl_chart`: hedef çizgisi, tutan gün vurgulu, tutmayan soluk, verisiz/gelecek boş; renkler `AppColors`. Sağlık sekmesine Uyku ve Kalori kartları (Bento) eklenir.
- [ ] Doğrula; commit.

### Task 4: Besin verisi (`foods_tr.json`)
**Files:** Create `assets/data/foods_tr.json`, `test/foods_data_test.dart`; Modify `pubspec.yaml` (`flutter: assets: - assets/data/`).
**Interfaces:** Produces JSON dizisi; öğe alanları: `id` (benzersiz, ascii), `name`, `aliases` (liste), `category` (`yumurta-süt|et-balık|tahıl-ekmek|sebze|meyve|baklagil|kuruyemiş-yağ|içecek|diğer`), `kcal100`, `protein100`, `carbs100`, `fat100` (sayı), `portions` (`[{name, grams}]`), `source` (`"USDA FDC <kimlik> | TürKomp <kod>"`), `verification` (`"iki kaynak"|"tek kaynak"`).
- [ ] Veriyi topla: USDA FoodData Central (API/yayımlı veri; ağ izin verdiği ölçüde) ve TürKomp. İki kaynakta uyuşan → `iki kaynak`; tek kaynakta olup yaygın yayımlanmış değerle ±%5 uyuşan → `tek kaynak`; kalanı ekleme. Çiğ/pişmiş ayrı satır. Hedef ≈100–150 satır, doldurma yok. Kapsam: yumurta (bütün, haşlanmış), tam buğday ve beyaz ekmek, yulaf, pirinç, bulgur, makarna, patates, tavuk göğsü, dana kıyma, ton balığı, somon, süt, yoğurt, lor, beyaz peynir, mercimek, nohut, kuru fasulye, zeytinyağı, tereyağı, fındık/ceviz/badem, muz, elma, portakal, domates, salatalık, havuç, vb.
- [ ] Test (önce kırmızı): dosya geçerli JSON; `id` benzersiz; sayılar ≥ 0 ve `kcal100 ≤ 900`; `category` ve `verification` izinli kümede; `source` boş değil; en az 60 satır; Atwater: `|kcal − (4·protein + 4·carbs + 9·fat)| ≤ max(0,15·kcal, 10)` (mutlak taban lifli gıdalar için).
- [ ] Doğrula; commit (kaynak özeti commit mesajında).

### Task 5: `FoodCatalog` ve öğün formu
**Files:** Create `lib/features/health/domain/food_item.dart`, `lib/features/health/data/food_catalog.dart`, `test/food_catalog_test.dart`; Modify `meal_form_sheet.dart`, `test/widget/health_screen_test.dart` ya da yeni form testi.
**Interfaces:** Consumes Görev 4 JSON. Produces `class FoodPortion { final String name; final double grams; }`; `class FoodMacros { final double kcal, protein, carbs, fat; }`; `class FoodItem { …alanlar JSON ile aynı…; FoodMacros forGrams(double grams); }`; `class FoodCatalog { static Future<FoodCatalog> load(AssetBundle bundle); factory FoodCatalog.fromItems(List<FoodItem>); List<FoodItem> search(String query, {int limit = 8}); }`; `final foodCatalogProvider = FutureProvider<FoodCatalog>`.
- [ ] Test: `forGrams(150)` 143 kcal/100 g için 214,5; arama normalleştirir (küçük harf Türkçe-uyumlu, `ç→c ğ→g ı→i ö→o ş→s ü→u`): "SUT" → "Süt", "yumurta" ilk sonuç yumurta, "İnek" büyük/küçük `İ/ı` duyarsız; sıralama: ad öneki, ad içinde geçen, takma ad; boş sorgu boş liste.
- [ ] Form: "Besin ara" alanı → sonuç listesi; seçince gram alanı (varsayılan 100) ve porsiyon çipleri; kcal/makrolar forma dolar ve elle düzenlenebilir; `quantity_text` "2 adet · 100 g"; kayıt `source` değişmez ('manual'). Gram alanı virgül kabul eder; boş/0/negatif gramda hesap uygulanmaz ve hata metni çıkar. Testler: arama→seçim→alanlar dolu; "150,5" kabul; "-5" ve "0" reddedilir; elle giriş akışı bozulmaz.
- [ ] Doğrula; commit.

### Task 6: `EnergyBalance` (saf Dart)
**Files:** Create `lib/features/health/domain/energy_balance.dart`, `test/energy_balance_test.dart`.
**Interfaces:** Produces `enum Sex { female, male, unspecified }`; `double basalKcal({required double weightKg, required int heightCm, required int age, required Sex sex})`; `enum EnergyVerdict { veryHighDeficit, burning, steady, slightOver, over, noMeals, underAge }`; `class EnergyDay { final DateTime day; final double? intake; final double basal; final double active; final bool activeDataMissing; final double? net; final EnergyVerdict verdict; final bool isToday; final int? walkingMinutesToCompensate; final double? tomorrowCutKcal; }`; `EnergyDay computeEnergyDay({required DateTime day, required DateTime now, required double weightKg, required int heightCm, required int birthYear, required Sex sex, required int mealEntryCount, required double intakeKcal, int? activeKcalFromMetrics, int workoutKcal = 0})`; `class EnergyRangeSummary { final int days; final double sumNet; final double estimatedFatKg; }` + `EnergyRangeSummary summarize(Iterable<EnergyDay> days)` (yalnızca `net != null` günler).
- [ ] Test: `basalKcal(80,180,30,male)=1780`, `female=1614`, `unspecified=1697`; bant sınırları: net −1000 `veryHighDeficit`, −999 `burning`, −150 `burning`, −149 `steady`, 149 `steady`, 150 `slightOver`, 499 `slightOver`, 500 `over`; `mealEntryCount 0` → `noMeals`, `net == null`; yaş 17 → `underAge`, sayılar dolu; `activeKcalFromMetrics == null` ve `workoutKcal 300` → yakılan = bazal + 300, `activeDataMissing true`; bugün saat 12:00 → bazal 1780×0,5 = 890; telafi: net +300, 80 kg → `walkingMinutesToCompensate == 62` (kcal/dk = 3,5 MET×3,5×kg÷200 = 4,9), `tomorrowCutKcal == 300`; `summarize` net [−500, +200, null] → `days 2`, `sumNet −300`, `estimatedFatKg ≈ −0,039`.
- [ ] Uygula; doğrula; commit.

### Task 7: Enerji sağlayıcıları, kart ve detay
**Files:** Create `lib/features/health/presentation/{energy_providers,energy_card,energy_detail_screen}.dart`, `test/widget/energy_card_test.dart`; Modify `health_screen.dart` (Kilo kartının altına `EnergyCard`).
**Interfaces:** Consumes Görev 1 (`profileComplete`), 3 (`TrendBarChart` kalıbı, sağlayıcı örnekleri), 6. Produces `final energyDayProvider = FutureProvider.family<EnergyDay?, DateTime>` (profil eksikse `null`); `final energyRangeProvider = FutureProvider.family<List<EnergyDay>, ({DateTime from, DateTime to})>`; `class EnergyCard extends ConsumerWidget`; `class EnergyDetailScreen extends ConsumerStatefulWidget`.
- [ ] Test (tam metinler): `burning` "Bugün yağ yaktın"; `steady` "Bugün yerinde saydın, yağ almadın"; `slightOver` "Bugün biraz kaçırdın, telafi edebilirsin" + telafi satırı; `over` "Bugün fazla geçti; bir günle bozulmaz, yarın toparla"; `veryHighDeficit` "Çok yüksek kalori açığı: yeterince yediğinden emin ol" (övgü yok); `noMeals` "Henüz öğün girilmedi"; `activeDataMissing` notu "aktif kalori verisi yok, tahmin bazala dayanıyor"; bugün için "Şu ana kadar" öneki; profil eksik → "Dengeyi hesaplamak için boy, yaş ve cinsiyet gerekli" ve Ayarlar'a götüren düğme; 375×667 ve ölçek 1,3'te taşma yok.
- [ ] Uygula: ağırlık = son tartı (≤ gün), yoksa `startWeightKg`; antrenman yedeği `WorkoutLog.caloriesBurned` toplamı. Detay: günlük net çubuk (sıfır çizgisi; açık mint aşağı, fazla amber yukarı), "Alınan / Yakılan" çizgi anahtarı, hafta/ay özeti "N gün üzerinden" ve tahmini yağ değişimi. Gün değişimi: `AppLifecycle` öne gelişte sağlayıcılar tazelenir (mevcut `invalidateHealthData`'ya eklenir).
- [ ] Doğrula; commit.

### Task 8: Ayarlar > Profil
**Files:** Modify `lib/features/settings/presentation/settings_screen.dart`; Test `test/widget/profile_settings_test.dart`.
**Interfaces:** Consumes Görev 1. Produces "Profil" bölümü: boy (cm), doğum yılı, cinsiyet (Kadın / Erkek / Belirtmek istemiyorum).
- [ ] Test: 180, 1990, Erkek girilip kaydedilince `FakeSettingsRepository`'ye `height_cm 180`, `birth_year 1990`, `sex male` gider; boy 99 ya da doğum yılı bu yıl−10'dan büyük → hata metni, kayıt yok; boş bırakmak `null` bırakır.
- [ ] Uygula (mevcut Hedefler bölümünün kalıbıyla, `AppColors`/Bento); doğrula; commit.

### Task 9: Düzenle / sil her yerde
**Files:** Create `lib/core/widgets/item_actions.dart`, `test/widget/item_actions_test.dart`; Modify `kokpit_day_view.dart`, `kokpit_month_view.dart`, `tasks_view.dart`, `routines_view.dart`, `notes_view.dart`, `meals_section.dart`, `workouts_section.dart`.
**Interfaces:** Produces `class ItemActions extends StatelessWidget { const ItemActions({super.key, required this.title, required this.onEdit, required this.onDelete, required this.child}); }` (uzun basışta "Düzenle / Sil" alt sayfası); `class SwipeToDelete extends StatelessWidget { const SwipeToDelete({super.key, required this.itemKey, required this.confirmTitle, required this.confirmMessage, required this.onDelete, required this.child}); }` (sola kaydırma, mevcut `confirmDelete` onayı; "Vazgeç"te satır geri gelir).
- [ ] Test: uzun basış → alt sayfada "Düzenle" ve "Sil"; Sil → onay → `onDelete` bir kez; Vazgeç → çağrılmaz; sola kaydırma aynı akış; Kokpit rutin satırında uzun basış menüsü açılır, kısa dokunuş hâlâ tamamlar.
- [ ] Bağla: mevcut silme ve düzenleme yolları aynen kullanılır (Operasyon'daki `_delete`/`_openForm` mantığı bildirim planını ve sağlayıcıları tazeler); Kokpit satırları (rutin, aylık, hatırlatma) ve ay günü listesi, Operasyon listeleri (üç nokta menüsü kalır), öğün ve antrenman satırları. Rutin silince tamamlama geçmişi gider (mevcut cascade).
- [ ] Test (Review Focus 5): Kokpit'ten rutin silince `FakeNotificationService` yeniden planlama çağrısı alır ve Kokpit sağlayıcısı tazelenir.
- [ ] Doğrula; commit.

### Task 10: Demo, dokümantasyon, nihai kontroller
**Files:** Modify `lib/demo/**` (60 günlük sahte adım/uyku/kalori/öğün verisi, profil dolu demo ayarı), `README.md` ("Trendler ve enerji dengesi" bölümü: eşikler, yorum bantları, sınırlar, "tahmini"), `docs/KARARLAR.md` (Faz 4A kararları), `CLAUDE.md` yalnızca gerekirse (dokunma).
- [ ] Web demoda Trend ekranı, Enerji kartı ve besin arama sahte veriyle çalışır (`flutter create --platforms=web` ve `flutter build web -t lib/main_demo.dart --release --no-web-resources-cdn --no-wasm-dry-run` kopyada; repoya `web/` eklenmez).
- [ ] Tek seferlik: `flutter analyze --no-fatal-infos` (0 hata, 0 uyarı), `flutter test` (tümü geçer), `supabase/tests/run_local.sh`, `node --test` (Edge Function), `tool/test/configure_ios_test.sh`.
- [ ] Commit; dalı gönder.

## Self-review
- Kapsam: spec §1→G2,G3; §2→G4,G5; §3→G1,G6,G7,G8; §4→G9; Netleştirmeler→G2/G6 testlerinde; Review Focus→G3,G5,G7,G9.
- Tutarlılık: `TrendBarChart` (G3) G7'de aynı adla; `Sex`/`sex` metni `'female'|'male'|'unspecified'` her yerde aynı; `GoalRules` yalnızca G2'de tanımlı.
- Oran: plan, spec'in ~2,2 katı; gövdeler yok, imza ve sabit değerler var.
