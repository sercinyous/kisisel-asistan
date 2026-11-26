import 'dart:math' as math;

import '../../../core/services/health_service.dart';
import 'health_repository.dart';

/// Apple Sağlık antrenmanlarının `fitness_logs.source` değeri.
const String appleWorkoutSource = 'healthkit';

/// `HealthWorkoutActivityType` adını uygulamadaki antrenman türüne çevirir.
String workoutTypeForApple(String activityType) =>
    switch (activityType.toUpperCase()) {
      'TRADITIONAL_STRENGTH_TRAINING' ||
      'FUNCTIONAL_STRENGTH_TRAINING' ||
      'CORE_TRAINING' ||
      'CROSS_TRAINING' ||
      'HIGH_INTENSITY_INTERVAL_TRAINING' =>
        'weights',
      'KICKBOXING' || 'BOXING' || 'MARTIAL_ARTS' || 'WRESTLING' =>
        'kickboxing',
      'RUNNING' || 'RUNNING_TREADMILL' => 'running',
      'SOCCER' => 'football',
      _ => 'other',
    };

/// Apple antrenmanını `fitness_logs` satırına çevirir; değerler veritabanı
/// sınırlarına sıkıştırılır, sıfır ya da bilinmeyen değer boş bırakılır.
ExternalWorkout externalWorkoutFromApple(AppleWorkout w) {
  final minutes = (w.end.difference(w.start).inSeconds / 60).round();
  final km = w.meters == null ? null : (w.meters! / 10).round() / 100;
  final id = w.uuid.length > ExternalWorkout.externalIdMaxLength
      ? w.uuid.substring(0, ExternalWorkout.externalIdMaxLength)
      : w.uuid;
  return ExternalWorkout(
    source: appleWorkoutSource,
    externalId: id,
    workout: WorkoutLog(
      id: '',
      loggedAt: w.start.toLocal(),
      workoutType: workoutTypeForApple(w.activityType),
      durationMin: minutes < WorkoutLog.durationMinMin
          ? null
          : math.min(minutes, WorkoutLog.durationMinMax),
      distanceKm:
          km == null || km <= 0 ? null : math.min(km, WorkoutLog.distanceKmMax),
      caloriesBurned: w.kcal == null || w.kcal! <= 0 ? null : w.kcal,
      source: appleWorkoutSource,
    ),
  );
}

/// Elle/AI ile girilmiş bir oturumla çakışmayan Apple antrenmanlarını yazar
/// (aynı uuid tekil dizinle bir kez yazılır). Yazılmak üzere gönderilen
/// kayıt sayısını döndürür.
Future<int> importAppleWorkouts(
  HealthRepository repository,
  List<AppleWorkout> workouts, {
  required String ownerId,
  bool Function()? isValid,
}) async {
  if (workouts.isEmpty) return 0;
  final items = [for (final w in workouts) externalWorkoutFromApple(w)];
  var from = items.first.workout.loggedAt;
  var to = from;
  for (final i in items) {
    if (i.workout.loggedAt.isBefore(from)) from = i.workout.loggedAt;
    if (i.workout.loggedAt.isAfter(to)) to = i.workout.loggedAt;
  }
  final existing = await repository.fetchWorkouts(
    from.subtract(const Duration(days: 1)),
    to.add(const Duration(days: 2)),
  );
  if (!(isValid?.call() ?? true)) return 0;
  final own = [
    for (final w in existing)
      if (w.source == 'manual' || w.source == 'ai') w,
  ];
  final fresh = [
    for (final i in items)
      if (!own.any(i.workout.isSameSessionAs)) i,
  ];
  await repository.importExternalWorkouts(fresh, ownerId: ownerId);
  return fresh.length;
}
