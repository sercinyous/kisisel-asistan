import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_plan.dart';
import 'package:kisisel_asistan/features/health/domain/goal_mode.dart';
import 'package:kisisel_asistan/features/health/domain/goal_projection.dart';
import 'package:kisisel_asistan/features/health/domain/meal_gap.dart';
import 'package:kisisel_asistan/features/health/domain/streaks.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/week_deficit_providers.dart'
    show weekTargetFor;
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_answers.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_result.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

UserSettings _s({
  GoalMode goal = GoalMode.fatLoss,
  GainRate gain = GainRate.slow,
  FatLossRate rate = FatLossRate.half,
  int manual = 3000,
  double target = 75,
}) =>
    const UserSettings.defaults().copyWith(
      goalMode: goal,
      gainRate: gain,
      weeklyRate: rate,
      expenditureKcalManual: manual,
      targetWeightKg: target,
      heightCm: 180,
      birthYear: 1990,
      sex: 'male',
      activityLevel: ActivityLevel.moderate,
    );

ResolvedTargets _r(UserSettings s, {double kg = 84, int age = 36}) =>
    resolveTargets(settings: s, latestWeightKg: kg, age: age, sex: Sex.male);

void _macrosFit(ResolvedTargets r) {
  final macroKcal = r.proteinG * 4 + r.carbsG * 4 + r.fatG * 9;
  expect(macroKcal, lessThanOrEqualTo(r.kcal));
}

