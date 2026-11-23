# Sağlık v2: motor ve veri API'si (WP1)

UI paketleri (WP2–WP4) için kısa başvuru. Sahip kararları `docs/SPEC_SAGLIK.md`'yi şu noktalarda geçersiz kılar:
hızlar **Klasik (kg×26)** (varsayılan), **0,50**, **0,75**, **1 kg/hafta** (0,25 yok); hız modunda taban
max(1200, bazal) ve açık sınırı yok (1 kg uyarı metniyle); Klasik 1.200 altı yalnızca uyarı.

## Şema (`supabase/schema.sql`, blok `health_v2`)
- `user_settings`: `weekly_rate` ('classic' | '0.5' | '0.75' | '1.0', varsayılan 'classic'),
  `expenditure_kcal_manual` (1200–6000 | null), `meal_count` (2–3), `targets_source`
  ('onboarding' | 'plan' | 'manual'), `targets_updated_at`, `checkin_cadence` ('weekly' | 'monthly'),
  `checkin_weekday` (1–7, ISO), `checkin_monthday` (1–28), `checkin_reminder`, `hide_photos`.
- `body_measurements` (gün başına tek satır, `unique(user_id, measured_on)`), `progress_photos`
  (`unique(user_id, taken_on, pose)`, `storage_path = <uid>/<YYYY-MM-DD>/<pose>.jpg`). Yalnızca sahibi (RLS).
- Storage `body_photos`: özel, yalnızca sahibi. Hesap silme (`delete-account`) kovayı da temizler.
- `complete_onboarding` artık `weekly_rate`, `targets_source`, `targets_updated_at` da yazar.
- Blok `goal_mode`: `user_settings.goal_mode` ('fat_loss' varsayılan | 'recomp' | 'lean_gain' | 'maintain'),
  `gain_rate` ('slow' | 'standard'); `complete_onboarding` ikisini de coalesce ile yazar.
  `report_health_safety` sonucu `goal_mode` taşır; `generate-reports` talimatı buna göre açık ya da fazla dili kullanır.

## Ayarlar (`lib/features/settings/domain/user_settings.dart`)
`UserSettings` yeni alanlar: `weeklyRate` (`FatLossRate`), `expenditureKcalManual`, `mealCount`,
`targetsSource` (`TargetsSource`), `targetsUpdatedAt`, `checkinCadence` (`CheckinCadence`),
`checkinWeekday`, `checkinMonthday`, `checkinReminder`, `hidePhotos`. `copyWith(clearExpenditureKcalManual: true)`.
`FatLossRate`: `classic | half | threeQuarter | one`, `.dbValue`, `.label`, `.kgPerWeek`, `.warning` (yalnızca 1 kg).
`goalMode` (`GoalMode`), `gainRate` (`GainRate`); `goalModeColumns` false ise (eski şema) `toMap` ikisini yazmaz,
Plan'ın Hedef türü kartı gizlenir ve `applyPlan(goal:, gainRate:)` değişikliği yok sayar.
Eski SharedPreferences anahtarları bir kez taşınır (`legacyFatLossPrefsMigrationProvider`, HomeShell izler) ve silinir.

