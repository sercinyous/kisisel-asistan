import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/templates/routine_templates.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_op_key_store.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_repository.dart';
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
        'activity_level': 'light',
      });
    });

    test('hareket düzeyi ve saat dilimi sonuca ve RPC gövdesine girer', () {
      final result = buildOnboardingResult(
        base: const UserSettings.defaults(),
        answers: OnboardingAnswers(
          displayName: 'Ayşe',
          heightCm: 168,
          birthYear: 1992,
          sex: Sex.female,
          weightKg: 70.5,
          targetWeightKg: 65,
          goal: OnboardingGoal.lose,
          activity: ActivityLevel.veryActive,
        ),
        targets: _targets,
        preferences: const OnboardingPreferences(),
        routines: const [],
        now: _now,
        timezone: 'Europe/Berlin',
      );
      expect(result.settings.activityLevel, ActivityLevel.veryActive);
      final payload = onboardingPayload(result);
      expect(payload['timezone'], 'Europe/Berlin');
      expect((payload['settings'] as Map)['activity_level'], 'very_active');
      expect(
        onboardingPayload(_build()).containsKey('timezone'),
        isFalse,
        reason: 'saat dilimi verilmezse gövdeye girmez (sunucu değeri korunur)',
      );
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

  group('OnboardingWriter: tek RPC, işlem anahtarı', () {
    test('gövde: tartı, rutinler ve onboarded_at dolu ayar satırı', () {
      final payload = onboardingPayload(_build());
      expect(payload['weight_kg'], 70.5);
      expect(
        [for (final r in payload['routines'] as List) (r as Map)['title']],
        ['Yürüyüş yap', 'Kirayı öde'],
      );
      expect((payload['settings'] as Map)['onboarded_at'], isNotNull);
    });

    test('başarıda anahtar silinir; sonraki kurulum yeni anahtar alır',
        () async {
      final calls = <String>[];
      var n = 0;
      final keys = OnboardingOpKeyStore(
        scope: 'u',
        open: () async => throw StateError('depo yok'),
        newKey: () => 'k${n++}',
      );
      final writer = OnboardingWriter(
        repository: _RecordingRepository(calls),
        keys: keys,
      );
      final saved = await writer.complete(_build());
      expect(saved.onboardedAt, isNotNull);
      await writer.complete(_build());
      expect(calls, ['k0', 'k1']);
    });

    test('hata sonrası yeniden deneme aynı anahtarı kullanır', () async {
      final calls = <String>[];
      final repo = _RecordingRepository(calls)..failNext = true;
      final keys = OnboardingOpKeyStore(
        scope: 'u',
        open: () async => throw StateError('depo yok'),
      );
      final writer = OnboardingWriter(repository: repo, keys: keys);
      await expectLater(writer.complete(_build()), throwsStateError);
      await writer.complete(_build());
      expect(calls, hasLength(2));
      expect(calls.first, calls.last);
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                r'[0-9a-f]{12}$')
            .hasMatch(calls.first),
        isTrue,
      );
    });
  });
}

class _RecordingRepository implements OnboardingRepository {
  _RecordingRepository(this.calls);

  final List<String> calls;
  bool failNext = false;

  @override
  Future<UserSettings> complete(
    Map<String, dynamic> payload,
    String opKey,
  ) async {
    calls.add(opKey);
    if (failNext) {
      failNext = false;
      throw StateError('ağ yok');
    }
    return UserSettings.fromMap(
      Map<String, dynamic>.from(payload['settings'] as Map),
    );
  }
}
