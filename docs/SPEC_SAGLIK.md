# Sağlık: final spec (decided)

## 0. Decisions that settle the open debates
- **Segments:** 3 segments, **Bugün · Vücut · Plan**. Bugün is the default. A single long page was rejected because it gets too long once body tracking is added. The Hareket segment goes away.
- **No streak freeze ("dondurma").** It hides state and makes the rule unclear. Today never breaks a streak before midnight, and that is the only grace rule.
- **One check-in schedule:** "Ölçü ve fotoğraf günü" is one cadence for both tape measure and photos. It is Haftalık (weekday) or Aylık (day of month). The default is Haftalık · Pazartesi. Two separate schedules add settings and give no clear benefit.
- **Rates:** Yavaş 0,25 · Dengeli 0,5 (default) · Hızlı 0,75 kg/hafta. Remove "Klasik (kg×26)" and the 1 kg option entirely, including the BMI exception.
- **No slider overlay for photos.** Side by side only. No 12-week heatmap; use a 30-day dot calendar.
- Tasks/İşler never use the word "açık". Use "Bekleyen" there.

## 1. Sağlık tab structure
Header: segmented control `Bugün | Vücut | Plan` (`healthSegmentProvider`, enum renamed to `today/body/plan`). Every scroll view ends with 120 bottom padding. All cards are `BentoCard`.

### Bugün (top to bottom)
1. **Seriler şeridi** (full width, 4 chips):
   - "Adım 7 gün", "Kayıt 12 gün", "Açık 4 gün" and "Hafta −2.850 kcal ≈ 0,37 kg".
   - Each chip has an icon plus a text label. VoiceOver reads "Adım serisi 7 gün".
   - The Hafta chip has a sub-line "hedef 3.500".
   - Today's state per chip: ✓ (done), or a grey dot "bugün bekleniyor".
   - Tap opens **SeriDetayScreen**.
   - The Adım chip is hidden when no health source is connected.
2. **Günün dengesi** (full width; replaces `NutritionDayCard` + `EnergyNetCard`):
   - A kcal ring shows Alınan / Hedef / Kalan. The number is shown, not only the color.
   - Protein bar "92 / 140 g".
   - Line "Kalori açığı (şu ana kadar): −420 kcal", with the footnote "Gün bitmeden kesinleşmez".
   - One gap line, at most 2 items, computed against `user_settings`, e.g. "Protein 48 g eksik". It is hidden when nothing is logged.
   - Water row: dots plus +/−, from the shared `WaterTracker`.
   - Tap opens **HaftalıkDetayScreen** on the kcal metric.
3. **Öğünler:** the existing `MealsSection`. One "+ Öğün ekle" button opens the same sheet with search, AI and recent foods.
4. **Hareket 2×2:**
   - Adım (steps / target bar)
   - Uyku (last night)
   - Antrenman (this week count + "Ekle")
   - Su haftası is not a tile; water lives in card 2.

   So the grid is 3 tiles plus a "Haftalık detay" tile. Each tile opens **HaftalıkDetayScreen** with its metric preselected.
5. **Bu hafta** (full width):
   - A 7-bar chart of daily actual deficit, Mon–Sun. Today's bar is hatched.
   - Total "−2.850 / hedef 3.500 kcal ≈ 0,37 kg".
   - Averages for steps and sleep.
   - Tap opens HaftalıkDetayScreen.

### Vücut
1. **Kontrol günü banner:** shown only on the scheduled day, and until it is completed or dismissed. Text: "Bugün ölçü ve fotoğraf günü · 3 adım, ~3 dk". The button "Başla" opens **KontrolAkışı**. Off-day, a slim row shows "Sonraki ölçü günü: Pazartesi · 3 gün kaldı".
2. **Kilo:**
   - Last weight and Δ over 7 days.
   - A 30-day sparkline.
   - "Hedefe ~9 hafta", from one ETA function.
   - "+ Tartıl" opens the shared `weight_sheets`.
   - Tap opens **KiloDetayScreen**.
