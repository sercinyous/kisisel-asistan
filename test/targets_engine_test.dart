import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_rate.dart';
import 'package:kisisel_asistan/features/health/domain/safe_targets.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/targets_providers.dart'
    show legacyPrefsMerge;
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

UserSettings _s({
  FatLossRate rate = FatLossRate.classic,
  int? manual = 3000,
  double target = 75,
  int? height = 180,
}) =>
    const UserSettings.defaults().copyWith(
      weeklyRate: rate,
      expenditureKcalManual: manual,
      clearExpenditureKcalManual: manual == null,
      targetWeightKg: target,
      heightCm: height,
      clearHeightCm: height == null,
      birthYear: 1990,
      sex: 'male',
      activityLevel: ActivityLevel.moderate,
    );

ResolvedTargets _r(UserSettings s, {double kg = 84, int age = 36}) =>
    resolveTargets(
        settings: s, latestWeightKg: kg, age: age, sex: Sex.male);

void main() {
  group('resolveTargets', () {
    test('Klasik: kg × 26, protein kg × 2, yağ kcal/30, lif, karb kalan', () {
      final r = _r(_s());
      expect(r.mode, TargetsMode.classic);
      expect(r.kcal, 2184);
      expect(r.proteinG, 168);
      expect(r.fatG, 72);
      expect(r.fiberG, 30);
      expect(r.carbsG, 216);
      expect(r.deficit, 816);
      expect(r.clamped, isFalse);
    });

    test('0,5 / 0,75 / 1 kg: harcama − r × 7700 / 7', () {
      expect(_r(_s(rate: FatLossRate.half)).kcal, 2450);
      expect(_r(_s(rate: FatLossRate.threeQuarter)).kcal, 2175);
      final one = _r(_s(rate: FatLossRate.one));
      expect(one.kcal, 1900);
      expect(one.mode, TargetsMode.rate);
      expect(one.warnings, contains(FatLossRate.one.warning));
    });

    test('rozet vücut ağırlığının yüzdesine göre', () {
      expect(_r(_s(rate: FatLossRate.half)).health, RateHealth.sustainable);
      expect(_r(_s(rate: FatLossRate.threeQuarter)).health, RateHealth.fast);
      expect(_r(_s(rate: FatLossRate.one), kg: 84).health, RateHealth.aggressive);
    });

    test('taban max(1200, bazal) altına inince clamped', () {
      // Bazal 10×84 + 6,25×180 − 5×36 + 5 = 1790; 2000 − 1100 = 900 < 1790.
      final r = _r(_s(rate: FatLossRate.one, manual: 2000));
      expect(r.clamped, isTrue);
      expect(r.kcal, 1790);
      expect(r.floorKcal, 1790);
      expect(r.warnings, contains(SafeTargets.clampedMessage));
    });

    test('makrolar hiçbir hızda kcal\'ı aşmaz', () {
      for (final rate in FatLossRate.values) {
        for (final kg in [50.0, 84.0, 140.0]) {
          final r = _r(_s(rate: rate, manual: 1800, target: 45, height: null),
              kg: kg);
          expect(r.proteinG * 4 + r.fatG * 9 + r.carbsG * 4,
              lessThanOrEqualTo(r.kcal),
              reason: '${rate.name} $kg');
        }
      }
    });

    test('Klasik 1200 altı: uyarı, sayılar değişmez', () {
      final r = _r(_s(target: 30, height: null), kg: 40);
      expect(r.kcal, 1040);
      expect(r.classicBelowFloor, isTrue);
      expect(r.clamped, isFalse);
    });

    test('18 yaş altı: kilit, koruma (harcama kadar)', () {
      final r = _r(_s(rate: FatLossRate.one), age: 16);
      expect(r.mode, TargetsMode.locked);
      expect(r.kcal, 3000);
      expect(r.deficit, 0);
      expect(r.warnings.first, SafeTargets.lockedMessage);
    });

    test('hedef VKİ 18,5 altı: kilit', () {
      final r = _r(_s(target: 55), kg: 70);
      expect(r.locked, isTrue);
    });

    test('hedef kilo şimdikinden düşük değilse koruma', () {
      final r = _r(_s(target: 90));
      expect(r.mode, TargetsMode.maintain);
      expect(r.kcal, 3000);
    });

    test('elle harcama yoksa profil (bazal × hareket katsayısı)', () {
      final r = _r(_s(rate: FatLossRate.half, manual: null));
      // 1790 × 1,55 = 2774,5 → 2775; 2775 − 550 = 2225.
      expect(r.expenditure.source, ExpenditureSource.estimate);
      expect(r.expenditure.kcal, 2775);
      expect(r.kcal, 2225);
    });
  });

  group('planWrite (tek yazar)', () {
    final now = DateTime(2026, 11, 23, 9);

    test('tempo değişimi her zaman yazar, kaynak plan, damga', () {
      final s = _s(rate: FatLossRate.half);
      final w = planWrite(
          settings: s,
          resolved: _r(s),
          trigger: PlanTrigger.rateChanged,
          now: now)!;
      expect(w.settings.dailyCalories, 2450);
      expect(w.settings.dailyProteinG, 168);
      expect(w.settings.targetsSource, TargetsSource.plan);
      expect(w.settings.targetsUpdatedAt, now);
      expect(w.settings.weeklyRate, FatLossRate.half);
      expect(w.previousKcal, 2000);
      expect(w.message, 'Hedefin güncellendi: 2.000 → 2.450 kcal');
    });

    test('ilk kurulum kaynağı onboarding', () {
      final s = _s();
      final w = planWrite(
          settings: s,
          resolved: _r(s),
          trigger: PlanTrigger.onboarding,
          now: now)!;
      expect(w.settings.targetsSource, TargetsSource.onboarding);
    });

    test('tartı: eşik altında yazmaz, üstünde yazar', () {
      final applied = planWrite(
              settings: _s(),
              resolved: _r(_s()),
              trigger: PlanTrigger.rateChanged,
              now: now)!
          .settings;
      // 84 → 83,5 kg: kcal −13, protein −1 → yazılmaz.
      expect(
          planWrite(
              settings: applied,
              resolved: _r(applied, kg: 83.5),
              trigger: PlanTrigger.weightSaved,
              now: now),
          isNull);
      // 84 → 81 kg: kcal −78 → yazılır.
      final w = planWrite(
          settings: applied,
          resolved: _r(applied, kg: 81),
          trigger: PlanTrigger.weightSaved,
          now: now)!;
      expect(w.settings.dailyCalories, 2106);
      expect(w.message, 'Hedefin güncellendi: 2.184 → 2.106 kcal');
    });

    test('tartı: protein farkı 5 g üstündeyse de yazar', () {
      final applied = planWrite(
              settings: _s(),
              resolved: _r(_s()),
              trigger: PlanTrigger.rateChanged,
              now: now)!
          .settings
          .copyWith(dailyProteinG: 160);
      expect(
          planWrite(
              settings: applied,
              resolved: _r(applied),
              trigger: PlanTrigger.weightSaved,
              now: now),
          isNotNull);
    });

    test('kaynak manual iken tartı yazmaz, öneri gösterilir', () {
      final manual = manualTargets(_s(),
          kcal: 1800, proteinG: 150, carbsG: 150, fatG: 60, now: now);
      expect(manual.targetsSource, TargetsSource.manual);
      expect(manual.dailyCalories, 1800);
      expect(
          planWrite(
              settings: manual,
              resolved: _r(manual, kg: 80),
              trigger: PlanTrigger.weightSaved,
              now: now),
          isNull);
      final suggestion = planSuggestion(manual, _r(manual, kg: 80));
      expect(suggestion, isNotNull);
      expect(suggestion!.kcal, 2080);
      // Öneri uygulanınca kaynak plan olur.
      final w = planWrite(
          settings: manual,
          resolved: suggestion,
          trigger: PlanTrigger.suggestionApplied,
          now: now)!;
      expect(w.settings.targetsSource, TargetsSource.plan);
    });

    test('kaynak plan iken öneri yok', () {
      expect(planSuggestion(_s(), _r(_s())), isNull);
    });

    test('yazılan değerler sütun sınırına sıkıştırılır (ölçekleme yok)', () {
      final s = _s(target: 25, height: null);
      final w = planWrite(
          settings: s,
          resolved: _r(s, kg: 30),
          trigger: PlanTrigger.rateChanged,
          now: now)!;
      expect(w.settings.dailyCalories, 800);
      expect(w.settings.dailyProteinG, 60);
    });
  });

  group('eski cihaz tercihleri', () {
    test('hız ve elle harcama taşınır', () {
      final merged = legacyPrefsMerge(const UserSettings.defaults(),
          rate: 'threeQuarter', expenditure: 2700, manualMode: true)!;
      expect(merged.weeklyRate, FatLossRate.threeQuarter);
      expect(merged.expenditureKcalManual, 2700);
    });

    test('elle mod kapalıysa harcama taşınmaz; sunucudaki seçim ezilmez', () {
      expect(
          legacyPrefsMerge(const UserSettings.defaults(),
              expenditure: 2700, manualMode: false),
          isNull);
      final server = const UserSettings.defaults()
          .copyWith(weeklyRate: FatLossRate.half);
      expect(legacyPrefsMerge(server, rate: 'one'), isNull);
    });
  });
}
