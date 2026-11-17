import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/features/health/data/google_health_source.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';

import 'helpers/fakes.dart';

/// Bağlantı tarafının sahtesi: anahtar, bildirimler ve içe aktarma işareti.
class FakeLink implements GoogleHealthLink {
  bool configured = true;
  GoogleHealthException? tokenError;
  final List<GoogleHealthException> failures = [];
  final List<DateTime> synced = [];
  DateTime? watermark;
  int tokenCalls = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<String> accessToken() async {
    tokenCalls++;
    final error = tokenError;
    if (error != null) throw error;
    return 'tok';
  }

  @override
  void reportFailure(GoogleHealthException error) => failures.add(error);

  @override
  void reportSynced(DateTime at) => synced.add(at);

  @override
  DateTime? get exerciseWatermark => watermark;

  @override
  Future<void> saveExerciseWatermark(DateTime value) async => watermark = value;
}

String utc(DateTime local) => GoogleHealthApi.rfc3339(local);

Map<String, dynamic> stage(String type, DateTime from, DateTime to) =>
    {'type': type, 'startTime': utc(from), 'endTime': utc(to)};

Map<String, dynamic> sleepPoint(
  DateTime from,
  DateTime to, {
  List<Map<String, dynamic>> stages = const [],
}) =>
    {
      'sleep': {
        'interval': {'startTime': utc(from), 'endTime': utc(to)},
        if (stages.isNotEmpty) 'stages': stages,
      },
    };

Map<String, dynamic> exercisePoint(
  String id,
  String type,
  DateTime start,
  DateTime end, {
  String? duration,
  num? distanceMm,
  num? kcal,
  DateTime? created,
  String? name,
}) =>
    {
      'name': 'users/me/dataTypes/exercise/dataPoints/$id',
      'exercise': {
        'exerciseType': type,
        if (name != null) 'displayName': name,
        'interval': {'startTime': utc(start), 'endTime': utc(end)},
        if (duration != null) 'activeDuration': duration,
        'metricsSummary': {
          if (distanceMm != null) 'distanceMillimeters': distanceMm,
          if (kcal != null) 'caloriesKcal': kcal,
        },
        if (created != null) 'createTime': GoogleHealthApi.rfc3339(created),
      },
    };

/// Google Health API'nin bellekteki taklidi: günlük toplamlar, uyku ve
/// antrenman listeleri; dailyRollUp yalnızca istenen aralığın günlerini döner.
class FakeGoogleServer {
  Map<DateTime, int> steps = {};
  Map<DateTime, double> kcal = {};
  List<Map<String, dynamic>> sleep = [];
  List<Map<String, dynamic>> exercises = [];
  int? failStatus;
  final List<http.Request> requests = [];