3. **Ölçüler:**
   - One row per field: Bel, Kalça, Göğüs, Kol, Uyluk, Boyun.
   - Each row shows the last value, Δ from the first entry, and Δ from the previous entry, e.g. "Bel 88 cm · −4 başlangıçtan · −0,5 geçen".
   - "+ Ölç" opens the measurement form.
   - Tap opens **ÖlçülerScreen**.
   - Empty state: "Henüz ölçüm yok." + [İlk ölçümü ekle].
4. **Fotoğraflar:**
   - Last check-in's thumbnails (ön/yan/arka), blurred if "Fotoğrafları gizle" is on.
   - "Karşılaştır" opens **FotoğraflarScreen** in compare mode.
   - Empty state: "Henüz fotoğraf yok." + [İlk fotoğrafı çek].

### Plan
1. **Hedefim:**
   - "85,2 → 75 kg · Dengeli (0,5 kg/hafta)".
   - Source badge: "Otomatik (kiloya göre) · 21 Kas" or "Elle ayarlandı".
2. **Günlük hedeflerin:** kcal, P/K/Y, steps and sleep, read-only from `user_settings`. One "Hedef açık: 500 kcal/gün" line. If clamped: "Hızın güvenli sınıra indirildi".
3. **Tempo:** 3 radio options (Yavaş/Dengeli/Hızlı), each with its resulting kcal shown. Changing it calls `applyPlan()`.
4. **Neden bu sayılar?** (collapsible): 3 sentences covering expenditure, deficit and protein.
5. **Rehber** (collapsible, closed by default): Besin karşılıkları, Örnek menü, Takviyeler.
6. **Ölçü ve fotoğraf günü:** Haftalık/Aylık, weekday or day of month, and reminder on/off.
7. **Hedefleri elle ayarla** (link): opens Ayarlar > Hedeflerim.

Under-18 users, or users whose current or target BMI is below 18,5, see the following:
- Plan shows "Kilo verme planı sana uygun değil, dengeli beslenme hedefleri gösteriliyor".
- Tempo is hidden.
- Targets use maintenance kcal.

## 2. Detail screens & navigation map (one destination per thing)
| Screen | Reached from |
|---|---|
| SeriDetayScreen (3 streaks: current/best, 30-day dot calendar, rule text, weekly deficit history 8 wk) | Bugün streak strip, Kokpit streak row, İçgörü week streak line |
| HaftalıkDetayScreen (merge of `EnergyDetailScreen`+`TrendScreen`; metric chips kcal/açık/protein/adım/uyku/antrenman; 7/30/90 range; "Çok yüksek açık" warning) | Günün dengesi, Hareket tiles, Bu hafta, Kokpit Sağlık card long-press, İçgörü week details |
| KiloDetayScreen (existing `WeightDetailScreen`) | Vücut Kilo card, Kokpit weight quick action → sheet then here |
| ÖlçülerScreen (table + per-field line chart, 4/12/Tümü chips) | Vücut Ölçüler, KontrolAkışı finish |
| FotoğraflarScreen (week grid + Karşılaştır) | Vücut Fotoğraflar, KontrolAkışı finish |
| KontrolAkışı (tartı → mezura → fotoğraf; each step "Atla") | Vücut banner, Kokpit today item, reminder notification |
| Plan segment | Kokpit Sağlık card "Hedef" chip, Ayarlar > Hedeflerim "Plan'ı gör" |

The weight sheet, meal sheet, measurement form and photo capture are each **one widget**, reused everywhere. Deep links use `HealthRoute(segment, detail?)`, so Kokpit, notifications and İçgörü all call the same function.

## 3. Single source of truth
- **Targets: `user_settings` only.**
  - `resolveTargets(settings, latestWeight, age, sex)` is a pure function. It returns kcal, P/C/F, `deficit`, `clamped` and `mode`.
  - `applyPlan()` is the **only writer** of `daily_calories/protein/carbs/fat`. It also stamps `targets_source` and `targets_updated_at`.
  - Callers:
    - Onboarding: always.
    - Weight save: when `targets_source='plan'` and |Δkcal| > 50 or |Δprotein| > 5 g. Show a snackbar "Hedefin güncellendi: 1.880 → 1.850 kcal".
    - Tempo change: always.
    - Ayarlar > Hedeflerim manual save: writes the values and sets `targets_source='manual'`.
  - With `targets_source='manual'`, a new weight only shows a suggestion row in Plan: "Kilona göre önerilen 1.820 kcal [Uygula]". Applying it sets `targets_source='plan'`.
  - Remove "Hedeflerimi buna göre ayarla".
  - Kokpit, Bugün, reports, Trend and Gemini read `targetsProvider` (a wrapper over `settingsOrDefaultProvider`).
