import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/templates/meal_templates.dart';
import 'package:kisisel_asistan/features/health/domain/diet_preset.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

const _p = DietPreset.highProtein1800;

UserSettings _adult({int? birthYear = 1990, int heightCm = 175}) =>
    const UserSettings.defaults().copyWith(
      startWeightKg: 85,
      targetWeightKg: 75,
      heightCm: heightCm,
      birthYear: birthYear,
      sex: 'male',
    );

PresetCheck _check(UserSettings s, {double weight = 85, int? age = 36}) =>
    checkPreset(
      preset: _p,
      settings: s,
      latestWeightKg: weight,
      age: age,
      sex: Sex.male,
    );

void main() {
  final now = DateTime(2026, 11, 27);

  group('paket makroları', () {
    test('1800 kcal, yüksek protein, 4/9/4 toplamı tutar', () {
      expect(_p.kcal, 1800);
      expect(_p.proteinG, 150);
      expect(_p.fatG, 60);
      expect(_p.carbsG, 165);
      expect(_p.fiberG, 30);
      expect(_p.macroKcal, 1800);
      expect(_p.label, '1800 kcal · Yüksek protein');
    });

    test('menü 4 öğün, ≈1800 kcal ve ≈150 g protein', () {
      expect(_p.meals.map((m) => m.mealType).toList(),
          ['breakfast', 'lunch', 'dinner', 'snack']);
      expect(_p.menuKcal, closeTo(1800, 30));
      expect(_p.menuProteinG, closeTo(150, 5));
      for (final m in _p.meals) {
        final kcal = m.proteinG * 4 + m.carbsG * 4 + m.fatG * 9;
        expect(m.calories, closeTo(kcal, 10), reason: m.label);
        expect(MealTemplates.all, contains(m));
      }
    });
  });

  group('motor entegrasyonu', () {
    test('yetişkin, taban altında değil: uygulanır, kaynak manual', () {
      final s = _adult();
      final check = _check(s);
      expect(check.allowed, isTrue);
      expect(check.warning, isNull);
      final write = presetWrite(settings: s, check: check, now: now)!;
      expect(write.kcal, 1800);
      expect(write.previousKcal, s.dailyCalories);
      final w = write.settings;
      expect(w.dailyCalories, 1800);
      expect(w.dailyProteinG, 150);
      expect(w.dailyCarbsG, 165);
      expect(w.dailyFatG, 60);
      expect(w.targetsSource, TargetsSource.manual);
      expect(w.goalMode, s.goalMode);
      expect(presetActive(w, _p), isTrue);
      expect(presetActive(s, _p), isFalse);
    });

    test('tartı kaydı paketi ezmez (kaynak manual)', () {
      final s = _adult();
      final w = presetWrite(settings: s, check: _check(s), now: now)!.settings;
      final resolved = resolveTargets(
          settings: w, latestWeightKg: 84, age: 36, sex: Sex.male);
      expect(
        planWrite(
            settings: w,
            resolved: resolved,
            trigger: PlanTrigger.weightSaved,
            now: now),
        isNull,
      );
    });

    test('önceki plana dön: motor yeniden yazar, paket kalkar', () {
      final s = _adult();
      final w = presetWrite(settings: s, check: _check(s), now: now)!.settings;
      final resolved = resolveTargets(
          settings: w, latestWeightKg: 85, age: 36, sex: Sex.male);
      final back = planWrite(
          settings: w,
          resolved: resolved,
          trigger: PlanTrigger.suggestionApplied,
          now: now)!;
      expect(back.settings.targetsSource, TargetsSource.plan);
      expect(presetActive(back.settings, _p), isFalse);
    });

    test('geri al önceki hedefleri ve kaynağı geri yazar', () {
      final s = _adult().copyWith(
          dailyCalories: 2100,
          dailyProteinG: 140,
          targetsSource: TargetsSource.plan);
      final w = presetWrite(settings: s, check: _check(s), now: now)!.settings;
      final r = restoreTargets(w, s);
      expect(r.dailyCalories, 2100);
      expect(r.dailyProteinG, 140);
      expect(r.targetsSource, TargetsSource.plan);
    });

    test('18 yaş altı: kilitli, yazılmaz', () {
      final s = _adult(birthYear: 2010);
      final check = _check(s, age: 16);
      expect(check.block, PresetBlock.locked);
      expect(check.warning, contains('18 yaş altı'));
      expect(presetWrite(settings: s, check: check, now: now), isNull);
    });

    test('VKİ 18,5 altı: kilitli', () {
      final s =
          _adult(heightCm: 185).copyWith(startWeightKg: 60, targetWeightKg: 58);
      final check = _check(s, weight: 60);
      expect(check.block, PresetBlock.locked);
    });

    test('bazal 1800 üstünde: taban altında, yazılmaz', () {
      final s = _adult(heightCm: 195)
          .copyWith(startWeightKg: 140, targetWeightKg: 110);
      final check = _check(s, weight: 140, age: 25);
      expect(check.floorKcal, greaterThan(1800));
      expect(check.block, PresetBlock.belowFloor);
      expect(check.warning, contains('güvenli tabanının'));
      expect(presetWrite(settings: s, check: check, now: now), isNull);
    });
  });
}
