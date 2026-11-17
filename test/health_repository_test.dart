import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `fitness_logs` tablosunun PostgREST taklidi: gerçek [HealthRepository] ve
/// supabase istemcisi olduğu gibi çalışır, yalnızca HTTP yanıtları bellekten
/// gelir (ekleme, `logged_at` aralığıyla okuma, kimlikle silme).
class _FitnessTable {
  final List<Map<String, dynamic>> rows = [];
  final List<String> deletedIds = [];
  bool failReads = false;
  int _next = 1;

  // postgrest yanıtın `request` alanını okur; taklit yanıtlara eklenir.
  static http.Response _json(
    http.BaseRequest request,
    Object body, [
    int status = 200,
  ]) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  void add(
    String id,
    String type,
    DateTime at,
    int? minutes, {
    required String source,
  }) =>
      rows.add({
        'id': id,
        'log_type': 'workout',
        'workout_type': type,
        'title': null,
        'duration_min': minutes,
        'distance_km': null,
        'calories_burned': null,
        'notes': null,
        'logged_at': at.toUtc().toIso8601String(),
        'source': source,
      });

  http.Client client() => MockClient((request) async {
        final query = request.url.queryParametersAll;
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final row = {...body, 'id': 'new-${_next++}'};
          rows.add(row);
          return _json(request, row, 201);
        }
        if (request.method == 'DELETE') {
          final id = query['id']!.single.replaceFirst('eq.', '');
          deletedIds.add(id);
          rows.removeWhere((row) => row['id'] == id);
          return http.Response('', 204, request: request);
        }
        if (failReads) return http.Response('', 500, request: request);
        final bounds = query['logged_at'] ?? const <String>[];
        DateTime bound(String prefix) => DateTime.parse(
              bounds
                  .firstWhere((b) => b.startsWith(prefix))
                  .substring(prefix.length),
            );
        final from = bound('gte.');
        final to = bound('lt.');
        return _json(request, [
          for (final row in rows)
            if (!DateTime.parse(row['logged_at'] as String).isBefore(from) &&
                DateTime.parse(row['logged_at'] as String).isBefore(to))
              row,
        ]);
      });
}

void main() {
  late _FitnessTable table;
  late HealthRepository repository;

  setUp(() {
    table = _FitnessTable();
    repository = HealthRepository(
      SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: table.client(),
      ),
    );
  });

  final evening = DateTime(2026, 11, 16, 19);

  group('createWorkout: Google kopyası temizliği', () {
    test('aynı oturumun Google satırı silinir, kullanıcının kaydı kalır',
        () async {
      // Fitbit seansı Google'dan zaten aktarılmış; kullanıcı sonradan aynı
      // seansı formla yazıyor.
      table
        ..add('g-1', 'kickboxing', DateTime(2026, 11, 16, 19, 2), 59,
            source: 'google')
        ..add('g-morning', 'running', DateTime(2026, 11, 16, 7, 5), 38,
            source: 'google')
        ..add('m-old', 'kickboxing', DateTime(2026, 11, 16, 19, 10), 30,
            source: 'manual');

      final created = await repository.createWorkout(
        WorkoutLog(
          id: '',
          workoutType: 'kickboxing',
          loggedAt: evening.add(const Duration(minutes: 70)),
          durationMin: 60,
        ),
      );

      expect(created.source, 'manual');
      expect(table.deletedIds, ['g-1']);
      expect(
        table.rows.map((r) => r['id']),
        containsAll(['g-morning', 'm-old', created.id]),
        reason: 'sabah koşusu ve kullanıcının kendi kayıtları silinmez',
      );
      expect(table.rows, hasLength(3));
    });

    test('Google satırı oturumdan çok önce başlasa da (uzun oturum) bulunur',
        () async {
      // 10 saatlik Google oturumu 08:00'de başladı; kullanıcı 17:30'da yazıyor.
      table.add('g-long', 'other', DateTime(2026, 11, 16, 8), 600,
          source: 'google');

      await repository.createWorkout(
        WorkoutLog(
          id: '',
          workoutType: 'other',
          loggedAt: DateTime(2026, 11, 16, 17, 30),
          durationMin: 30,
        ),
      );

      expect(table.deletedIds, ['g-long']);
    });

    test('okuma/silme hatası kaydı bozmaz: kullanıcıya hata dönmez', () async {
      table.failReads = true;
      table.add('g-1', 'kickboxing', DateTime(2026, 11, 16, 19, 2), 59,
          source: 'google');

      final created = await repository.createWorkout(
        WorkoutLog(
          id: '',
          workoutType: 'kickboxing',
          loggedAt: evening,
          durationMin: 60,
        ),
      );

      expect(created.id, startsWith('new-'));
      expect(table.deletedIds, isEmpty,
          reason: 'temizlik bir sonraki Google eşitlemesine kalır');
    });

    test('Google satırı yoksa hiçbir şey silinmez', () async {
      table.add('m-1', 'kickboxing', evening, 60, source: 'manual');

      await repository.createWorkout(
        WorkoutLog(
          id: '',
          workoutType: 'kickboxing',
          loggedAt: evening,
          durationMin: 60,
        ),
      );

      expect(table.deletedIds, isEmpty);
      expect(table.rows, hasLength(2));
    });
  });
}