- **Weight:**
  - `latestWeightProvider` and `weightSeriesProvider` are the only weight providers. `fatLossWeightProvider` is deleted.
  - There is one ETA function, `weightEta(series)`: 14-day linear trend, used by the Kilo card, KiloDetay and Plan.
  - `actualKgPerWeek` is derived from the same function.
- **Expenditure (one model, in `energy_balance.dart`)**, used by the day net, the weekly deficit and the engine:
  - Use `expenditure_kcal_manual` if it is set.
  - Else use HealthKit basal + active if available.
  - Else use Mifflin BMR × 1,2 + steps × 0,04.
  - Today's basal is prorated to "now".
  - `resolveExpenditure` in the plan is deleted and replaced by this.
- **Deficit:** `Kalori açığı(day) = expenditure − intake`. A positive value means a deficit; the UI shows it as "−X kcal".
- **Weekly deficit:** the Mon–Sun sum of closed days plus today "şu ana kadar". Target is `weekly_rate_kg × 7700`. kg ≈ sum / 7700. Provided by `weekDeficitProvider(weekStart)`, used by Bugün, SeriDetay, İçgörü and the notification.
- **Synced settings:** all of these move from SharedPreferences into `user_settings`. Delete the prefs keys.
  - `weekly_rate_kg numeric default 0.5`
  - `expenditure_kcal_manual int null`
  - `meal_count smallint default 3`
  - `targets_source text check in ('onboarding','plan','manual') default 'plan'`
  - `targets_updated_at timestamptz`
  - `checkin_cadence text check in ('weekly','monthly') default 'weekly'`
  - `checkin_weekday smallint default 1`
  - `checkin_monthday smallint default 1`
  - `checkin_reminder bool default true`
  - `hide_photos bool default false`

## 4. Streaks (`domain/streaks.dart`, pure; `streaksProvider` over last 120 days)
| Streak | A day counts when |
|---|---|
| Adım | steps ≥ `daily_steps` |
| Kayıt (beslenme) | ≥ 2 meals logged **or** logged kcal ≥ 50% of the kcal target |
| Açık (kalori açığı) | day is a Kayıt day **and** floor ≤ eaten ≤ kcal target **and** actual deficit ≤ cap (min(25% expenditure, 1000)) |

- The Açık rule is target-based, so it stays consistent with Kokpit's ring and does not reward starving.
- **Today:** counts if already met. If not met, the state is "bekleniyor" and the streak is never broken before 00:00 local time. After midnight the day closes.
- **No freeze.** Each streak shows current and best.
- **Weekly deficit:** shown in the strip and in SeriDetay, with 8 past weeks as bars against target.
- Device-local date is used. There is no timezone column.
- A backdated entry recomputes, because the provider derives the streak from raw data; nothing is stored.
- **Shown in:** Bugün strip, Kokpit Sağlık card line ("Adım 7 · Kayıt 12 · Açık 4"), SeriDetay, İçgörü week view.

## 5. Body measurements
```sql
create table body_measurements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  measured_on date not null,
  waist_cm numeric(5,1), hip_cm numeric(5,1), chest_cm numeric(5,1),
  arm_cm numeric(5,1), thigh_cm numeric(5,1), neck_cm numeric(5,1),
  note text, created_at timestamptz not null default now(),
  unique (user_id, measured_on),
  check (coalesce(waist_cm,hip_cm,chest_cm,arm_cm,thigh_cm,neck_cm) is not null)
);
```
- **RLS:** select/insert/update/delete `using ((select auth.uid()) = user_id)`. There is no friend policy.
- **Form:**
  - 6 numeric fields in cm, one decimal, with the previous value shown as hint text.
  - Each field has one help line, e.g. "Bel: göbek hizası, nefes verince".
  - Every field is optional, but at least one is required.
  - Values must be in the range 20–250.
  - If |Δ| > 5 cm vs. the previous entry, ask "Yanlış girmiş olabilir misin?" with [Düzelt] [Doğru].
  - Saving upserts on `(user_id, measured_on)`.
