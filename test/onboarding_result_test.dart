import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/templates/routine_templates.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_writer.dart';
import 'package:kisisel_asistan/features/onboarding/domain/goal_suggestion.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_answers.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_result.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

OnboardingAnswers _answers({String? work = 'Mimarım.'}) => OnboardingAnswers(
      displayName: 'Ayşe',
      heightCm: 168,
      birthYear: 1992,
      sex: Sex.female,
      weightKg: 70.5,
      targetWeightKg: 65,
      goal: OnboardingGoal.lose,
      workDescription: work,
    );

const _targets = OnboardingTargets(
  calories: 1700,
  proteinG: 127,
  carbsG: 170,
  fatG: 51,
  steps: 9000,
  sleepMinutes: 480,
);

final _now = DateTime.utc(2026, 11, 17, 9, 30);

OnboardingResult _build({
  UserSettings? base,
  OnboardingAnswers? answers,
  OnboardingPreferences preferences = const OnboardingPreferences(),
  List<RoutineTemplate>? routines,
}) =>
    buildOnboardingResult(
      base: base ?? const UserSettings.defaults(),
      answers: answers ?? _answers(),
      targets: _targets,
      preferences: preferences,
      routines: routines ??
          [
            RoutineTemplates.byId('yuruyus')!,
            RoutineTemplates.byId('kira')!,
          ],
      now: _now,
    );

