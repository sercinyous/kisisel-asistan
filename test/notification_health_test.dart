import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_health.dart';
import 'package:kisisel_asistan/core/services/notification_plan.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

// 2026-11-23 Pazartesi.
final DateTime monday8 = DateTime(2026, 11, 23, 8);

UserSettings settings({
  bool quiet = false,
  TimeOfDayValue? quietStart,
  TimeOfDayValue? quietEnd,
  bool checkinReminder = true,
  int checkinWeekday = 1,
  bool notifications = true,
}) =>
    const UserSettings.defaults().copyWith(
      notificationsEnabled: notifications,
      quietHoursEnabled: quiet,
      quietStart: quietStart,
      quietEnd: quietEnd,
      checkinReminder: checkinReminder,
      checkinCadence: CheckinCadence.weekly,
      checkinWeekday: checkinWeekday,
    );

const HealthNudgeState idle = HealthNudgeState(mealsLoggedToday: false);

List<PlannedNotification> onDay(List<PlannedNotification> plan, int day) =>
    plan.where((p) => p.fireAt.day == day).toList();

void main() {
  test('bildirimler kapalıysa hiç dürtü yok', () {
    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(notifications: false),
      state: idle,
    );
    expect(plan, isEmpty);
  });

  test('ölçü günü 09:00, öğün 20:30; anahtarlar sabit', () {
    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(),
      state: idle,
    );
    final today = onDay(plan, 23);
    expect(today.map((p) => p.key), [
      'health:checkin:2026-11-23',
      'health:meals:2026-11-23',
    ]);
    expect(today.first.fireAt, DateTime(2026, 11, 23, 9));
    expect(today.first.body,
        'Bugün ölçü ve fotoğraf günü. Tartı, mezura, fotoğraf: ~3 dk.');
    expect(today.last.fireAt, DateTime(2026, 11, 23, 20, 30));
    expect(plan.every((p) => p.kind == PlannedKind.healthNudge), isTrue);
  });

  test('günde en fazla 2: öncelik ölçü > öğün > adım', () {
    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(),
      state: const HealthNudgeState(
        mealsLoggedToday: false,
        stepsToday: 6000,
        stepTarget: 8000,
      ),
    );
    final today = onDay(plan, 23);
    expect(today, hasLength(maxHealthNudgesPerDay));
    expect(today.map((p) => p.key).any((k) => k.contains('steps')), isFalse);
    for (var d = 23; d < 30; d++) {
      expect(onDay(plan, d).length, lessThanOrEqualTo(2));
    }
  });

  test('öğün kaydı varsa bugün öğün dürtüsü yok; okunamadıysa hiç yok', () {
    final logged = buildHealthNudgePlan(
      now: monday8,
      settings: settings(checkinReminder: false),
      state: const HealthNudgeState(mealsLoggedToday: true),
    );
    expect(onDay(logged, 23), isEmpty);
    expect(onDay(logged, 24).single.key, 'health:meals:2026-11-24');

    final unknown = buildHealthNudgePlan(
      now: monday8,
      settings: settings(checkinReminder: false),
      state: const HealthNudgeState(mealsLoggedToday: null),
    );
    expect(unknown.where((p) => p.key.contains('meals')), isEmpty);
  });

  test('adım: yalnızca %70+ ve 4.000 altı kalan, hedef bitmemiş', () {
    expect(stepsNudgeApplies(5600, 8000), isTrue);
    expect(stepsNudgeApplies(5599, 8000), isFalse);
    expect(stepsNudgeApplies(8000, 8000), isFalse);
    expect(stepsNudgeApplies(10500, 15000), isFalse, reason: '4.500 kaldı');
    expect(stepsNudgeApplies(null, 8000), isFalse);

    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(checkinReminder: false),
      state: const HealthNudgeState(
        mealsLoggedToday: true,
        stepsToday: 6000,
        stepTarget: 8000,
      ),
    );
    final steps = plan.singleWhere((p) => p.key.contains('steps'));
    expect(steps.fireAt, DateTime(2026, 11, 23, 19));
    expect(steps.body, contains('2.000 adım'));
  });

  test('kapatılan tür planlanmaz; ölçü günü checkin_reminder ile kapanır', () {
    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(checkinReminder: false),
      state: idle,
      disabled: {HealthNudgeKind.meals},
    );
    expect(plan, isEmpty);
  });

  test('ölçü bugün yapıldıysa ölçü dürtüsü yok', () {
    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(),
      state: const HealthNudgeState(
        mealsLoggedToday: true,
        checkinDoneToday: true,
      ),
    );
    expect(plan.where((p) => p.key.contains('checkin')), isEmpty);
  });

  test('geçmiş saat planlanmaz', () {
    final plan = buildHealthNudgePlan(
      now: DateTime(2026, 11, 23, 21),
      settings: settings(),
      state: idle,
    );
    expect(onDay(plan, 23), isEmpty);
  });

  test('sessiz saat: aynı gün bitişe kayar, gün dışına taşan atılır', () {
    final shifted = buildHealthNudgePlan(
      now: monday8,
      settings: settings(
        quiet: true,
        quietStart: const TimeOfDayValue(8, 0),
        quietEnd: const TimeOfDayValue(10, 0),
      ),
      state: const HealthNudgeState(mealsLoggedToday: true),
    );
    expect(onDay(shifted, 23).single.fireAt, DateTime(2026, 11, 23, 10));

    final dropped = buildHealthNudgePlan(
      now: monday8,
      settings: settings(
        checkinReminder: false,
        quiet: true,
        quietStart: const TimeOfDayValue(20, 0),
        quietEnd: const TimeOfDayValue(7, 0),
      ),
      state: idle,
    );
    expect(dropped, isEmpty, reason: '20:30 öğün dürtüsü gece kaymaz');
  });

  test('Pazar 21:00 haftalık özet metni', () {
    expect(
      weeklyNudgeBody(const HealthNudgeState(
        mealsLoggedToday: true,
        weekDeficitKcal: 3100,
        weekDeficitKg: 0.4,
        tasksDonePercent: 80,
      )),
      'Bu hafta −3.100 kcal (≈0,4 kg) · işlerin %80 tamam',
    );
    expect(
      weeklyNudgeBody(const HealthNudgeState(
        mealsLoggedToday: true,
        weekDeficitKcal: -200,
        tasksDonePercent: 60,
      )),
      'İşlerin %60 tamam',
      reason: 'açık yoksa suçlama yok',
    );
    expect(
      weeklyNudgeBody(const HealthNudgeState(
        mealsLoggedToday: true,
        weekDeficitKcal: -1400,
        weekSurplusGoal: true,
        tasksDonePercent: 60,
      )),
      'Bu hafta +1.400 kcal fazla · işlerin %60 tamam',
      reason: 'kas yapmada fazla özetlenir',
    );
    expect(
      weeklyNudgeBody(const HealthNudgeState(
        mealsLoggedToday: true,
        weekDeficitKcal: 900,
        weekSurplusGoal: true,
      )),
      isNull,
      reason: 'kas yapmada açık suçlanmaz',
    );
    expect(weeklyNudgeBody(idle), isNull);

    final plan = buildHealthNudgePlan(
      now: monday8,
      settings: settings(checkinReminder: false),
      state: const HealthNudgeState(
        mealsLoggedToday: true,
        weekDeficitKcal: 3100,
        tasksDonePercent: 80,
      ),
      disabled: {HealthNudgeKind.meals},
    );
    final weekly = plan.single;
    expect(weekly.key, 'health:weekly:2026-11-29');
    expect(weekly.fireAt, DateTime(2026, 11, 29, 21));
  });

  test('silme listesi dünden 7 gün ilerisine kadar her türü kapsar', () {
    final keys = healthNudgeKeysAround(monday8);
    expect(keys, contains('health:meals:2026-11-22'));
    expect(keys, contains('health:weekly:2026-11-29'));
    expect(keys, hasLength(8 * HealthNudgeKind.values.length));
  });
}
