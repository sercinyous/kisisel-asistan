import 'dart:math' as math;

import '../../../core/services/google_health_api.dart';
import '../../../core/services/health_service.dart';
import '../../../core/utils/date_utils.dart';
import 'health_repository.dart';

/// Google Health kaynağının bağlantı tarafı: erişim anahtarı, durum bildirimi
/// ve içe aktarma işareti. Uygulamada `GoogleConnectionController` uygular.
abstract interface class GoogleHealthLink {
  /// Derlemeye istemci kimliği verilmiş mi?
  bool get isConfigured;

  /// Etkileşimsiz erişim anahtarı; alınamazsa [GoogleHealthException].
  Future<String> accessToken();

  /// Okuma hatası (oturum, izin ya da geçici sorun).
  void reportFailure(GoogleHealthException error);

  /// Başarılı okuma anı.
  void reportSynced(DateTime at);

  /// İçe aktarılan son antrenmanın Google'daki oluşturulma anı.
  DateTime? get exerciseWatermark;

  Future<void> saveExerciseWatermark(DateTime value);
}

/// Google Health hatasının kartlarda gösterilen sağlık durumu.
HealthStatus healthStatusForGoogleError(GoogleHealthErrorKind kind) =>
    switch (kind) {
      GoogleHealthErrorKind.notConfigured => HealthStatus.unavailable,
      GoogleHealthErrorKind.notConnected => HealthStatus.notConnected,
      GoogleHealthErrorKind.reconnect ||
      GoogleHealthErrorKind.missingScope =>
        HealthStatus.reconnect,
      _ => HealthStatus.failed,
    };

/// Google kaynağının uygulamaya açılan yüzü; tarayıcı demosunun sahte
/// kaynağı da bunu uygular.
abstract interface class GoogleHealthReader implements HealthDataSource {
  /// Son [days] tamamlanmış gün ve bugünün antrenmanlarını içe aktarır;
  /// yazılmak üzere gönderilen ve kullanıcının kendi kaydıyla çiftlendiği için
  /// silinen kayıtların toplamını döndürür (0: günlük değişmedi).
  ///
  /// [ownerId] verilirse yazmalar o kullanıcıyla yapılır (oturum başka
  /// kullanıcıya geçtiyse yazılmaz); [isValid] her `await` sonrasında
  /// denetlenir, `false` dönerse işlem yazmadan (işaret de ilerlemeden) durur.
  Future<int> importWorkouts(
    HealthRepository repository, {
    int days = HealthService.backfillDays,
    DateTime? now,
    String? ownerId,
    bool Function()? isValid,
  });
}

/// Google Health (Fitbit) okuma katmanı. Pencereler HealthKit yoluyla
/// aynıdır ([healthDayWindows]): adım ve aktif kalori yerel takvim günü
/// (`dailyRollUp`), uyku önceki gün 18:00 → o gün 18:00 penceresindeki
/// uyku evrelerinin birleşimi.
class GoogleHealthSource implements GoogleHealthReader {
  GoogleHealthSource({required this.link, required this.api});

  final GoogleHealthLink link;
  final GoogleHealthApi api;

  /// İçe aktarılan antrenmanların `fitness_logs.source` değeri.
  static const String workoutSource = WorkoutLog.googleSource;

  @override
  Future<HealthSnapshot> readToday({DateTime? now}) async {
    if (!link.isConfigured) {
      return _failure(
        const GoogleHealthException(GoogleHealthErrorKind.notConfigured),
      );
    }
    final current = now ?? DateTime.now();
    try {
      final readings =
          await _read(healthDayWindows(current, pastDays: 0), current);
      link.reportSynced(current);
      return readings.single.snapshot;
    } on GoogleHealthException catch (error) {
      link.reportFailure(error);
      return _failure(error);
    }
  }

  @override
  Future<List<HealthDayReading>> readPastDays({
    int days = HealthService.backfillDays,
    DateTime? now,
  }) async {
    if (!link.isConfigured || days <= 0) return const [];
    final current = now ?? DateTime.now();
    final windows = healthDayWindows(current, pastDays: days);
    try {
      // Son pencere bugündür; onu readToday okur.
      return await _read(windows.take(windows.length - 1).toList(), current);
    } on GoogleHealthException catch (error) {
      link.reportFailure(error);
      return const [];
    }
  }