void main() {
  group('buildOnboardingResult: tek user_settings kaydı', () {
    test('cevaplar, hedefler ve kurulum anı tek kayıtta', () {
      final settings = _build().settings;
      expect(settings.toMap(), {
        ...const UserSettings.defaults().toMap(),
        'start_weight_kg': 70.5,
        'target_weight_kg': 65.0,
        'daily_calories': 1700,
        'daily_protein_g': 127,
        'daily_carbs_g': 170,
        'daily_fat_g': 51,
        'daily_steps': 9000,
        'sleep_minutes': 480,
        'height_cm': 168,
        'birth_year': 1992,
        'sex': 'female',
        'display_name': 'Ayşe',
        'work_description': 'Mimarım.',
        'onboarded_at': '2026-11-17T09:30:00.000Z',
      });
    });

    test('cinsiyet veritabanı değeri olarak yazılır', () {
      for (final sex in Sex.values) {
        final a = OnboardingAnswers(
          displayName: 'A',
          heightCm: 170,
          birthYear: 1990,
          sex: sex,
          weightKg: 70,
          targetWeightKg: 70,
          goal: OnboardingGoal.maintain,
        );
        expect(_build(answers: a).settings.sex, sex.name);
        expect(UserSettings.sexValues, contains(sex.name));
      }
    });

    test('sonuç UserSettings.fromMap ile geri okunur (profil tamam, kurulum bitti)',
        () {
      final back = UserSettings.fromMap(_build().settings.toMap());
      expect(back.profileComplete, isTrue);
      expect(back.isOnboarded, isTrue);
      expect(back.displayName, 'Ayşe');
      expect(back.onboardedAt!.toUtc(), _now);
    });

    test('iş tanımı boşsa eski değer silinir (null yazılır)', () {
      final base = const UserSettings.defaults().copyWith(workDescription: 'Eski');
      final settings = _build(base: base, answers: _answers(work: null)).settings;
      expect(settings.workDescription, isNull);
      expect(settings.toMap()['work_description'], isNull);
    });

    test('sorulmayan alanlar mevcut satırdan korunur', () {
      final base = const UserSettings.defaults().copyWith(
        teamMembers: ['Ali'],
        monthlyLeadDays: 5,
        eventRemindMinutes: 60,
        routineNotifications: false,
      );
      final s = _build(base: base).settings;
      expect(s.teamMembers, ['Ali']);
      expect(s.monthlyLeadDays, 5);
      expect(s.eventRemindMinutes, 60);
      expect(s.routineNotifications, isFalse);
    });

    test('bildirim ve sessiz saat tercihleri yazılır', () {
      final s = _build(
        preferences: const OnboardingPreferences(
          notificationsEnabled: false,
          quietHoursEnabled: false,
          quietStart: TimeOfDayValue(22, 15),
          quietEnd: TimeOfDayValue(6, 0),
        ),
      ).settings;
      expect(s.notificationsEnabled, isFalse);
      expect(s.quietHoursEnabled, isFalse);
      expect(s.quietStart, const TimeOfDayValue(22, 15));
      expect(s.quietEnd, const TimeOfDayValue(6, 0));
    });

    test('varsayılan tercihler bildirim açık, sessiz saat 23:00–07:30', () {
      const p = OnboardingPreferences();
      expect(p.notificationsEnabled, isTrue);
      expect(p.quietHoursEnabled, isTrue);
      expect(p.quietStart, const TimeOfDayValue(23, 0));
      expect(p.quietEnd, const TimeOfDayValue(7, 30));
    });
  });

  group('buildOnboardingResult: rutinler ve tartı', () {
    test('seçilen rutinler sıra numaralı kişisel taslak olur', () {
      final r = _build();
      expect(r.routines, hasLength(2));
      expect(r.routines[0].title, 'Yürüyüş yap');
      expect(r.routines[0].sortOrder, 0);
      expect(r.routines[0].scope, Routine.scopePersonal);
      expect(r.routines[0].id, isEmpty);
      expect(r.routines[1].title, 'Kirayı öde');
      expect(r.routines[1].sortOrder, 1);
      expect(r.routines[1].isMonthly, isTrue);
      expect(r.routines[1].dayOfMonth, 1);
    });

    test('hiç rutin seçilmezse boş başlanır', () {
      expect(_build(routines: const []).routines, isEmpty);
    });

    test('kilo cevabı tartı kaydı olacak kilodur', () {
      expect(_build().weightKg, 70.5);
    });
  });

  group('OnboardingWriter', () {
    late List<String> log;
    late List<Routine> created;
    late OnboardingWriter writer;
    Object? weightError;
    Object? routineError;
    Object? settingsError;

    setUp(() {
      log = [];
      created = [];
      weightError = null;
      routineError = null;
      settingsError = null;
      writer = OnboardingWriter(
        addWeight: (kg) async {
          if (weightError != null) throw weightError!;
          log.add('weight:$kg');
        },
        createRoutine: (routine) async {
          if (routineError != null) throw routineError!;
          created.add(routine);
          log.add('routine:${routine.title}');
        },
        saveSettings: (settings) async {
          if (settingsError != null) throw settingsError!;
          log.add('settings');
          return settings;
        },
      );
    });

    test('sıra: tartı, rutinler, en son tek ayar kaydı', () async {
      final result = _build();
      final saved = await writer.complete(result);
      expect(log, ['weight:70.5', 'routine:Yürüyüş yap', 'routine:Kirayı öde', 'settings']);
      expect(saved.onboardedAt, isNotNull);
    });

    test('ayar kaydı başarısızsa kurulum bitmiş sayılmaz; yeniden denemede '
        'tartı ve rutinler tekrarlanmaz', () async {
      final result = _build();
      settingsError = StateError('ağ yok');
      await expectLater(writer.complete(result), throwsStateError);
      expect(log, ['weight:70.5', 'routine:Yürüyüş yap', 'routine:Kirayı öde']);

      settingsError = null;
      await writer.complete(result);
      expect(
        log,
        ['weight:70.5', 'routine:Yürüyüş yap', 'routine:Kirayı öde', 'settings'],
      );
      expect(created, hasLength(2));
    });

    test('tartı başarısızsa hiçbir şey yazılmaz ve ayar kaydına geçilmez',
        () async {
      weightError = StateError('hata');
      await expectLater(writer.complete(_build()), throwsStateError);
      expect(log, isEmpty);
    });

    test('rutin yazımı yarıda kesilirse yeniden denemede kalandan sürer',
        () async {
      final result = _build();
      var calls = 0;
      final flaky = OnboardingWriter(
        addWeight: (kg) async => log.add('weight'),
        createRoutine: (routine) async {
          calls++;
          if (calls == 2) throw StateError('ikinci rutin düştü');
          log.add('routine:${routine.title}');
        },
        saveSettings: (settings) async {
          log.add('settings');
          return settings;
        },
      );
      await expectLater(flaky.complete(result), throwsStateError);
      expect(log, ['weight', 'routine:Yürüyüş yap']);

      await flaky.complete(result);
      expect(log, [
        'weight',
        'routine:Yürüyüş yap',
        'routine:Kirayı öde',
        'settings',
      ]);
    });

    test('rutin seçilmediyse yalnızca tartı ve ayar yazılır', () async {
      await writer.complete(_build(routines: const []));
      expect(log, ['weight:70.5', 'settings']);
    });
  });
}
