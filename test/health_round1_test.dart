import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/demo/demo_health_extras.dart';
import 'package:kisisel_asistan/features/health/data/apple_workouts.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/fat_loss_rate.dart';
import 'package:kisisel_asistan/features/health/domain/streaks.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/health/presentation/water_providers.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

class _SlowWater extends FakeWaterRepository {
  @override
  Future<WaterLog> add(DateTime day, int ml) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.add(day, ml);
  }
}

void main() {
  test('su: art arda hızlı eklemeler kaybolmaz', () async {
    final repo = _SlowWater();
    final c = ProviderContainer(
        overrides: [waterRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await c.read(waterTodayProvider.future);
    final n = c.read(waterTodayProvider.notifier);
    await Future.wait([n.add(250), n.add(250), n.add(250)]);
    final state = c.read(waterTodayProvider).value!;
    final server = await repo.fetchDay(state.day);
    expect(state.totalMl, 750);
    expect(server.fold<int>(0, (s, l) => s + l.ml), 750);
    await Future.wait([n.undo(), n.add(500)]);
    final after = c.read(waterTodayProvider).value!;
    final serverAfter = await repo.fetchDay(after.day);
    expect(after.totalMl, serverAfter.fold<int>(0, (s, l) => s + l.ml));
    expect(after.totalMl, 1000);
  });

  test('gün harcaması: saatsiz iPhone, plan hedefinde yenen gün açık günü',
      () {
    // 84 kg, 178 cm, 34 yaş erkek; 8.000 adım, aktif 320 kcal.
    final basal =
        basalKcal(weightKg: 84, heightCm: 178, age: 34, sex: Sex.male);
    final plan = planExpenditure(basal: basal, activityFactor: 1.55).kcal;
    final target = plan - 550;
    final day = DateTime(2026, 11, 20);
    final exp = dayExpenditure(
      day: day,
      now: DateTime(2026, 11, 25),
      basal: basal,
      activeKcal: 320,
      steps: 8000,
    )!;
    expect(exp.kcal, greaterThan(target));
    final d = StreakDay(
      date: day,
      mealCount: 3,
      intakeKcal: target.toDouble(),
      expenditureKcal: exp.kcal,
    );
    final t = StreakTargets(dailySteps: 8000, kcalTarget: target, floorKcal: 1200);
    expect(isDeficitDay(d, t), isTrue);
  });

  test('0 kcal kayıtlar Kayıt gününe sayılmaz', () {
    final d = StreakDay(
        date: DateTime(2026, 11, 20), mealCount: 2, intakeKcal: 0);
    expect(isLoggingDay(d, StreakTargets(dailySteps: 8000, kcalTarget: 2000, floorKcal: 1200)),
        isFalse);
  });

  test('yaş doğum yılından: 18 görünen kullanıcı ihtiyatla kilitli', () {
    final r = resolveTargets(
      settings: const UserSettings.defaults().copyWith(
        weeklyRate: FatLossRate.half,
        expenditureKcalManual: 2800,
        startWeightKg: 80,
        targetWeightKg: 70,
        heightCm: 178,
      ),
      latestWeightKg: 80,
      age: 18,
      sex: Sex.male,
    );
    expect(r.mode, TargetsMode.locked);
  });

  test('Apple antrenmanı fitness_logs satırına çevrilir', () {
    final w = externalWorkoutFromApple(AppleWorkout(
      uuid: 'ABC-123',
      activityType: 'RUNNING',
      start: DateTime(2026, 11, 20, 7),
      end: DateTime(2026, 11, 20, 7, 42),
      kcal: 410,
      meters: 6230,
    ));
    expect(w.source, 'healthkit');
    expect(w.externalId, 'ABC-123');
    expect(w.workout.workoutType, 'running');
    expect(w.workout.durationMin, 42);
    expect(w.workout.distanceKm, 6.23);
    expect(w.workout.caloriesBurned, 410);
    expect(workoutTypeForApple('TRADITIONAL_STRENGTH_TRAINING'), 'weights');
    expect(workoutTypeForApple('YOGA'), 'other');
  });
}