## Saf alan katmanı (`lib/features/health/domain/`)
- `safe_targets.dart`: `SafeTargets` sabitleri ve metinleri (`lockedMessage`, `clampedMessage`,
  `classicBelowFloorWarning`, `lowIntakeWarning`, `manualExpenditureWarning`), `kcalFloor(basal)`,
  `deficitCap(exp)`, `planLocked(...)`, `bmiOf`, `manualExpenditureOutOfRange`, `recommendedWaterMl(kg)`,
  `fitMacros(...)` (makrolar asla kcal'ı aşmaz), `AiHealthContext`, `filterAiHealthAdvice(text, floorKcal:)`.
- `targets_engine.dart`:
  - `ResolvedTargets resolveTargets({settings, latestWeightKg, age, sex})` → `mode` (`TargetsMode.classic | rate | maintain | locked`),
    `kcal, proteinG, carbsG, fatG, fiberG, deficit, kgPerWeek, health (RateHealth?), clamped, floorKcal,
    expenditure (Expenditure), classicBelowFloor, locked, warnings`.
  - `PlanWrite? planWrite({settings, resolved, trigger, now})` — `daily_*` sütunlarının **tek yazarı**.
    `PlanTrigger.onboarding | weightSaved | rateChanged | suggestionApplied`. Tartıda yalnızca kaynak ≠ manual ve
    |Δkcal| > 50 veya |Δprotein| > 5. `PlanWrite.message` = "Hedefin güncellendi: 1.880 → 1.850 kcal".
  - `manualTargets(settings, kcal:, proteinG:, carbsG:, fatG:, now:)` (kaynak 'manual'),
    `planSuggestion(settings, resolved)` (kaynak manual iken öneri), `ageFromSettings`, `settingsBasal`.
- `energy_balance.dart`: tek harcama modeli `dayExpenditure({day, now, manualKcal, basal, activeKcal, steps})`
  (elle → bazal + sağlık aktif → bazal × 1,2 + adım × 0,04; bugün oranlı) ve `planExpenditure(...)`.
- `streaks.dart`: `StreakDay`, `StreakTargets`, `StreakKind` (`label`, `semanticLabel`), `StreakStatus`
  (`current, best, today: StreakToday.done|pending, days, semantics`), `computeStreaks(...)`,
  `isStepsDay/isLoggingDay/isDeficitDay`, `lowIntakeWarning(...)`, `WeekDeficit` (`days, totalKcal, kg, progress, targetKcal`),
  `computeWeekDeficit(...)`, `weeklyDeficitTarget(...)`.
- `weight_eta.dart`: `weightEta(series, targetKg:, now:)`, `actualKgPerWeek(series, now:)`.
- `checkin.dart`: `isCheckinDay(settings, date)`, `nextCheckinDay`, `daysUntilCheckin`, `isCheckinDone`,
  `checkinScheduleLine` ("Sonraki ölçü günü: Pazartesi · 3 gün kaldı"), `checkinNotificationBody`.
- `body_models.dart`: `BodyField` (label, help, lowerIsBetter), `BodyMeasurement`, `validateMeasurement`,
  `suspiciousFields` (±5 cm), `summarizeMeasurements` → `BodyFieldSummary`, `PhotoPose` (Ön/Yan/Arka),
  `ProgressPhoto`, `PhotoCheckin`, `groupPhotos`, `progressPhotoPath`.

## Veri (`lib/features/health/data/body_repository.dart`)
`bodyRepositoryProvider` → `BodyRepository`: `photosSupported`, `fetchMeasurements({from})`,
`upsertMeasurement(m)`, `deleteMeasurement(id)`, `fetchPhotos()`, `uploadPhoto({takenOn, pose, imageBytes})`
(1600 px, JPEG %80, EXIF silinir: `progressPhotoJpeg` in `core/avatar/avatar_image.dart`),
`deletePhoto(photo)` (önce Storage, sonra satır), `signedUrl(path)` (10 dk). Demo/test: `MemoryBodyRepository`.

## Sağlayıcılar (`lib/features/health/presentation/providers/`)
- `targets_providers.dart`: `targetsProvider` (`DailyTargets`), `latestWeightProvider`, `resolvedTargetsProvider`,
  `planSuggestionProvider`, `planControllerProvider` → `PlanController`:
  `applyPlan(PlanTrigger, {rate, weightKg}) → Future<PlanWrite?>`, `saveManualTargets(...)`,
  `setExpenditureManual(int?)`, `setMealCount(int)`, `setCheckinSchedule({cadence, weekday, monthday, reminder})`,
  `setHidePhotos(bool)`.
- `week_deficit_providers.dart`: `healthDaysProvider((from:, to:))` → `HealthDays(days, hasSteps)`,
  `weekDeficitProvider(weekStart)`, `currentWeekDeficitProvider`, `pastWeekDeficitsProvider(weeks)`.
- `streaks_providers.dart`: `streaksProvider` → `StreaksState(streaks, lowIntake, of(kind), line)` (120 gün).
- `body_providers.dart`: `measurementsProvider`, `measurementSummaryProvider`, `progressPhotosProvider`,
  `photoCheckinsProvider`, `photoUrlProvider(path)`, `checkinTodayProvider` (`isCheckinDay, done, showBanner, scheduleLine`),
  `invalidateBodyData(container)`.
- `water_providers.dart`: `waterProvider` (= `waterTodayProvider`), `recommendedWaterMlProvider`.

## Yeniden bağlananlar
- Tartı kaydı: `updatePlanAfterWeight(container, messenger)` (`weight_sheets.dart`) → `applyPlan(weightSaved)` + snackbar.
- İlk kurulum: `suggestOnboardingTargets(answers, now:)`; öneri aynen kabul edildiyse kaynak 'onboarding', değilse 'manual'.
- Ayarlar > Hedeflerim: kcal/makro değiştiyse `manualTargets` (kaynak 'manual').
- Yağ yakımı ekranı (eski UI, WP2'de Plan olur): sağlayıcılar `user_settings` üzerinden; "Hedeflerimi buna göre ayarla" kaldırıldı.
- Gemini: `generateWeeklySummary(metrics, {AiHealthContext? health})` sınırları talimata ekler ve cevabı süzer.
