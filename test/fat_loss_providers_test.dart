import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  final today = AppDates.startOfDay(DateTime.now());

  ProviderContainer make(FakeHealthRepository health) {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      healthRepositoryProvider.overrideWithValue(health),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository(
          settings: const UserSettings.defaults().copyWith(dailyProteinG: 168))),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('plan en son tarihli tartıyı kullanır, sıradan bağımsız', () async {
    final health = FakeHealthRepository(weights: [
      WeightEntry(id: 'yeni', weightKg: 80, loggedAt: today),
      WeightEntry(
          id: 'eski', weightKg: 90, loggedAt: AppDates.addDays(today, -3)),
    ]);
    final c = make(health);
    final plan = await c.read(fatLossPlanProvider.future);
    expect(plan!.weight.id, 'yeni');
    expect(plan.targets.kcal, 2080);
  });

  test('yeni kilo eklenince plan güncellenir', () async {
    final health = FakeHealthRepository(weights: [
      WeightEntry(
          id: 'eski', weightKg: 90, loggedAt: AppDates.addDays(today, -1)),
    ]);
    final c = make(health);
    final sub = c.listen(fatLossPlanProvider, (_, __) {});
    addTearDown(sub.close);
    expect((await c.read(fatLossPlanProvider.future))!.targets.weightKg, 90);
    await health.addWeight(84);
    c.invalidate(weightSeriesProvider);
    expect((await c.read(fatLossPlanProvider.future))!.targets.weightKg, 84);
  });

  test('bugün kartı öğün eklenince güncellenir', () async {
    final health = FakeHealthRepository(weights: [
      WeightEntry(id: 'w', weightKg: 84, loggedAt: today),
    ]);
    final c = make(health);
    final sub = c.listen(todayMealGapProvider, (_, __) {});
    addTearDown(sub.close);
    expect((await c.read(todayMealGapProvider.future))!.nothingLogged, isTrue);
    await health.createNutritionLog(NutritionLog(
      id: '',
      foodName: 'Tavuk',
      mealType: 'lunch',
      calories: 500,
      proteinG: 123,
      eatenAt: today.add(const Duration(hours: 12)),
    ));
    c.invalidate(dayNutritionLogsProvider);
    final r = (await c.read(todayMealGapProvider.future))!;
    expect(r.nothingLogged, isFalse);
    expect(r.gap(GapMetric.protein).headline, 'Protein 45 g eksik');
  });

  test('hız seçimi user_settings\'e yazılır ve hedefleri motorla günceller',
      () async {
    final health = FakeHealthRepository(weights: [
      WeightEntry(id: 'w', weightKg: 84, loggedAt: today),
    ]);
    final repo = FakeSettingsRepository(
      settings: const UserSettings.defaults().copyWith(
        targetWeightKg: 75,
        expenditureKcalManual: 2800,
      ),
    );
    final c = ProviderContainer(overrides: [
      healthRepositoryProvider.overrideWithValue(health),
      settingsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    await c.read(userSettingsProvider.future);
    await c.read(fatLossRateProvider.notifier).set(FatLossRate.half);
    final saved = repo.settings!;
    expect(saved.weeklyRate, FatLossRate.half);
    expect(saved.dailyCalories, 2250);
    expect(saved.targetsSource, TargetsSource.plan);
    expect(c.read(fatLossRateProvider), FatLossRate.half);
  });

  test('öğün sayısı user_settings\'e yazılır', () async {
    final repo = FakeSettingsRepository(settings: const UserSettings.defaults());
    final c = ProviderContainer(overrides: [
      healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
      settingsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    await c.read(userSettingsProvider.future);
    await c.read(fatLossMealCountProvider.notifier).set(2);
    expect(repo.settings!.mealCount, 2);
    expect(c.read(fatLossMealCountProvider), 2);
  });
}