  /// Son [days] tamamlanmış gün ve bugünün antrenmanlarını `fitness_logs`'a
  /// aktarır. Daha önce aktarılanlar (Google'daki oluşturulma anı işaretten
  /// eski) atlanır; kullanıcı aktarılan bir kaydı silerse geri gelmez. Aynı
  /// kayıt ikinci kez gelse de veritabanı dizini kopyayı reddeder.
  ///
  /// Günlük kullanıcının kendi kayıtlarıyla (elle, AI hızlı ekleme) uzlaştırılır:
  /// - Antrenman sayılmayan oturumlar ([isImportableExercise]: ev işi, bahçe,
  ///   meditasyon, düz yürüyüş, 10 dk'dan kısa kayıtlar) aktarılmaz; yoksa
  ///   planlı spor gününü "yapıldı" gösterir ve raporlara sayılırlardı.
  /// - Kullanıcının kendi kaydıyla aynı oturum olan Google antrenmanı
  ///   ([WorkoutLog.isSameSessionAs]) aktarılmaz; Google'dan daha önce
  ///   aktarılmış bir kopya sonradan elle/AI kaydıyla çiftlenmişse silinir.
  ///   Kullanıcının kendi kaydı her zaman kalır.
  /// İşaret, atlananlar dahil Google'ın döndürdüğü her kayda göre ilerler;
  /// böylece atlanan oturumlar her eşitlemede yeniden değerlendirilmez.
  /// Döndürülen sayı yazılmak üzere gönderilen ve silinen kayıtların toplamıdır.
  @override
  Future<int> importWorkouts(
    HealthRepository repository, {
    int days = HealthService.backfillDays,
    DateTime? now,
    String? ownerId,
    bool Function()? isValid,
  }) async {
    if (!link.isConfigured) return 0;
    final owner = ownerId ?? repository.currentUserId;
    bool stale() =>
        !(isValid?.call() ?? true) || repository.currentUserId != owner;
    final today = AppDates.startOfDay(now ?? DateTime.now());
    final from = AppDates.addDays(today, -days);
    final to = AppDates.addDays(today, 1);
    final List<GoogleExercise> exercises;
    try {
      exercises = await api.exercises(fromDay: from, toDay: to);
    } on GoogleHealthException catch (error) {
      link.reportFailure(error);
      return 0;
    }
    if (stale()) return 0;
    // Pencerenin iki ucunda gün sınırını aşan oturumlar da eşleşsin diye
    // okuma bir gün geniş tutulur. Okunamazsa hiçbir şey yazılmaz (kopya
    // riski) ve işaret ilerlemez; sonraki eşitleme yeniden dener.
    final existing = await repository.fetchWorkouts(
      AppDates.addDays(from, -1),
      AppDates.addDays(to, 1),
    );
    final own = [
      for (final w in existing)
        if (!w.isFromGoogle) w
    ];
    final duplicates = [
      for (final w in existing)
        if (w.isFromGoogle && own.any(w.isSameSessionAs)) w,
    ];
    if (stale()) return 0;
    for (final duplicate in duplicates) {
      if (stale()) return 0;
      await repository.deleteWorkout(duplicate.id);
    }
    if (stale()) return 0;

    final watermark = link.exerciseWatermark;
    final fresh = <ExternalWorkout>[];
    for (final exercise in exercises) {
      final created = exercise.createTime;
      final seen =
          watermark != null && created != null && !created.isAfter(watermark);
      if (seen || !isImportableExercise(exercise)) continue;
      final item = externalWorkoutFromGoogle(exercise);
      if (own.any(item.workout.isSameSessionAs)) continue;
      fresh.add(item);
    }
    if (stale() || owner == null) return 0;
    await repository.importExternalWorkouts(fresh, ownerId: owner);
    if (stale()) return 0;

    DateTime? newest = watermark;
    for (final exercise in exercises) {
      final created = exercise.createTime;
      if (created != null && (newest == null || created.isAfter(newest))) {
        newest = created;
      }
    }
    if (newest != null && newest != watermark) {
      await link.saveExerciseWatermark(newest);
    }
    return fresh.length + duplicates.length;
  }

  Future<List<HealthDayReading>> _read(
    List<HealthDayWindow> windows,
    DateTime readAt,
  ) async {
    if (windows.isEmpty) return const [];
    final from = windows.first.day;
    final to = windows.last.end;
    final stepsFuture = api.dailySteps(from: from, to: to);
    final kcalFuture = api.dailyActiveKcal(from: from, to: to);
    // Uyku yalnızca bitiş anıyla süzülür: pencereye taşan oturumlar da gelsin
    // diye üst sınır bir gün geniş tutulur, fazlası kırpılınca sıfırlanır.
    final sleepFuture = api.sleepSessions(
      endFrom: windows.first.sleepStart,
      endTo: windows.last.sleepEnd.add(const Duration(days: 1)),
    );
    // Paralel okuma; ilk hata özgün türüyle iletilir, diğerleri sahipsiz kalmaz.
    await Future.wait<Object>([stepsFuture, kcalFuture, sleepFuture]);
    final steps = await stepsFuture;
    final kcal = await kcalFuture;
    final asleep = [
      for (final session in await sleepFuture) ...session.asleep,
    ];

    return [
      for (final window in windows)
        (
          day: window.day,
          snapshot: HealthSnapshot(
            status: HealthStatus.ok,
            steps: steps[window.day] ?? 0,
            activeKcal: (kcal[window.day] ?? 0).round(),
            sleepMinutes: sleepMinutesInWindow(
              asleep,
              window.sleepStart,
              window.sleepEnd,
            ),
            readAt: readAt,
            source: HealthSourceKind.googleHealth,
          ),
        ),
    ];
  }

