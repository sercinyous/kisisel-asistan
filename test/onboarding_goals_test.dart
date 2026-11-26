import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/onboarding/domain/goal_suggestion.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_answers.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

OnboardingAnswers _answers({
  double weight = 80,
  int height = 180,
  int birthYear = 1990,
  Sex sex = Sex.male,
  OnboardingGoal goal = OnboardingGoal.lose,
  ActivityLevel activity = ActivityLevel.light,
}) =>
    OnboardingAnswers(
      displayName: 'Ayşe',
      heightCm: height,
      birthYear: birthYear,
      sex: sex,
      weightKg: weight,
      targetWeightKg: weight,
      goal: goal,
      activity: activity,
    );

OnboardingTargets _suggest(OnboardingAnswers a, {int nowYear = 2026}) =>
    GoalSuggestion.compute(a, nowYear: nowYear);

void main() {
  group('GoalSuggestion: kalori = bazal x hareket katsayısı + amaç farkı', () {
    // Erkek, 80 kg, 180 cm, 36 yaş: bazal 800 + 1125 - 180 + 5 = 1750;
    // az hareketli x 1,375 = 2406,25.
    test('ver −500, koru 0, al +300', () {
      expect(_suggest(_answers(goal: OnboardingGoal.lose)).calories, 1906);
      expect(_suggest(_answers(goal: OnboardingGoal.maintain)).calories, 2406);
      expect(_suggest(_answers(goal: OnboardingGoal.gain)).calories, 2706);
    });

    test('hareket düzeyi katsayıları: 1,2 / 1,375 / 1,55 / 1,725 / 1,9', () {
      expect([for (final l in ActivityLevel.values) l.factor],
          [1.2, 1.375, 1.55, 1.725, 1.9]);
      int kcal(ActivityLevel level) => _suggest(
            _answers(goal: OnboardingGoal.maintain, activity: level),
          ).calories;
      expect(kcal(ActivityLevel.sedentary), 2100);
      expect(kcal(ActivityLevel.moderate), 2713);
      expect(kcal(ActivityLevel.active), 3019);
      expect(kcal(ActivityLevel.veryActive), 3325);
    });

    test('hareket düzeyi veritabanı değerleri', () {
      expect([for (final l in ActivityLevel.values) l.dbValue],
          ['sedentary', 'light', 'moderate', 'active', 'very_active']);
      expect(ActivityLevel.tryParse('very_active'), ActivityLevel.veryActive);
      expect(ActivityLevel.tryParse('lazy'), isNull);
      expect(ActivityLevel.tryParse(null), isNull);
    });

    test('amaç farkları sabit', () {
      expect(OnboardingGoal.lose.kcalDelta, -500);
      expect(OnboardingGoal.maintain.kcalDelta, 0);
      expect(OnboardingGoal.gain.kcalDelta, 300);
    });

    test('cinsiyet katsayısı: kadın −161, belirtmeyen −78 (4A bazal fonksiyonu)',
        () {
      final base = _answers(goal: OnboardingGoal.maintain);
      final male = _suggest(base).calories;
      final female = _suggest(
        _answers(sex: Sex.female, goal: OnboardingGoal.maintain),
      ).calories;
      final other = _suggest(
        _answers(sex: Sex.unspecified, goal: OnboardingGoal.maintain),
      ).calories;
      // Bazal farkı x 1,375: 166 x 1,375 = 228,25; 83 x 1,375 = 114,1.
      expect(male - female, closeTo(228.25, 1));
      expect(male - other, closeTo(114.1, 1));
    });

    test('küçük kadın, 66 yaş: açık hedefi 1200 kcal altına inmez', () {
      // Bazal 450 + 937,5 - 330 - 161 = 896,5; x 1,375 - 500 = 733 -> 1200.
      final targets = _suggest(
        _answers(
          weight: 45,
          height: 150,
          birthYear: 1960,
          sex: Sex.female,
          goal: OnboardingGoal.lose,
        ),
      );
      expect(targets.calories, GoalSuggestion.minCalories);
      expect(GoalSuggestion.minCalories, 1200);
    });

    test('18 yaş altında açık uygulanmaz (4A: reşit olmayana açık hedefi yok)',
        () {
      // 16 yaş: bazal 600 + 1075 - 80 + 5 = 1600; x 1,375 = 2200.
      final lose = _suggest(
        _answers(weight: 60, height: 172, birthYear: 2010),
      );
      final maintain = _suggest(
        _answers(
          weight: 60,
          height: 172,
          birthYear: 2010,
          goal: OnboardingGoal.maintain,
        ),
      );
      expect(lose.calories, 2200);
      expect(lose.calories, maintain.calories);
      // 18 yaşında açık uygulanır.
      final adult = _suggest(
        _answers(weight: 60, height: 172, birthYear: 2008),
      );
      expect(adult.calories, lessThan(lose.calories));
    });
  });

  group('GoalSuggestion: protein, makrolar, adım, uyku', () {
    test('protein kilo başına 1,6 g', () {
      expect(_suggest(_answers(weight: 80)).proteinG, 128);
      expect(_suggest(_answers(weight: 100)).proteinG, 160);
      expect(GoalSuggestion.proteinPerKg, 1.6);
    });

    test('adım 8000, uyku 7,5 saat (450 dk)', () {
      final t = _suggest(_answers());
      expect(t.steps, 8000);
      expect(t.sleepMinutes, 450);
    });

    test('makrolar kaloriyle tutarlı (yağ %27, kalan karbonhidrat)', () {
      final t = _suggest(_answers());
      expect(t.fatG, 57);
      final kcal = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
      expect((kcal - t.calories).abs(), lessThanOrEqualTo(8));
    });

    test('tüm öneriler veritabanı sınırları içinde (uç kilo ve boylar)', () {
      for (final (weight, height, year) in [
        (30.0, 100, 2013),
        (250.0, 250, 1900),
        (45.0, 150, 1960),
        (120.0, 175, 1985),
      ]) {
        for (final sex in Sex.values) {
          for (final goal in OnboardingGoal.values) {
           for (final activity in ActivityLevel.values) {
            final t = _suggest(
              _answers(
                weight: weight,
                height: height,
                birthYear: year,
                sex: sex,
                goal: goal,
                activity: activity,
              ),
            );
            final reason = '$weight kg, $height cm, $year, $sex, $goal';
            expect(t.calories, inInclusiveRange(TargetLimits.caloriesMin, TargetLimits.caloriesMax), reason: reason);
            expect(t.proteinG, inInclusiveRange(TargetLimits.proteinMin, TargetLimits.proteinMax), reason: reason);
            expect(t.carbsG, inInclusiveRange(TargetLimits.carbsMin, TargetLimits.carbsMax), reason: reason);
            expect(t.fatG, inInclusiveRange(TargetLimits.fatMin, TargetLimits.fatMax), reason: reason);
            expect(t.steps, inInclusiveRange(TargetLimits.stepsMin, TargetLimits.stepsMax), reason: reason);
            expect(t.sleepMinutes, inInclusiveRange(TargetLimits.sleepMin, TargetLimits.sleepMax), reason: reason);
           }
          }
        }
      }
    });

    test('OnboardingTargets eşitliği değer üzerinden', () {
      expect(_suggest(_answers()), _suggest(_answers()));
      expect(
        _suggest(_answers()) == _suggest(_answers(goal: OnboardingGoal.gain)),
        isFalse,
      );
    });
  });

  group('VKİ ve hedef kilo önerisi', () {
    test('VKİ = kg / m²', () {
      expect(bodyMassIndex(weightKg: 80, heightCm: 180), closeTo(24.69, 0.01));
      expect(bodyMassIndex(weightKg: 45, heightCm: 150), 20);
      expect(() => bodyMassIndex(weightKg: 0, heightCm: 180),
          throwsArgumentError);
      expect(() => bodyMassIndex(weightKg: 70, heightCm: 0),
          throwsArgumentError);
    });

    test('VKİ sınıfları', () {
      expect(bmiCategory(18.4), 'Zayıf');
      expect(bmiCategory(18.5), 'Normal');
      expect(bmiCategory(24.9), 'Normal');
      expect(bmiCategory(25), 'Fazla kilolu');
      expect(bmiCategory(30), 'Obez');
    });

    test('sağlıklı aralıktaysa mevcut kilo, değilse en yakın sınır', () {
      expect(
          GoalSuggestion.suggestTargetWeight(weightKg: 72, heightCm: 180), 72);
      // 24,9 x 1,8² = 80,676 -> 80,7.
      expect(
          GoalSuggestion.suggestTargetWeight(weightKg: 100, heightCm: 180),
          80.7);
      // 18,5 x 1,6² = 47,36 -> 47,4.
      expect(
          GoalSuggestion.suggestTargetWeight(weightKg: 40, heightCm: 160), 47.4);
    });

    test('öneri her zaman kilo sınırları içinde (30–250)', () {
      expect(
          GoalSuggestion.suggestTargetWeight(weightKg: 30, heightCm: 100), 30);
      expect(
          GoalSuggestion.suggestTargetWeight(weightKg: 250, heightCm: 250),
          155.6);
    });
  });

  group('TargetLimits.parse', () {
    test('aralıktaki tam sayıyı verir, dışını ve bozuğu null yapar', () {
      expect(TargetLimits.parse(' 2000 ', 800, 6000), 2000);
      expect(TargetLimits.parse('800', 800, 6000), 800);
      expect(TargetLimits.parse('6000', 800, 6000), 6000);
      for (final bad in <String?>[null, '', 'abc', '799', '6001', '12.5', '-1']) {
        expect(TargetLimits.parse(bad, 800, 6000), isNull, reason: '$bad');
      }
    });
  });

  group('OnboardingValidators', () {
    test('görünen ad: boş olamaz, en çok 60 karakter', () {
      expect(OnboardingValidators.displayName(null), isNotNull);
      expect(OnboardingValidators.displayName('   '), isNotNull);
      expect(OnboardingValidators.displayName('Ayşe'), isNull);
      expect(OnboardingValidators.displayName('a' * 60), isNull);
      expect(OnboardingValidators.displayName('a' * 61), isNotNull);
    });

    test('boy 100–250', () {
      expect(OnboardingValidators.height('99'), isNotNull);
      expect(OnboardingValidators.height('100'), isNull);
      expect(OnboardingValidators.height('250'), isNull);
      expect(OnboardingValidators.height('251'), isNotNull);
      expect(OnboardingValidators.height(''), isNotNull);
      expect(OnboardingValidators.height('1,8'), isNotNull);
    });

    test('doğum yılı isteğe bağlı, 1900 – (bu yıl − 13)', () {
      String? check(String v) =>
          OnboardingValidators.birthYear(v, nowYear: 2026);
      expect(check('1899'), isNotNull);
      expect(check('1900'), isNull);
      expect(check('2013'), isNull);
      expect(check('2014'), OnboardingValidators.underAgeMessage);
      expect(check(''), isNull);
    });

    test('kilo 30–250, virgül kabul; hedef kilo boş olabilir', () {
      expect(OnboardingValidators.weight('29,9'), isNotNull);
      expect(OnboardingValidators.weight('30'), isNull);
      expect(OnboardingValidators.weight('84,5'), isNull);
      expect(OnboardingValidators.weight('84.5'), isNull);
      expect(OnboardingValidators.weight('250'), isNull);
      expect(OnboardingValidators.weight('250,1'), isNotNull);
      expect(OnboardingValidators.weight('abc'), isNotNull);
      expect(OnboardingValidators.weight('NaN'), isNotNull);
      expect(OnboardingValidators.targetWeight(''), isNull);
      expect(OnboardingValidators.targetWeight('  '), isNull);
      expect(OnboardingValidators.targetWeight('20'), isNotNull);
      expect(OnboardingValidators.targetWeight('78'), isNull);
    });

    test('iş tanımı en çok 500 karakter, boş olabilir', () {
      expect(OnboardingValidators.workDescription(''), isNull);
      expect(OnboardingValidators.workDescription('b' * 500), isNull);
      expect(OnboardingValidators.workDescription('b' * 501), isNotNull);
    });
  });

  group('OnboardingAnswers.tryParse', () {
    OnboardingAnswers? parse({
      String name = ' Ayşe ',
      String height = '180',
      String birthYear = '1990',
      Sex? sex = Sex.female,
      String weight = '84,5',
      String target = '78',
      OnboardingGoal? goal = OnboardingGoal.lose,
      String work = '',
    }) =>
        OnboardingAnswers.tryParse(
          displayName: name,
          height: height,
          birthYear: birthYear,
          sex: sex,
          weight: weight,
          targetWeight: target,
          goal: goal,
          workDescription: work,
          nowYear: 2026,
        );

    test('geçerli girdi: ad kırpılır, virgüllü kilo okunur, iş tanımı boşsa null',
        () {
      final a = parse()!;
      expect(a.displayName, 'Ayşe');
      expect(a.heightCm, 180);
      expect(a.birthYear, 1990);
      expect(a.sex, Sex.female);
      expect(a.weightKg, 84.5);
      expect(a.targetWeightKg, 78);
      expect(a.goal, OnboardingGoal.lose);
      expect(a.workDescription, isNull);
    });

    test('iş tanımı kırpılır ve doluysa korunur', () {
      expect(parse(work: '  Mimarım.  ')!.workDescription, 'Mimarım.');
    });

    test('hedef kilo boşsa mevcut kiloya eşit; kilolar iki ondalığa yuvarlanır',
        () {
      final a = parse(weight: '84,456', target: '')!;
      expect(a.weightKg, 84.46);
      expect(a.targetWeightKg, 84.46);
    });

    test('cinsiyet seçilmemişse belirtilmemiş, amaç seçilmemişse koru sayılır',
        () {
      expect(parse(sex: null)!.sex, Sex.unspecified);
      expect(parse(goal: null)!.goal, OnboardingGoal.maintain);
      expect(parse()!.activity, ActivityLevel.light);
    });

    test('geçersiz alan null döndürür', () {
      expect(parse(name: ' '), isNull);
      expect(parse(height: '50'), isNull);
      expect(parse(birthYear: '2025'), isNull);
      expect(parse(weight: ''), isNull);
      expect(parse(target: '5'), isNull);
      expect(parse(work: 'x' * 501), isNull);
    });

    test('targetsSignature: hesabı etkileyen cevaplarla değişir, adla değişmez',
        () {
      final base = parse()!.targetsSignature;
      expect(parse(name: 'Veli')!.targetsSignature, base);
      expect(parse(work: 'Mimar')!.targetsSignature, base);
      expect(parse(target: '70')!.targetsSignature, base);
      expect(parse(weight: '90')!.targetsSignature, isNot(base));
      expect(parse(height: '170')!.targetsSignature, isNot(base));
      expect(parse(birthYear: '1991')!.targetsSignature, isNot(base));
      expect(parse(sex: Sex.male)!.targetsSignature, isNot(base));
      expect(parse(goal: OnboardingGoal.gain)!.targetsSignature, isNot(base));
      expect(
        OnboardingAnswers.tryParse(
          displayName: 'Ayşe',
          height: '180',
          birthYear: '1990',
          sex: Sex.female,
          weight: '84,5',
          targetWeight: '78',
          goal: OnboardingGoal.lose,
          workDescription: '',
          nowYear: 2026,
          activity: ActivityLevel.active,
        )!
            .targetsSignature,
        isNot(base),
      );
    });
  });
}