- **ÖlçülerScreen:**
  - Table: rows = fields, columns = Başlangıç, the last 4 entries and Δ.
  - Tapping a field shows its line chart, with 4/12/Tümü chips.
  - The week-over-week Δ is colored by goal direction (down = success for bel/kalça).

## 6. Progress photos
```sql
create table progress_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  taken_on date not null,
  pose text not null check (pose in ('front','side','back')),
  storage_path text not null,
  created_at timestamptz not null default now(),
  unique (user_id, taken_on, pose)
);
```
- **Storage:** private bucket `body_photos`, path `{uid}/{uuid}.jpg`.
  - The policy for select, insert, update and delete is `(storage.foldername(name))[1] = (select auth.uid())::text`.
  - Images open through 10-minute signed URLs.
  - Never friends, never in reports or AI, never in the friends row.
- **Upload:** resize to 1600 px, JPEG 80%, EXIF stripped. Camera capture shows a translucent outline of the previous same-pose photo as a guide.
- **Poses:** Ön / Yan / Arka.
- **FotoğraflarScreen:**
  - Week grid: one row per check-in date, 3 thumbs.
  - Karşılaştır: two date chips and a pose chip, shown side by side. Under each photo: date, weight (nearest entry ±3 days) and waist.
  - With "Fotoğrafları gizle" on, photos are blurred until tapped.
  - Deleting a photo removes the row and the storage object in the repo (storage first, then the row).
- **Account delete:**
  - The rows cascade.
  - The `delete-account` Edge Function lists `body_photos/{uid}/` and removes all objects. Add this to the existing deletion path.

## 7. Check-in schedule
- Set in Plan > "Ölçü ve fotoğraf günü".
  - Haftalık: weekday, default Pazartesi.
  - Aylık: day 1–28.
- `isCheckinDay(settings, date)` is a pure function.
- A check-in is done when that date has a measurement row or a photo row. Dismissing hides it for that day only.
- On that day:
  - Vücut banner.
  - Kokpit today list gets the system item "Ölçü ve fotoğraf günü · ~3 dk". It is not a task row; it opens KontrolAkışı.
  - A local notification at 09:00, "Bugün ölçü ve fotoğraf günü. Tartı, mezura, fotoğraf: ~3 dk." It is scheduled via the existing reminders service and turned off by `checkin_reminder`.

## 8. Guardrails (`domain/safe_targets.dart`, used by engine, menus, Gemini)
- **kcal floor:** max(1200 for women / 1500 for men, BMR).
- **Deficit cap:** min(25% of expenditure, 1000 kcal). If the chosen rate exceeds it, step down the rate and set `clamped`, which shows the honest line.
- **Macros:**
  - Protein = 1,6 g × target kg, capped at 2,2 g × current kg.
  - Fat ≥ 0,6 g/kg.
  - Carbs fill the rest, never below 50 g.
  - Never rescale macros proportionally (delete the `fatLossApplyValues` rescale).
- **Plan lock:** under 18, or BMI (current or target) < 18,5, gives maintenance only.
- **Manual expenditure:** outside ±30% of the model estimate, show the warning "Bu değer tahminden çok farklı".
- **Menus and equivalents:**
  - A single meal is at most 45% of the target.
  - Meat/fish is at most 250 g per meal.
  - Items over the cap are dropped, not scaled.
- **Gap line:** suggests at most 2 items. It never says "less food" when eaten is below the floor.
- **Gemini:** the prompt gets the targets, the floor, the cap, the weekly deficit and the streaks. It is told to never suggest below the floor, faster than 0,75 kg/week, fasting or skipping meals. Answers that cross these limits are post-filtered and replaced with a safe sentence.
- **Low-intake warning:** 3 consecutive closed days below the floor show the Bugün warning "Son 3 gün çok az yedin" (warning tone, no streak credit).

