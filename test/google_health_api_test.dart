import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/google_health_api.dart';

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> rollup(DateTime day, Map<String, dynamic> value) => {
      'civilStartTime': {
        'date': {'year': day.year, 'month': day.month, 'day': day.day},
      },
      'civilEndTime': {
        'date': {'year': day.year, 'month': day.month, 'day': day.day + 1},
      },
      ...value,
    };

void main() {
  test('yalnızca salt okuma kapsamları istenir', () {
    expect(googleHealthScopes, [
      'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
      'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
    ]);
    expect(googleHealthScopes.every((s) => s.endsWith('.readonly')), isTrue);
  });

  group('dailyRollUp', () {
    test('adım: istek adresi, başlıklar, gövde ve sayfalama', () async {
      final requests = <http.Request>[];
      final api = GoogleHealthApi(
        accessToken: () async => 'tok-1',
        client: MockClient((request) async {
          requests.add(request);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['pageToken'] == null) {
            return jsonResponse({
              'rollupDataPoints': [
                rollup(DateTime(2026, 11, 10), {
                  'steps': {'countSum': '8123'},
                }),
                rollup(DateTime(2026, 11, 11), {
                  'steps': {'countSum': '10456'},
                }),
              ],
              'nextPageToken': 'sayfa-2',
            });
          }
          return jsonResponse({
            'rollupDataPoints': [
              rollup(DateTime(2026, 11, 12), {
                'steps': {'countSum': 432},
              }),
              // Verisi olmayan gün: değer alanı yok.
              rollup(DateTime(2026, 11, 13), const {}),
            ],
          });
        }),
      );

      final steps = await api.dailySteps(
        from: DateTime(2026, 11, 10),
        to: DateTime(2026, 11, 17),
      );

      expect(steps, {
        DateTime(2026, 11, 10): 8123,
        DateTime(2026, 11, 11): 10456,
        DateTime(2026, 11, 12): 432,
        DateTime(2026, 11, 13): 0,
      });
      expect(requests, hasLength(2));
      final first = requests.first;
      expect(first.method, 'POST');
      expect(
        first.url.toString(),
        'https://health.googleapis.com/v4/users/me/dataTypes/steps/'
        'dataPoints:dailyRollUp',
      );
      expect(first.headers['Authorization'], 'Bearer tok-1');
      expect(first.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(first.body), {
        'range': {
          'start': {
            'date': {'year': 2026, 'month': 11, 'day': 10},
          },
          'end': {
            'date': {'year': 2026, 'month': 11, 'day': 17},
          },
        },
        'windowSizeDays': 1,
        'pageSize': 90,
      });
      // İkinci sayfa aynı gövdeyi + anahtarı taşır.
      final second = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(second['pageToken'], 'sayfa-2');
      expect(second['range'], (jsonDecode(first.body) as Map)['range']);
    });

    test('bugün: aralık şu ana kadar (sivil saat) ve aktif kalori', () async {
      late Map<String, dynamic> body;
      late Uri url;
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((request) async {
          url = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({
            'rollupDataPoints': [
              rollup(DateTime(2026, 11, 17), {
                'activeEnergyBurned': {'kcalSum': 412.6},
              }),
            ],
          });
        }),
      );

      final kcal = await api.dailyActiveKcal(
        from: DateTime(2026, 11, 17),
        to: DateTime(2026, 11, 17, 14, 5, 30),
      );

      expect(url.path,
          '/v4/users/me/dataTypes/active-energy-burned/dataPoints:dailyRollUp');
      expect((body['range'] as Map)['end'], {
        'date': {'year': 2026, 'month': 11, 'day': 17},
        'time': {'hours': 14, 'minutes': 5, 'seconds': 30},
      });
      expect(kcal, {DateTime(2026, 11, 17): 412.6});
    });

    test('90 günü aşan aralık parçalara bölünür', () async {
      final starts = <Object?>[];
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          starts.add((body['range'] as Map)['start']);
          return jsonResponse(const {'rollupDataPoints': []});
        }),
      );
      await api.dailySteps(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(starts, [
        {
          'date': {'year': 2026, 'month': 1, 'day': 1},
        },
        {
          'date': {'year': 2026, 'month': 4, 'day': 1},
        },
      ]);
    });

    test('aynı sayfa anahtarı tekrar gelirse sayfalama durur', () async {
      var calls = 0;
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((request) async {
          calls++;
          return jsonResponse(const {
            'rollupDataPoints': [],
            'nextPageToken': 'hep-ayni',
          });
        }),
      );
      await api.dailySteps(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 2),
      );
      expect(calls, 2);
    });
  });

  group('list', () {
    test('uyku: bitiş süzgeci, sayfa boyu 25, sayfalama ve evreler', () async {
      final urls = <Uri>[];
      final api = GoogleHealthApi(
        accessToken: () async => 'tok-s',
        client: MockClient((request) async {
          urls.add(request.url);
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer tok-s');
          if (request.url.queryParameters['pageToken'] == null) {
            return jsonResponse({
              'dataPoints': [
                {
                  'name': 'users/me/dataTypes/sleep/dataPoints/s1',
                  'sleep': {
                    'interval': {
                      'startTime': '2026-11-16T20:30:00Z',
                      'endTime': '2026-11-17T04:30:00Z',
                    },
                    'type': 'STAGES',
                    'stages': [
                      {
                        'type': 'AWAKE',
                        'startTime': '2026-11-16T20:30:00Z',
                        'endTime': '2026-11-16T20:45:00Z',
                      },
                      {
                        'type': 'LIGHT',
                        'startTime': '2026-11-16T20:45:00Z',
                        'endTime': '2026-11-17T00:00:00Z',
                      },
                      {
                        'type': 'DEEP',
                        'startTime': '2026-11-17T00:00:00Z',
                        'endTime': '2026-11-17T02:00:00Z',
                      },
                      {
                        'type': 'RESTLESS',
                        'startTime': '2026-11-17T02:00:00Z',
                        'endTime': '2026-11-17T02:10:00Z',
                      },
                      {
                        'type': 'REM',
                        'startTime': '2026-11-17T02:10:00Z',
                        'endTime': '2026-11-17T04:30:00Z',
                      },
                    ],
                  },
                },
              ],
              'nextPageToken': 'p2',
            });
          }
          return jsonResponse({
            'dataPoints': [
              {
                // Evresiz (elle girilmiş) uyku: oturumun tamamı sayılır.
                'sleep': {
                  'interval': {
                    'startTime': '2026-11-15T21:00:00Z',
                    'endTime': '2026-11-16T05:00:00Z',
                  },
                },
              },
            ],
          });
        }),
      );

      final sessions = await api.sleepSessions(
        endFrom: DateTime.utc(2026, 11, 15, 15),
        endTo: DateTime.utc(2026, 11, 18, 15),
      );

      expect(urls, hasLength(2));
      expect(urls.first.path, '/v4/users/me/dataTypes/sleep/dataPoints');
      expect(urls.first.queryParameters['pageSize'], '25');
      expect(
        urls.first.queryParameters['filter'],
        'sleep.interval.end_time >= "2026-11-15T15:00:00Z" AND '
        'sleep.interval.end_time < "2026-11-18T15:00:00Z"',
      );
      expect(urls[1].queryParameters['pageToken'], 'p2');
      expect(urls[1].queryParameters['filter'],
          urls.first.queryParameters['filter']);

      expect(sessions, hasLength(2));
      final staged = sessions.first;
      expect(
          staged.asleep,
          [
            (DateTime.utc(2026, 11, 16, 20, 45), DateTime.utc(2026, 11, 17)),
            (DateTime.utc(2026, 11, 17), DateTime.utc(2026, 11, 17, 2)),
            (
              DateTime.utc(2026, 11, 17, 2, 10),
              DateTime.utc(2026, 11, 17, 4, 30)
            ),
          ],
          reason: 'AWAKE ve RESTLESS sayılmaz');
      expect(sessions[1].asleep, [
        (DateTime.utc(2026, 11, 15, 21), DateTime.utc(2026, 11, 16, 5)),
      ]);
    });

    test('antrenman: sivil gün süzgeci ve alanların ayrıştırılması', () async {
      late Uri url;
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((request) async {
          url = request.url;
          return jsonResponse({
            'dataPoints': [
              {
                'name': 'users/123/dataTypes/exercise/dataPoints/ex-abc',
                'exercise': {
                  'exerciseType': 'RUNNING',
                  'displayName': 'Running',
                  'interval': {
                    'startTime': '2026-11-16T04:05:00Z',
                    'endTime': '2026-11-16T04:45:00Z',
                  },
                  'activeDuration': '2280.500s',
                  'metricsSummary': {
                    'distanceMillimeters': 6120000,
                    'caloriesKcal': 401.7,
                  },
                  'createTime': '2026-11-16T05:00:00Z',
                },
              },
              {
                // Adı olmayan nokta: kimlik başlangıç + türden türetilir.
                'exercise': {
                  'exerciseType': 'WEIGHTLIFTING',
                  'interval': {
                    'startTime': '2026-11-15T16:30:00Z',
                    'endTime': '2026-11-15T17:15:00Z',
                  },
                },
              },
            ],
          });
        }),
      );

      final list = await api.exercises(
        fromDay: DateTime(2026, 11, 10),
        toDay: DateTime(2026, 11, 18),
      );

      expect(url.path, '/v4/users/me/dataTypes/exercise/dataPoints');
      expect(
        url.queryParameters['filter'],
        'exercise.interval.civil_start_time >= "2026-11-10" AND '
        'exercise.interval.civil_start_time < "2026-11-18"',
      );
      expect(url.queryParameters['pageSize'], '25');
      expect(list, hasLength(2));
      final run = list.first;
      expect(run.id, 'ex-abc');
      expect(run.exerciseType, 'RUNNING');
      expect(
          run.activeDuration, const Duration(seconds: 2280, milliseconds: 500));
      expect(run.distanceMeters, 6120);
      expect(run.caloriesKcal, 401.7);
      expect(run.createTime, DateTime.utc(2026, 11, 16, 5));
      expect(list[1].id, '2026-11-15T16:30:00Z-WEIGHTLIFTING');
      expect(list[1].activeDuration, isNull);
    });
  });

  group('hata eşlemesi', () {
    Future<GoogleHealthException> failWith(
      int status, {
      Object? body,
      Map<String, String> headers = const {},
    }) async {
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient(
          (_) async => http.Response(
            body == null ? '' : jsonEncode(body),
            status,
            headers: headers,
          ),
        ),
      );
      try {
        await api.dailySteps(
          from: DateTime(2026, 11, 16),
          to: DateTime(2026, 11, 17),
        );
      } on GoogleHealthException catch (error) {
        return error;
      }
      fail('hata bekleniyordu');
    }

    Map<String, dynamic> googleError(int code, String status, String reason) =>
        {
          'error': {
            'code': code,
            'message': 'Request had insufficient authentication scopes.',
            'status': status,
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                'reason': reason,
                'domain': 'googleapis.com',
              },
            ],
          },
        };

    test('401 → yeniden bağlan', () async {
      final error = await failWith(401);
      expect(error.kind, GoogleHealthErrorKind.reconnect);
      expect(error.message, contains('Google\'a yeniden bağlan'));
    });

    test('403 kapsam yetersiz → izin eksik', () async {
      for (final reason in [
        'ACCESS_TOKEN_SCOPE_INSUFFICIENT',
        'MISSING_OAUTH_SCOPE'
      ]) {
        final error = await failWith(403,
            body: googleError(403, 'PERMISSION_DENIED', reason));
        expect(error.kind, GoogleHealthErrorKind.missingScope, reason: reason);
        expect(error.message, contains('izni eksik'));
      }
      final header = await failWith(
        403,
        headers: {
          'www-authenticate':
              'Bearer realm="https://accounts.google.com/", error="insufficient_scope"',
        },
      );
      expect(header.kind, GoogleHealthErrorKind.missingScope);
    });

    test('403 API kapalı → yapılandırma', () async {
      final error = await failWith(
        403,
        body: {
          'error': {
            'code': 403,
            'message': 'Google Health API has not been used in project 1 '
                'before or it is disabled.',
            'status': 'PERMISSION_DENIED',
            'details': [
              {
                '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
                'reason': 'SERVICE_DISABLED',
              },
            ],
          },
        },
      );
      expect(error.kind, GoogleHealthErrorKind.configuration);
    });

    test('diğer 403 → yeniden bağlan', () async {
      final error = await failWith(
        403,
        body: {
          'error': {
            'code': 403,
            'message': 'denied',
            'status': 'PERMISSION_DENIED'
          },
        },
      );
      expect(error.kind, GoogleHealthErrorKind.reconnect);
    });

    test('429 ve 5xx → sonra tekrar dene', () async {
      final limited = await failWith(429);
      expect(limited.kind, GoogleHealthErrorKind.rateLimited);
      expect(limited.message, contains('Biraz sonra tekrar dene'));
      expect(limited.kind.isTemporary, isTrue);
      for (final status in [500, 502, 503]) {
        final error = await failWith(status);
        expect(error.kind, GoogleHealthErrorKind.unavailable);
        expect(error.message, contains('Biraz sonra tekrar dene'));
      }
    });

    test('diğer 4xx → istek reddedildi (kod mesajda)', () async {
      final error = await failWith(400, body: {
        'error': {'code': 400}
      });
      expect(error.kind, GoogleHealthErrorKind.requestRejected);
      expect(error.message, contains('400'));
    });

    test('400 ACCOUNT_NOT_LINKED → Google Health profili yok', () async {
      final error = await failWith(400, body: {
        'error': {
          'code': 400,
          'message': 'The user account is not linked to Google Health.',
          'status': 'FAILED_PRECONDITION',
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
              'reason': 'ACCOUNT_NOT_LINKED',
              'metadata': {'redirect_uri': 'https://fitbit.google.com/auth/signup'},
            },
          ],
        },
      });
      expect(error.kind, GoogleHealthErrorKind.accountNotLinked);
      expect(error.message, contains('Fitbit'));
      expect(error.message, contains('yeniden bağlan'));
      expect(error.detail, contains('ACCOUNT_NOT_LINKED'));
    });

    test('400 gövdesi: Google mesajı kısaltılmış ve temizlenmiş gösterilir',
        () async {
      final long = 'Invalid range:\n start must be before end. ${'x' * 300}';
      final error = await failWith(400, body: {
        'error': {
          'code': 400,
          'message': long,
          'status': 'INVALID_ARGUMENT',
        },
      });
      expect(error.kind, GoogleHealthErrorKind.requestRejected);
      expect(error.message, contains('HTTP 400 · INVALID_ARGUMENT: Invalid range'));
      expect(error.message, contains('Google\'a yeniden bağlanmayı dene'));
      expect(error.message.contains('\n'), isFalse);
      expect(error.detail!.length, lessThanOrEqualTo(150));
    });

    test('identity: GET users/me/identity, profil yoksa hata', () async {
      final requests = <http.Request>[];
      final ok = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse({'healthUserId': 'u-1'});
        }),
      );
      expect(await ok.identity(), 'u-1');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(),
          'https://health.googleapis.com/v4/users/me/identity');
      final unlinked = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((_) async => jsonResponse({
              'error': {
                'code': 400,
                'status': 'FAILED_PRECONDITION',
                'details': [
                  {'reason': 'ACCOUNT_NOT_LINKED'},
                ],
              },
            }, status: 400)),
      );
      await expectLater(
        unlinked.identity(),
        throwsA(isA<GoogleHealthException>().having((e) => e.kind, 'kind',
            GoogleHealthErrorKind.accountNotLinked)),
      );
    });

    test('yeni hesap: boş rollUp yanıtı hata değil, boş sonuç', () async {
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((_) async => jsonResponse(const {})),
      );
      expect(
        await api.dailySteps(
            from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 17)),
        isEmpty,
      );
    });

    test('gece yarısından salise sonra boş aralık istenmez', () async {
      var sent = 0;
      final api = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((_) async {
          sent++;
          return jsonResponse(const {});
        }),
      );
      final result = await api.dailySteps(
        from: DateTime(2026, 11, 17),
        to: DateTime(2026, 11, 17, 0, 0, 0, 400),
      );
      expect(result, isEmpty);
      expect(sent, 0);
    });

    test('ağ hatası ve bozuk yanıt', () async {
      final offline = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.dailySteps(
            from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 17)),
        throwsA(
          isA<GoogleHealthException>()
              .having((e) => e.kind, 'kind', GoogleHealthErrorKind.network),
        ),
      );
      final broken = GoogleHealthApi(
        accessToken: () async => 'tok',
        client: MockClient((_) async => http.Response('<html>', 200)),
      );
      await expectLater(
        broken.dailySteps(
            from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 17)),
        throwsA(
          isA<GoogleHealthException>().having(
            (e) => e.kind,
            'kind',
            GoogleHealthErrorKind.invalidResponse,
          ),
        ),
      );
    });

    test('erişim anahtarı alınamazsa istek gönderilmez', () async {
      var sent = 0;
      final api = GoogleHealthApi(
        accessToken: () async => throw const GoogleHealthException(
            GoogleHealthErrorKind.notConnected),
        client: MockClient((_) async {
          sent++;
          return jsonResponse(const {});
        }),
      );
      await expectLater(
        api.dailySteps(
            from: DateTime(2026, 11, 16), to: DateTime(2026, 11, 17)),
        throwsA(isA<GoogleHealthException>()),
      );
      expect(sent, 0);
    });
  });

  test('rfc3339 ve civilDate biçimleri', () {
    expect(
      GoogleHealthApi.rfc3339(DateTime.utc(2026, 1, 2, 3, 4, 5, 678)),
      '2026-01-02T03:04:05Z',
    );
    expect(GoogleHealthApi.civilDate(DateTime(2026, 3, 9, 23)), '2026-03-09');
    expect(GoogleHealthApi.civilDateTime(DateTime(2026, 3, 9)), {
      'date': {'year': 2026, 'month': 3, 'day': 9},
    });
  });
}