  static HealthSnapshot _failure(GoogleHealthException error) => HealthSnapshot(
        status: healthStatusForGoogleError(error.kind),
        source: HealthSourceKind.googleHealth,
        message: error.message,
      );
}

/// Antrenman günlüğüne alınmayan Google egzersiz türleri: ev işi, bahçe ve
/// tamir işleri, meditasyon ve hobi etkinlikleri sporda sayılmaz. Düz yürüyüş
/// de dışarıda kalır (adım sayısında zaten vardır); 'other' olarak girip
/// planlı bir spor gününü yanlışlıkla "yapıldı" gösterirdi. Daha çaba isteyen
/// yürüyüş türleri (HIKING, POWER_WALKING, NORDIC_WALKING …) alınır.
const Set<String> nonWorkoutExerciseTypes = {
  'CLEANING',
  'GARDENING',
  'HOUSEHOLD_CHORES',
  'HOEING',
  'WEEDING',
  'MOWING_LAWN',
  'SHOVELING',
  'CARPENTRY',
  'PAINTING',
  'MEDITATE',
  'FISHING',
  'HUNTING',
  'BILLIARDS',
  'MUSICAL_PERFORMANCE',
  'WALKING',
  'STROLLER_WALK',
};

/// Bundan kısa oturumlar (cihazın otomatik algıladığı kısa hareketler)
/// antrenman sayılmaz.
const int minImportedWorkoutMinutes = 10;

/// [exercise] antrenman günlüğüne aktarılır mı? Türü antrenman sayılıyor ve
/// süresi en az [minImportedWorkoutMinutes] olmalı.
bool isImportableExercise(GoogleExercise exercise) {
  if (nonWorkoutExerciseTypes.contains(exercise.exerciseType.toUpperCase())) {
    return false;
  }
  final duration =
      exercise.activeDuration ?? exercise.end.difference(exercise.start);
  return duration.inMinutes >= minImportedWorkoutMinutes;
}

/// Google antrenman türünü uygulamanın türüne çevirir
/// ([WorkoutLog.workoutTypes]); eşleşmeyen her şey 'other'.
String workoutTypeForGoogle(String exerciseType) =>
    switch (exerciseType.toUpperCase()) {
      'WEIGHTS' ||
      'WEIGHTLIFTING' ||
      'FREE_WEIGHTS' ||
      'WEIGHT_MACHINES' ||
      'STRENGTH_TRAINING' ||
      'FUNCTIONAL_STRENGTH_TRAINING' ||
      'POWERLIFTING' ||
      'BODY_WEIGHT' ||
      'CALISTHENICS' ||
      'CROSSFIT' ||
      'RESISTANCE_BANDS' ||
      'CORE_TRAINING' =>
        'weights',
      'KICKBOXING' ||
      'BOXING' ||
      'MUAY_THAI' ||
      'MARTIAL_ARTS' ||
      'KARATE' ||
      'TAEKWONDO' ||
      'JIU_JITSU' ||
      'WRESTLING' =>
        'kickboxing',
      'RUNNING' || 'TRAIL_RUN' || 'TREADMILL' || 'INCLINE_RUN' => 'running',
      'SOCCER' => 'football',
      _ => 'other',
    };

/// Google antrenmanını `fitness_logs` satırına çevirir. Değerler veritabanı
/// sınırlarına sıkıştırılır (süre 1–600 dk, mesafe ≤ 9999,99 km); sıfır ya
/// da bilinmeyen değer boş bırakılır.
ExternalWorkout externalWorkoutFromGoogle(GoogleExercise exercise) {
  final duration =
      exercise.activeDuration ?? exercise.end.difference(exercise.start);
  final minutes = (duration.inSeconds / 60).round();
  final km = exercise.distanceMeters == null
      ? null
      : (exercise.distanceMeters! / 10).round() / 100;
  final kcal = exercise.caloriesKcal?.round();
  final title = exercise.displayName?.trim();
  final notes = exercise.notes?.trim();
  final externalId = exercise.id.length > ExternalWorkout.externalIdMaxLength
      ? exercise.id.substring(0, ExternalWorkout.externalIdMaxLength)
      : exercise.id;
  return ExternalWorkout(
    source: GoogleHealthSource.workoutSource,
    externalId: externalId,
    workout: WorkoutLog(
      id: '',
      loggedAt: exercise.start.toLocal(),
      workoutType: workoutTypeForGoogle(exercise.exerciseType),
      title: title == null || title.isEmpty
          ? null
          : title.substring(0, math.min(title.length, 120)),
      durationMin: minutes < WorkoutLog.durationMinMin
          ? null
          : math.min(minutes, WorkoutLog.durationMinMax),
      distanceKm:
          km == null || km <= 0 ? null : math.min(km, WorkoutLog.distanceKmMax),
      caloriesBurned: kcal == null || kcal <= 0 ? null : kcal,
      notes: notes == null || notes.isEmpty ? null : notes,
      source: GoogleHealthSource.workoutSource,
    ),
  );
}