## 9. Remove / merge; Kokpit; İçgörü
**Delete:**
- `WeekSummaryCard`, `CaloriesWeekCard`, `StepsWeekCard`, `SleepWeekCard`, `WorkoutWeekCard`
- `EnergyNetCard`, `FatLossEntryCard`, `TodayGapCard` (becomes a gap line), `_WeeklyCard`, `_TargetsCard`, `FatLossRateCard`
- `fatLossRateProvider` and the prefs keys, `fatLossMealCountProvider`, `fatLossWeightProvider`, `resolveExpenditure`
- The Klasik/1 kg code
- The second ETA
- `WeeklyCheckinCard` (grep for usage first; if it is used, replace it with KontrolAkışı)
- Health `WaterCard` and Kokpit `_WaterCard` become one `WaterTracker` (compact/full variants) on one `waterProvider`.

**Merge:**
- `EnergyDetailScreen` + `TrendScreen` become HaftalıkDetayScreen.
- `FatLossScreen` becomes the Plan segment body (`plan_view.dart`). Its menu, equivalents and supplements widgets move into Rehber.

**Kokpit:**
- `_CalorieCard` and the step/sleep stat cards are replaced by one **Sağlık kartı**:
  - Mini ring "Kalan 640 kcal".
  - Steps bar.
  - Streak line.
  - Tap goes to Sağlık > Bugün.
- `WaterTracker` (compact).
- The check-in item in the today list.
- The weight quick action opens the shared sheet.
- Work/İşler is unchanged.

**İçgörü (week view):**
- Weekly deficit vs. target.
- Streak counts.
- Weight Δ.
- Month view adds measurement Δ ("Bel −2,5 cm").
- All values come from the same providers.

**Notifications** (max 2/day, no blame, each type can be turned off):
- 20:30: no meals logged today.
- 19:00: steps, only if ≥ 70% of the target is done and fewer than 4.000 steps remain.
- 09:00 on check-in day.
- Sunday 21:00: "Bu hafta −3.100 kcal (≈0,4 kg) · işlerin %80 tamam".

## 10. Work packages (parallel, disjoint file ownership)
**WP1: Engine & data**
- Files:
  - `supabase/migrations/<ts>_health_v2.sql`: user_settings columns, 2 tables, bucket + policies, delete-account update.
  - `settings/domain/user_settings.dart` and its repo.
  - `health/domain/{safe_targets,targets_engine,energy_balance,streaks,weight_eta,checkin}.dart`.
  - `health/data/body_repository.dart` (measurements, photos with resize/EXIF/signed URL).
  - `health/presentation/providers/{targets,week_deficit,streaks,body,water}_providers.dart`.
  - Rewire `onboarding_result.dart`, `profile_goals_page.dart` and the weight-save path to `applyPlan()`.
  - `gemini_parser_service.dart` prompt + filter.
- Tests:
  - `safe_targets` floors, cap and lock.
  - `resolveTargets` for 3 rates and the clamped case.
  - `streaks`: today pending, break, below-floor day not counted, overshoot day not counted.
  - `weekDeficit` sums.
  - `weightEta`.
  - `isCheckinDay` weekly/monthly.
  - `applyPlan` threshold and manual guard.

**WP2: Sağlık Bugün + Plan UI** (depends only on WP1 provider signatures; stub them first)
- Files:
  - `health_screen.dart`
  - `health/presentation/today/*` (streak_strip, day_balance_card, movement_tiles, week_card)
  - `plan_view.dart` (gutted `fat_loss_screen.dart`)
  - `streak_detail_screen.dart`, `weekly_detail_screen.dart`
  - Deletions of the obsolete cards
- Tests: widget tests for empty/filled day card, the streak strip label/semantics, and the Plan clamped and locked states.

**WP3: Vücut UI**
- Files: `health/presentation/body/*` (body_view, measurement_form_sheet, measurements_screen, photos_screen, compare_view, checkin_flow, photo_capture).
- Tests: measurement validation and the ±5 warning, the compare picker, checkin flow skip/complete.

**WP4: Kokpit, İçgörü, notifications, docs**
- Files:
  - `kokpit_day_view.dart` (Sağlık kartı, `WaterTracker` use, checkin item)
  - `reports/*` week/month views
  - Reminders service (4 notification types, max 2/day)
  - `docs/KARARLAR.md`, `docs/yol_haritasi.html` (+ republish)
- Tests: notification scheduling rules and the Kokpit card deep-link route.

Finish with one `flutter analyze` and `flutter test`, then the build.