  static http.Response ok(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Client client() => MockClient((request) async {
        requests.add(request);
        if (failStatus != null) return http.Response('', failStatus!);
        final path = request.url.path;
        if (path.endsWith(':dailyRollUp')) {
          final range = (jsonDecode(request.body) as Map)['range'] as Map;
          DateTime day(Map<dynamic, dynamic> civil) {
            final d = civil['date'] as Map;
            return DateTime(d['year'] as int, d['month'] as int, d['day'] as int);
          }

          final start = day(range['start'] as Map);
          final endMap = range['end'] as Map;
          final end = day(endMap);
          final inclusiveEnd = endMap['time'] != null;
          final isSteps = path.contains('/steps/');
          final source = isSteps ? steps : kcal;
          return ok({
              'rollupDataPoints': [
                for (final entry in source.entries)
                  if (!entry.key.isBefore(start) &&
                      (entry.key.isBefore(end) ||
                          (inclusiveEnd && entry.key == end)))
                    {
                      'civilStartTime': {
                        'date': {
                          'year': entry.key.year,
                          'month': entry.key.month,
                          'day': entry.key.day,
                        },
                      },
                      if (isSteps)
                        'steps': {'countSum': '${entry.value}'}
                      else
                        'activeEnergyBurned': {'kcalSum': entry.value},
                    },
              ],
            });
        }
        if (path.endsWith('/sleep/dataPoints')) {
          return ok({'dataPoints': sleep});
        }
        if (path.endsWith('/exercise/dataPoints')) {
          return ok({'dataPoints': exercises});
        }
        return http.Response('', 404);
      });
}

void main() {
  // Saat dilimi: testi çalıştıran makinenin yerel saati (pencereler yerel).
  final now = DateTime(2026, 11, 17, 14, 5);
  final d15 = DateTime(2026, 11, 15);
  final d16 = DateTime(2026, 11, 16);
  final d17 = DateTime(2026, 11, 17);
  late FakeLink link;
  late FakeGoogleServer server;
  late GoogleHealthSource source;

  setUp(() {
    link = FakeLink();
    server = FakeGoogleServer()
      ..steps = {d15: 9000, d16: 11000, d17: 4000}
      ..kcal = {d15: 300.4, d16: 500.6, d17: 120}
      ..sleep = [
        // 15→16 gecesi, gece yarısını geçen tek evreli uyku: 16'sına 480 dk.
        sleepPoint(
          DateTime(2026, 11, 15, 22),
          DateTime(2026, 11, 16, 6),
          stages: [
            stage('ASLEEP', DateTime(2026, 11, 15, 22), DateTime(2026, 11, 16, 6)),
          ],
        ),
        // 16'sı 17:30–18:30 şekerleme (evresiz): 18:00 sınırında bölünür,
        // 30 dk 16'sına, 30 dk 17'sine.
        sleepPoint(DateTime(2026, 11, 16, 17, 30), DateTime(2026, 11, 16, 18, 30)),
        // 16→17 gecesi, saat (evreli, uyanık bölümlü).
        sleepPoint(
          DateTime(2026, 11, 16, 23),
          DateTime(2026, 11, 17, 7),
          stages: [
            stage('AWAKE', DateTime(2026, 11, 16, 23), DateTime(2026, 11, 16, 23, 10)),
            stage('LIGHT', DateTime(2026, 11, 16, 23, 10), DateTime(2026, 11, 17, 2)),
            stage('AWAKE', DateTime(2026, 11, 17, 2), DateTime(2026, 11, 17, 2, 20)),
            stage('DEEP', DateTime(2026, 11, 17, 2, 20), DateTime(2026, 11, 17, 5)),
            stage('REM', DateTime(2026, 11, 17, 5), DateTime(2026, 11, 17, 7)),
          ],
        ),
        // Aynı gece ikinci kaynak: çakışan kısım bir kez, taşan 30 dk eklenir.
        sleepPoint(
          DateTime(2026, 11, 16, 23, 30),
          DateTime(2026, 11, 17, 7, 30),
          stages: [
            stage('ASLEEP', DateTime(2026, 11, 16, 23, 30), DateTime(2026, 11, 17, 1, 30)),
            stage('ASLEEP', DateTime(2026, 11, 17, 6), DateTime(2026, 11, 17, 7, 30)),
          ],
        ),
      ];
    source = GoogleHealthSource(
      link: link,
      api: GoogleHealthApi(accessToken: link.accessToken, client: server.client()),
    );
  });

  group('readToday / readPastDays', () {
    test('bugün: adım, aktif kalori ve 18:00 penceresinde birleşik uyku', () async {
      final snapshot = await source.readToday(now: now);

      expect(snapshot.status, HealthStatus.ok);
      expect(snapshot.source, HealthSourceKind.googleHealth);
      expect(snapshot.steps, 4000);
      expect(snapshot.activeKcal, 120);
      // 18:00–18:30 şekerleme (30) + gece [23:10–02:00] ∪ [02:20–07:30]
      // (170 + 310); uyanık bölümler ve çift kaynak sayılmaz.
      expect(snapshot.sleepMinutes, 30 + 170 + 310);
      expect(snapshot.readAt, now);
      expect(link.synced, [now]);
      expect(link.failures, isEmpty);
    });

    test('geçmiş günler: gece yarısını geçen uyku ve sınırda bölünen şekerleme',
        () async {
      final days = await source.readPastDays(days: 2, now: now);

      expect([for (final d in days) d.day], [d15, d16]);
      final (day: _, snapshot: s15) = days[0];
      final (day: _, snapshot: s16) = days[1];
      expect(s15.steps, 9000);
      expect(s15.activeKcal, 300);
      expect(s15.sleepMinutes, 0);
      expect(s16.steps, 11000);
      expect(s16.activeKcal, 501);
      expect(s16.sleepMinutes, 480 + 30);
      expect(s16.source, HealthSourceKind.googleHealth);
      // Tek istek her veri türü için (3 istek), uyku süzgeci pencereyi kapsar.
      expect(server.requests, hasLength(3));
      final sleepRequest =
          server.requests.firstWhere((r) => r.url.path.endsWith('/sleep/dataPoints'));
      expect(
        sleepRequest.url.queryParameters['filter'],
        'sleep.interval.end_time >= "${utc(DateTime(2026, 11, 14, 18))}" AND '
        'sleep.interval.end_time < "${utc(DateTime(2026, 11, 17, 18))}"',
      );
    });

    test('oturum yenilenemezse "yeniden bağlan" durumu ve istek yok', () async {
      link.tokenError =
          const GoogleHealthException(GoogleHealthErrorKind.reconnect);

      final snapshot = await source.readToday(now: now);

      expect(snapshot.status, HealthStatus.reconnect);
      expect(snapshot.source, HealthSourceKind.googleHealth);
      expect(snapshot.message, contains('Google\'a yeniden bağlan'));
      expect(link.failures.single.kind, GoogleHealthErrorKind.reconnect);
      expect(server.requests, isEmpty);
      expect(await source.readPastDays(now: now), isEmpty);
    });

    test('bağlı değil → notConnected; 403 → reconnect', () async {
      link.tokenError =
          const GoogleHealthException(GoogleHealthErrorKind.notConnected);
      expect((await source.readToday(now: now)).status, HealthStatus.notConnected);
      server.failStatus = 403;
      link.tokenError = null;
      expect((await source.readToday(now: now)).status, HealthStatus.reconnect);
    });

    test('429 geçici hata: "sonra tekrar" mesajı, veri yazılmaz', () async {
      server.failStatus = 429;
      final snapshot = await source.readToday(now: now);
      expect(snapshot.status, HealthStatus.failed);
      expect(snapshot.message, contains('Biraz sonra tekrar dene'));
      expect(snapshot.hasData, isFalse);
      expect(link.synced, isEmpty);
    });

    test('istemci kimliği yoksa kullanılamaz, istek gönderilmez', () async {
      link.configured = false;
      final snapshot = await source.readToday(now: now);
      expect(snapshot.status, HealthStatus.unavailable);
      expect(snapshot.message, contains('yapılandırılmamış'));
      expect(await source.readPastDays(now: now), isEmpty);
      expect(link.tokenCalls, 0);
      expect(server.requests, isEmpty);
    });
  });

  group('importWorkouts', () {
    late FakeHealthRepository repository;

    setUp(() {
      repository = FakeHealthRepository();
      server.exercises = [
        exercisePoint(
          'run-1',
          'RUNNING',
          DateTime(2026, 11, 16, 7, 5),
          DateTime(2026, 11, 16, 7, 50),
          duration: '2280s',
          distanceMm: 6120000,
          kcal: 401.7,
          created: DateTime.utc(2026, 11, 16, 8),
          name: 'Koşu',
        ),
        exercisePoint(
          'lift-1',
          'WEIGHTLIFTING',
          DateTime(2026, 11, 15, 19, 30),
          DateTime(2026, 11, 15, 20, 15),
          created: DateTime.utc(2026, 11, 15, 21),
        ),
        exercisePoint(
          'walk-1',
          'WALKING',
          DateTime(2026, 11, 14, 8),
          DateTime(2026, 11, 14, 19, 40),
          distanceMm: 0,
          kcal: 0,
        ),
      ];
    });

    test('alanlar eşlenir ve sınırlara sıkıştırılır', () async {
      final sent = await source.importWorkouts(repository, now: now);

      expect(sent, 3);
      final byId = {
        for (final w in repository.workouts) w.title ?? w.workoutType: w,
      };
      final run = byId['Koşu']!;
      expect(run.workoutType, 'running');
      expect(run.source, 'google');
      expect(run.durationMin, 38);
      expect(run.distanceKm, 6.12);
      expect(run.caloriesBurned, 402);
      expect(run.loggedAt, DateTime(2026, 11, 16, 7, 5));
      final lift = repository.workouts.firstWhere((w) => w.workoutType == 'weights');
      expect(lift.durationMin, 45, reason: 'activeDuration yoksa aralık süresi');
      final walk = repository.workouts.firstWhere((w) => w.workoutType == 'other');
      expect(walk.durationMin, 600, reason: '700 dk → üst sınır 600');
      expect(walk.distanceKm, isNull);
      expect(walk.caloriesBurned, isNull);
      expect(link.watermark, DateTime.utc(2026, 11, 16, 8));

      final request = server.requests
          .firstWhere((r) => r.url.path.endsWith('/exercise/dataPoints'));
      expect(
        request.url.queryParameters['filter'],
        'exercise.interval.civil_start_time >= "2026-11-10" AND '
        'exercise.interval.civil_start_time < "2026-11-18"',
      );
    });

    test('yeniden eşitleme kopya üretmez; silinen kayıt geri gelmez', () async {
      await source.importWorkouts(repository, now: now);
      expect(repository.workouts, hasLength(3));

      // İkinci eşitleme: işaretten eski olanlar gönderilmez; oluşturulma anı
      // bilinmeyen kayıt gönderilir ama dizin kopyayı reddeder.
      final second = await source.importWorkouts(repository, now: now);
      expect(second, 1);
      expect(repository.workouts, hasLength(3));

      // Kullanıcı aktarılan koşuyu siler: sonraki eşitlemede geri gelmez.
      final run = repository.workouts.firstWhere((w) => w.workoutType == 'running');
      await repository.deleteWorkout(run.id);
      await source.importWorkouts(repository, now: now);
      expect(repository.workouts.where((w) => w.workoutType == 'running'), isEmpty);

      // Google'da sonradan oluşan yeni antrenman aktarılır.
      server.exercises = [
        ...server.exercises,
        exercisePoint(
          'box-1',
          'BOXING',
          DateTime(2026, 11, 17, 12),
          DateTime(2026, 11, 17, 13),
          created: DateTime.utc(2026, 11, 17, 13, 5),
        ),
      ];
      await source.importWorkouts(repository, now: now);
      expect(
        repository.workouts.where((w) => w.workoutType == 'kickboxing'),
        hasLength(1),
      );
      expect(link.watermark, DateTime.utc(2026, 11, 17, 13, 5));
    });

    test('Google hatasında hiçbir şey yazılmaz ve işaret değişmez', () async {
      server.failStatus = 503;
      expect(await source.importWorkouts(repository, now: now), 0);
      expect(repository.importCalls, 0);
      expect(link.watermark, isNull);
      expect(link.failures.single.kind, GoogleHealthErrorKind.unavailable);
    });

    test('depo yazamazsa işaret ilerlemez (sonraki eşitlemede yeniden denenir)',
        () async {
      repository.writeError = Exception('ağ yok');
      await expectLater(
        source.importWorkouts(repository, now: now),
        throwsException,
      );
      expect(link.watermark, isNull);
    });
  });

  test('antrenman türü eşlemesi', () {
    expect(workoutTypeForGoogle('WEIGHTLIFTING'), 'weights');
    expect(workoutTypeForGoogle('STRENGTH_TRAINING'), 'weights');
    expect(workoutTypeForGoogle('KICKBOXING'), 'kickboxing');
    expect(workoutTypeForGoogle('MUAY_THAI'), 'kickboxing');
    expect(workoutTypeForGoogle('TREADMILL'), 'running');
    expect(workoutTypeForGoogle('SOCCER'), 'football');
    expect(workoutTypeForGoogle('FOOTBALL_AMERICAN'), 'other');
    expect(workoutTypeForGoogle('YOGA'), 'other');
    for (final type in ['WEIGHTS', 'BOXING', 'RUNNING', 'SOCCER', 'X']) {
      expect(WorkoutLog.workoutTypes, contains(workoutTypeForGoogle(type)));
    }
  });

  test('ExternalWorkout ekleme gövdesi kaynak kimliğini taşır', () {
    final row = externalWorkoutFromGoogle(
      GoogleExercise(
        id: 'abc',
        exerciseType: 'RUNNING',
        start: DateTime.utc(2026, 11, 16, 4),
        end: DateTime.utc(2026, 11, 16, 4, 0, 20),
      ),
    ).toInsertMap('user-1');
    expect(row['user_id'], 'user-1');
    expect(row['source'], 'google');
    expect(row['external_id'], 'abc');
    expect(row['log_type'], 'workout');
    expect(row['duration_min'], isNull, reason: '1 dakikadan kısa süre boş');
    expect(row['logged_at'], '2026-11-16T04:00:00.000Z');
  });

  test('sleepMinutesInWindow: kırpma ve birleştirme', () {
    final start = DateTime(2026, 11, 16, 18);
    final end = DateTime(2026, 11, 17, 18);
    expect(
      sleepMinutesInWindow(
        [
          (DateTime(2026, 11, 16, 17), DateTime(2026, 11, 16, 19)), // 60 içeride
          (DateTime(2026, 11, 16, 23), DateTime(2026, 11, 17, 3)), // 240
          (DateTime(2026, 11, 17, 1), DateTime(2026, 11, 17, 4)), // +60 taşan
          (DateTime(2026, 11, 17, 17, 30), DateTime(2026, 11, 17, 20)), // 30
          (DateTime(2026, 11, 18), DateTime(2026, 11, 18, 1)), // pencere dışı
        ],
        start,
        end,
      ),
      60 + 240 + 60 + 30,
    );
    expect(sleepMinutesInWindow(const [], start, end), 0);
  });
}