void main() {
  group('GoalMode / GainRate', () {
    test('veritabanı değerleri ve çözümleme', () {
      expect(GoalMode.values.map((g) => g.dbValue),
          ['fat_loss', 'recomp', 'lean_gain', 'maintain']);
      expect(GoalMode.parse('lean_gain'), GoalMode.leanGain);
      expect(GoalMode.parse('recomp'), GoalMode.recomp);
      expect(GoalMode.parse(null), GoalMode.fatLoss);
      expect(GoalMode.parse('bulk'), GoalMode.fatLoss);
      expect(GainRate.parse('standard'), GainRate.standard);
      expect(GainRate.parse(null), GainRate.slow);
      expect(GainRate.slow.surplusKcal, 250);
      expect(GainRate.standard.surplusKcal, 400);
    });
  });

  group('resolveTargets hedef türleri', () {
    test('yağ yakma mevcut hız modudur', () {
      final r = _r(_s());
      expect(r.mode, TargetsMode.rate);
      expect(r.goal, GoalMode.fatLoss);
      expect(r.kcal, 3000 - 550);
      expect(r.weeklyChangeKg, closeTo(-0.5, 0.01));
      _macrosFit(r);
    });

    test('kas yaparken yağ yakma: harcama −%10, protein kg × 2,2, not', () {
      final r = _r(_s(goal: GoalMode.recomp));
      expect(r.mode, TargetsMode.recomp);
      expect(r.kcal, 2700);
      expect(r.deficit, 300);
      expect(r.proteinG, (84 * 2.2).floor());
      expect(r.goalNotes, [GoalRules.recompStrengthNote]);
      _macrosFit(r);
    });

    test('kas yaparken yağ yakma tabanın altına inmez', () {
      final r = _r(_s(goal: GoalMode.recomp, manual: 1250), kg: 60);
      expect(r.kcal, greaterThanOrEqualTo(r.floorKcal));
      expect(r.kcal, greaterThanOrEqualTo(1200));
      _macrosFit(r);
    });

    test('kas yapma: +250 / +400, protein kg × 2,0, tahmini artış', () {
      final slow = _r(_s(goal: GoalMode.leanGain));
      expect(slow.mode, TargetsMode.gain);
      expect(slow.kcal, 3250);
      expect(slow.surplus, 250);
      expect(slow.proteinG, 168);
      expect(slow.weeklyChangeKg, 0.25);
      expect(slow.goalNotes, [GoalRules.gainEstimateNote]);
      _macrosFit(slow);

      final std = _r(_s(goal: GoalMode.leanGain, gain: GainRate.standard));
      expect(std.kcal, 3400);
      expect(std.weeklyChangeKg, 0.4);
      _macrosFit(std);
    });

    test('kas yapma düşük VKİ\'de kilitlenmez, 18 yaş altında kilitlenir', () {
      final thin = _r(_s(goal: GoalMode.leanGain, target: 62), kg: 55);
      expect(thin.mode, TargetsMode.gain);
      final minor = _r(_s(goal: GoalMode.leanGain), age: 16);
      expect(minor.mode, TargetsMode.locked);
      expect(minor.kcal, 3000);
    });

    test('kiloyu koru: harcama kadar, protein kg × 1,6', () {
      final r = _r(_s(goal: GoalMode.maintain));
      expect(r.mode, TargetsMode.maintain);
      expect(r.goal, GoalMode.maintain);
      expect(r.kcal, 3000);
      expect(r.proteinG, (84 * 1.6).floor());
      expect(r.weeklyChangeKg, 0);
      _macrosFit(r);
    });

    test('düşük kalori ve yüksek proteinde makrolar kcal\'ı aşmaz', () {
      for (final g in GoalMode.values) {
        _macrosFit(_r(_s(goal: g, manual: 1200), kg: 140));
      }
    });

    test('planWrite hedef türünü ve tempoyu taşır', () {
      final s = _s(goal: GoalMode.leanGain, gain: GainRate.standard);
      final w = planWrite(
        settings: s,
        resolved: _r(s),
        trigger: PlanTrigger.rateChanged,
        now: DateTime(2026, 11, 23),
      )!;
      expect(w.settings.goalMode, GoalMode.leanGain);
      expect(w.settings.gainRate, GainRate.standard);
      expect(w.settings.dailyCalories, 3400);
    });

    test('haftalık hedef: kas yapmada fazla × 7, korumada 0', () {
      expect(weekTargetFor(_r(_s(goal: GoalMode.leanGain))), 1750);
      expect(weekTargetFor(_r(_s(goal: GoalMode.recomp))), 2100);
      expect(weekTargetFor(_r(_s(goal: GoalMode.maintain))), 0);
      expect(weekTargetFor(_r(_s())), 3850);
    });
  });

  group('GoalProjection', () {
    List<GoalProjection> project({double target = 78, double kg = 84}) =>
        projectGoals(
          settings: _s(target: target),
          latestWeightKg: kg,
          age: 36,
          sex: Sex.male,
        );

    test('her hedef için bir kart, sıra GoalMode.values', () {
      expect(project().map((p) => p.goal), GoalMode.values);
    });

    test('yağ yakma: ~12 haftada −6 kg, hedefe kalan süre', () {
      final p = project().firstWhere((p) => p.goal == GoalMode.fatLoss);
      expect(p.weeklyKg, closeTo(-0.5, 0.01));
      expect(p.horizonKg, closeTo(-6, 0.1));
      expect(p.headline, 'Bunu yaparsan ~12 haftada −6 kg');
      expect(p.etaWeeks, 12);
      expect(p.etaText, 'Hedef kiloya ~12 haftada');
      expect(p.weeklyText, '−0,50 kg/hafta');
    });

    test('kas yapma: +3 kg, bir kısmı yağ; hedef aşağıdaysa süre yok', () {
      final p = project().firstWhere((p) => p.goal == GoalMode.leanGain);
      expect(p.headline, 'Bunu yaparsan ~12 haftada +3 kg, bir kısmı yağ');
      expect(p.etaWeeks, isNull);
      final up =
          project(target: 88).firstWhere((p) => p.goal == GoalMode.leanGain);
      expect(up.etaWeeks, 16);
    });

    test('koruma: sabit', () {
      final p = project().firstWhere((p) => p.goal == GoalMode.maintain);
      expect(p.weeklyText, '≈ sabit');
      expect(p.headline, contains('sabit'));
      expect(p.etaWeeks, isNull);
    });

    test('kas yaparken yağ yakma: açık kadar yavaş kayıp', () {
      final p = project().firstWhere((p) => p.goal == GoalMode.recomp);
      expect(p.kcal, 2700);
      expect(p.weeklyKg, closeTo(-300 * 7 / FatLossRules.kcalPerKgFat, 1e-9));
    });
  });

  group('seriler hedefe göre', () {
    final today = DateTime(2026, 11, 23);
    List<StreakDay> days(double kcal) => [
          for (var i = 2; i >= 0; i--)
            StreakDay(
              date: DateTime(2026, 11, 23 - i),
              mealCount: 3,
              intakeKcal: kcal,
              expenditureKcal: 2500,
            ),
        ];

    test('yağ yakmada Açık serisi, diğerlerinde Hedef serisi', () {
      const fat =
          StreakTargets(dailySteps: 8000, kcalTarget: 2000, floorKcal: 1700);
      expect(
          computeStreaks(days: days(2000), targets: fat, today: today)
              .map((s) => s.kind),
          [StreakKind.steps, StreakKind.logging, StreakKind.deficit]);
      for (final g in [GoalMode.leanGain, GoalMode.maintain, GoalMode.recomp]) {
        final t = StreakTargets(
            dailySteps: 8000, kcalTarget: 2800, floorKcal: 1700, goal: g);
        final kinds = computeStreaks(days: days(2800), targets: t, today: today)
            .map((s) => s.kind);
        expect(kinds, contains(StreakKind.target));
        expect(kinds, isNot(contains(StreakKind.deficit)));
      }
    });

    test('Hedef günü: alınan hedefin ±%10\'u içinde', () {
      const t = StreakTargets(
          dailySteps: 8000,
          kcalTarget: 2800,
          floorKcal: 1700,
          goal: GoalMode.leanGain);
      StreakDay d(double kcal) => StreakDay(
          date: today, mealCount: 3, intakeKcal: kcal, expenditureKcal: 2500);
      expect(isTargetDay(d(2800), t), isTrue);
      expect(isTargetDay(d(3080), t), isTrue);
      expect(isTargetDay(d(2520), t), isTrue);
      expect(isTargetDay(d(3100), t), isFalse);
      expect(isTargetDay(d(2400), t), isFalse);
      final s = computeStreaks(days: days(2800), targets: t, today: today)
          .firstWhere((s) => s.kind == StreakKind.target);
      expect(s.current, 3);
      expect(StreakKind.target.semanticLabel, 'Hedef serisi');
    });

    test('kas yapmada haftalık kart fazlayı gösterir', () {
      final w = computeWeekDeficit(
        weekStart: DateTime(2026, 11, 23),
        days: [
          StreakDay(
              date: today,
              mealCount: 3,
              intakeKcal: 2800,
              expenditureKcal: 2500),
        ],
        today: today,
        targetKcal: 1750,
        surplusGoal: true,
      );
      expect(w.balanceKcal, 300);
      expect(w.dayBalance(w.days.single), 300);
      expect(w.progress, closeTo(300 / 1750, 1e-9));
    });
  });

  group('öğün eksiği hedefe göre', () {
    test('kas yapmada kalori ±%10 içinde tamam sayılır', () {
      const targets = FatLossTargets(
          weightKg: 84,
          kcal: 3000,
          proteinG: 168,
          fatG: 90,
          fiberG: 40,
          carbsG: 380);
      final fat = analyzeMealGap(targets: targets, logs: const []);
      expect(fat.gap(GapMetric.kcal).status, GapStatus.deficit);
      const gap = MacroGap(
          metric: GapMetric.kcal,
          eaten: 2800,
          target: 3000,
          kcalTolerance: 300);
      expect(gap.status, GapStatus.onTarget);
      const strict =
          MacroGap(metric: GapMetric.kcal, eaten: 2800, target: 3000);
      expect(strict.status, GapStatus.deficit);
    });
  });

  group('ayarlar', () {
    test('goal_mode ve gain_rate okunur ve yazılır', () {
      final s = SettingsRepository.parseRow({
        'onboarded_at': '2026-11-01T00:00:00Z',
        'weekly_rate': '0.5',
        'goal_mode': 'recomp',
        'gain_rate': 'standard',
      });
      expect(s.goalMode, GoalMode.recomp);
      expect(s.gainRate, GainRate.standard);
      expect(s.goalModeColumns, isTrue);
      final map = s.toMap();
      expect(map['goal_mode'], 'recomp');
      expect(map['gain_rate'], 'standard');
    });

    test('eski şema: goal_mode yoksa yazılmaz', () {
      final s = SettingsRepository.parseRow({
        'onboarded_at': '2026-11-01T00:00:00Z',
        'weekly_rate': '0.5',
      });
      expect(s.goalMode, GoalMode.fatLoss);
      expect(s.goalModeColumns, isFalse);
      expect(s.toMap().containsKey('goal_mode'), isFalse);
      expect(s.toMap().containsKey('gain_rate'), isFalse);
      expect(s.toMap()['weekly_rate'], '0.5');
    });
  });

  group('ilk kurulum', () {
    test('"Kilo al" motordan kas yapma hedefine gider', () {
      expect(onboardingGoalMode(OnboardingGoal.gain), GoalMode.leanGain);
      expect(onboardingGoalMode(OnboardingGoal.maintain), GoalMode.maintain);
      expect(onboardingGoalMode(OnboardingGoal.lose), GoalMode.fatLoss);
    });
  });
}
