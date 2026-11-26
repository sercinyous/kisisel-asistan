import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kisisel_asistan/core/config/env.dart';
import 'package:kisisel_asistan/features/ai/data/gemini_transport.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';

const String proxyUrl = 'https://proje.supabase.co/functions/v1/ai-proxy';
const Map<String, dynamic> geminiBody = {
  'systemInstruction': {
    'parts': [
      {'text': 'talimat'},
    ],
  },
  'contents': [
    {
      'role': 'user',
      'parts': [
        {'text': 'merhaba'},
      ],
    },
  ],
  'generationConfig': {'maxOutputTokens': 2048},
};

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=UTF-8'},
    );

http.Response geminiOk(String text) => json({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    });

Future<String?> session() async => 'oturum-jwt';

Duration noDelay(int attempt) => Duration.zero;

GeminiTransport proxyTransport(
  MockClientHandler handler, {
  AccessTokenReader? accessToken = session,
  String url = proxyUrl,
  String anonKey = 'anon-key',
  Duration timeout = const Duration(seconds: 30),
  RetryDelay retryDelay = noDelay,
}) =>
    GeminiTransport(
      apiKey: '',
      model: 'gemini-3.8-flash',
      proxyUrl: url,
      anonKey: anonKey,
      accessToken: accessToken,
      client: MockClient(handler),
      timeout: timeout,
      retryDelay: retryDelay,
    );

GeminiTransport directTransport(
  MockClientHandler handler, {
  RetryDelay retryDelay = noDelay,
}) =>
    GeminiTransport(
      apiKey: 'dogrudan-anahtar',
      model: 'gemini-3.8-flash',
      proxyUrl: proxyUrl,
      accessToken: session,
      client: MockClient(handler),
      retryDelay: retryDelay,
    );

Future<AiParseException> expectAiError(Future<Object?> future) async {
  try {
    await future;
  } on AiParseException catch (e) {
    return e;
  }
  fail('AiParseException bekleniyordu');
}

void main() {
  group('mod seçimi', () {
    test('GEMINI_API_KEY boşsa (ya da yalnızca boşluksa) proxy modu', () {
      expect(proxyTransport((_) async => json({})).usesProxy, isTrue);
      final blank = GeminiTransport(apiKey: '   ', model: 'm');
      expect(blank.usesProxy, isTrue);
      blank.dispose();
    });

    test('anahtar doluysa doğrudan mod', () {
      expect(directTransport((_) async => json({})).usesProxy, isFalse);
    });

    test('derlemede anahtar verilmediğinde Env proxy modundadır', () {
      expect(Env.geminiApiKey, '');
      expect(Env.usesAiProxy, isTrue);
      expect(Env.missingKeys, isNot(contains('GEMINI_API_KEY')));
    });

    test('aiProxyUrlFor: işlev adresi SUPABASE_URL kökünden kurulur', () {
      expect(
        aiProxyUrlFor('https://abcd.supabase.co'),
        'https://abcd.supabase.co/functions/v1/ai-proxy',
      );
      expect(aiProxyUrlFor(''), '');
    });
  });

  group('proxy modu: giden istek', () {
    late http.Request captured;

    setUp(() async {
      final transport = proxyTransport((request) async {
        captured = request;
        return geminiOk('{}');
      });
      await transport.post(geminiBody);
    });

    test('adres, yöntem ve oturum belirteci', () {
      expect(captured.method, 'POST');
      expect(captured.url.toString(), proxyUrl);
      expect(captured.headers['Authorization'], 'Bearer oturum-jwt');
      expect(captured.headers['apikey'], 'anon-key');
      expect(captured.headers['content-type']!.toLowerCase(),
          contains('charset=utf-8'));
    });

    test('Gemini anahtarı hiçbir yerde yoktur', () {
      expect(captured.headers.containsKey('x-goog-api-key'), isFalse);
      expect(captured.url.queryParameters, isEmpty);
      expect(captured.url.host, isNot(contains('googleapis')));
    });

    test('gövde Gemini generateContent gövdesidir, olduğu gibi', () {
      expect(jsonDecode(captured.body), geminiBody);
    });
  });

  group('proxy modu: oturum', () {
    test('oturum yoksa (belirteç null) istek gitmez, 401 oturum mesajı',
        () async {
      var calls = 0;
      final transport = proxyTransport(
        (_) async {
          calls++;
          return geminiOk('{}');
        },
        accessToken: () async => null,
      );
      final e = await expectAiError(transport.post(geminiBody));
      expect(calls, 0);
      expect(e.statusCode, 401);
      expect(e.message, contains('Oturum bulunamadı'));
    });

    test('belirteç okuyucu verilmemişse de 401', () async {
      var calls = 0;
      final transport = proxyTransport(
        (_) async {
          calls++;
          return geminiOk('{}');
        },
        accessToken: null,
      );
      final e = await expectAiError(transport.post(geminiBody));
      expect(calls, 0);
      expect(e.statusCode, 401);
    });

    test('boş belirteç oturum yok sayılır', () async {
      final transport = proxyTransport(
        (_) async => geminiOk('{}'),
        accessToken: () async => '',
      );
      expect((await expectAiError(transport.post(geminiBody))).statusCode, 401);
    });

    test('belirteç her denemede yeniden okunur (yenilenmiş oturum)', () async {
      var reads = 0;
      final seen = <String?>[];
      final transport = proxyTransport(
        (request) async {
          seen.add(request.headers['Authorization']);
          return seen.length == 1
              ? json({'error': 'yoğun'}, 503)
              : geminiOk('{}');
        },
        accessToken: () async => 'jwt-${++reads}',
      );
      await transport.post(geminiBody);
      expect(seen, ['Bearer jwt-1', 'Bearer jwt-2']);
    });

    test('proxy adresi boşsa (SUPABASE_URL yok) anlaşılır hata, istek gitmez',
        () async {
      var calls = 0;
      final transport = proxyTransport(
        (_) async {
          calls++;
          return geminiOk('{}');
        },
        url: '',
      );
      final e = await expectAiError(transport.post(geminiBody));
      expect(calls, 0);
      expect(e.message, contains('AI şu an kullanılamıyor'));
    });

    test('anon anahtarı boşsa apikey başlığı eklenmez', () async {
      late http.Request captured;
      final transport = proxyTransport((request) async {
        captured = request;
        return geminiOk('{}');
      }, anonKey: '');
      await transport.post(geminiBody);
      expect(captured.headers.containsKey('apikey'), isFalse);
    });
  });

  group('proxy modu: hata eşleme', () {
    Future<AiParseException> errorFor(http.Response response) {
      final transport = proxyTransport((_) async => response);
      return expectAiError(transport.post(geminiBody));
    }

    test('401 -> oturum mesajı', () async {
      final e = await errorFor(json({'error': 'Oturum bulunamadı'}, 401));
      expect(e.statusCode, 401);
      expect(e.message,
          'Oturum bulunamadı ya da süresi doldu. Çıkış yapıp yeniden giriş yapın.');
    });

    test('402 -> düz "kullanılamıyor" iletisi (teknik ayrıntı yok)', () async {
      final e = await errorFor(json({'error': 'fatura'}, 402));
      expect(e.statusCode, 402);
      expect(e.message, contains('AI şu an kullanılamıyor'));
      expect(e.message, isNot(contains('402')));
    });

    test('404 -> düz "kullanılamıyor" iletisi', () async {
      final e = await errorFor(http.Response('Function not found', 404));
      expect(e.statusCode, 404);
      expect(e.message, contains('AI şu an kullanılamıyor'));
    });

    test('429 -> sunucunun Türkçe kota mesajı', () async {
      const message =
          'Günlük AI kullanım sınırına (100 istek) ulaştın. Yarın yeniden dene.';
      final e = await errorFor(json({'error': message}, 429));
      expect(e.statusCode, 429);
      expect(e.message, message);
    });

    test('429 gövdesi okunamazsa genel kota mesajı', () async {
      for (final response in [
        http.Response('<html>', 429),
        json({'baska': 1}, 429),
        json({'error': '   '}, 429),
        json(['dizi'], 429),
      ]) {
        final e = await errorFor(response);
        expect(e.message,
            'Günlük AI kullanım sınırına ulaşıldı. Yarın tekrar deneyin.');
      }
    });

    test('413 -> metin çok uzun', () async {
      final e = await errorFor(json({'error': 'büyük'}, 413));
      expect(e.message, contains('Metin çok uzun'));
    });

    test('400 -> geçersiz istek (model adı önerisi yok)', () async {
      final e = await errorFor(json({'error': 'x'}, 400));
      expect(e.message, contains('AI isteği geçersiz bulundu (400)'));
      expect(e.message, isNot(contains('Model adını')));
    });

    test('502 -> sunucu yapılandırması mesajı', () async {
      final e = await errorFor(json({'error': 'x'}, 502));
      expect(e.message, contains('AI şu an kullanılamıyor'));
    });

    test('sunucunun ham hata metni (500) kullanıcıya sızmaz', () async {
      final e = await errorFor(json({'error': 'iç ayrıntı: tablo yok'}, 500));
      expect(e.message, 'AI servisi hata verdi (500). Lütfen tekrar deneyin.');
    });
  });

  group('proxy modu: yeniden deneme', () {
    test('429 (günlük kota) yeniden denenmez: tek istek', () async {
      var calls = 0;
      final transport = proxyTransport((_) async {
        calls++;
        return json({'error': 'kota'}, 429);
      });
      final e = await expectAiError(transport.post(geminiBody));
      expect(calls, 1);
      expect(e.statusCode, 429);
    });

    for (final status in [401, 402, 404, 413, 502]) {
      test('$status yeniden denenmez', () async {
        var calls = 0;
        final transport = proxyTransport((_) async {
          calls++;
          return json({'error': 'x'}, status);
        });
        await expectAiError(transport.post(geminiBody));
        expect(calls, 1);
      });
    }

    for (final status in [500, 503, 504]) {
      test('$status 3 kez denenir', () async {
        var calls = 0;
        final transport = proxyTransport((_) async {
          calls++;
          return json({'error': 'geçici'}, status);
        });
        final e = await expectAiError(transport.post(geminiBody));
        expect(calls, 3);
        expect(e.statusCode, status);
      });
    }

    test('503 sonra 200 -> ikinci denemede başarı', () async {
      var calls = 0;
      final transport = proxyTransport((_) async {
        calls++;
        return calls == 1 ? json({'error': 'yoğun'}, 503) : geminiOk('tamam');
      });
      final body = await transport.post(geminiBody);
      expect(calls, 2);
      expect(jsonDecode(body)['candidates'], isNotEmpty);
    });

    test('bekleme süresi enjekte edilen retryDelay ile hesaplanır', () async {
      final delays = <int>[];
      final transport = proxyTransport(
        (_) async => json({'error': 'geçici'}, 503),
        retryDelay: (attempt) {
          delays.add(attempt);
          return Duration.zero;
        },
      );
      await expectAiError(transport.post(geminiBody));
      expect(delays, [1, 2]); // 3 denemede 2 bekleme
    });

    test('ağ hataları ve zaman aşımı yeniden denenir', () async {
      var calls = 0;
      final transport = proxyTransport((_) async {
        calls++;
        if (calls == 1) throw const SocketException('offline');
        if (calls == 2) throw http.ClientException('reset');
        return geminiOk('tamam');
      });
      await transport.post(geminiBody);
      expect(calls, 3);

      var slowCalls = 0;
      final slow = proxyTransport(
        (_) async {
          slowCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return geminiOk('geç');
        },
        timeout: const Duration(milliseconds: 20),
      );
      final e = await expectAiError(slow.post(geminiBody));
      expect(slowCalls, 3);
      expect(e.message,
          'AI servisi zamanında yanıt vermedi. Lütfen tekrar deneyin.');
    });
  });

  group('doğrudan mod (geçiş)', () {
    test('Google adresi, anahtar başlığı; oturum belirteci gönderilmez',
        () async {
      late http.Request captured;
      final transport = directTransport((request) async {
        captured = request;
        return geminiOk('{}');
      });
      await transport.post(geminiBody);
      expect(
        captured.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.8-flash:generateContent',
      );
      expect(captured.headers['x-goog-api-key'], 'dogrudan-anahtar');
      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(captured.headers.containsKey('apikey'), isFalse);
    });

    test('oturum olmasa da çalışır (belirteç okunmaz)', () async {
      var tokenReads = 0;
      final transport = GeminiTransport(
        apiKey: 'dogrudan-anahtar',
        model: 'm',
        accessToken: () async {
          tokenReads++;
          return null;
        },
        client: MockClient((_) async => geminiOk('{}')),
      );
      await transport.post(geminiBody);
      expect(tokenReads, 0);
    });

    test('429 hız sınırı yeniden denenir (Gemini, günlük kota değil)',
        () async {
      var calls = 0;
      final transport = directTransport((_) async {
        calls++;
        return json({'error': 'quota'}, 429);
      });
      final e = await expectAiError(transport.post(geminiBody));
      expect(calls, 3);
      expect(e.message,
          'Gemini kota sınırına ulaşıldı. Biraz sonra tekrar deneyin.');
    });

    test('504 doğrudan modda yeniden denenmez', () async {
      var calls = 0;
      final transport = directTransport((_) async {
        calls++;
        return json({'error': 'x'}, 504);
      });
      await expectAiError(transport.post(geminiBody));
      expect(calls, 1);
    });

    test('Gemini hata mesajları değişmedi', () async {
      final messages = <int, String>{
        401: 'Gemini API anahtarı geçersiz ya da yetkisiz.',
        404: 'Gemini modeli bulunamadı: gemini-3.8-flash',
        402: 'Gemini bakiyesi ya da faturalandırma tükendi (402). '
            'AI Studio > Billing bölümünden kredi ekleyin.',
      };
      for (final MapEntry(key: status, value: message) in messages.entries) {
        final transport =
            directTransport((_) async => json({'error': 'x'}, status));
        expect(
            (await expectAiError(transport.post(geminiBody))).message, message);
      }
    });
  });

  group('GeminiParserService proxy modunda', () {
    const workJson =
        '{"tasks":[{"title":"Fatura öde","category":"Finans","priority":"high"}],'
        '"notes":[],"routines":[],"other_domain":false}';

    GeminiParserService service(
      MockClientHandler handler, {
      AccessTokenReader? accessToken = session,
    }) =>
        GeminiParserService(
          apiKey: '',
          proxyUrl: proxyUrl,
          anonKey: 'anon-key',
          accessToken: accessToken,
          client: MockClient(handler),
          retryDelay: noDelay,
          mode: QuickAddMode.work,
        );

    test('ayrıştırma aynıdır: proxy yanıtı Gemini yanıtı gibi çözülür',
        () async {
      late http.Request captured;
      final parser = service((request) async {
        captured = request;
        return geminiOk(workJson);
      });
      final entry =
          await parser.parse('yarın fatura öde', now: DateTime(2026, 11, 16));

      expect(entry.totalCount, 1);
      expect(entry.tasks.single.title, 'Fatura öde');
      expect(captured.url.toString(), proxyUrl);
      expect(captured.headers['Authorization'], 'Bearer oturum-jwt');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.keys,
          containsAll(['systemInstruction', 'contents', 'generationConfig']));
      final config = body['generationConfig'] as Map<String, dynamic>;
      expect(config['maxOutputTokens'], 8192);
      expect(config['responseMimeType'], 'application/json');
    });

    test('günlük kota (429) kullanıcıya Türkçe mesajla ve tek istekle iner',
        () async {
      var calls = 0;
      const message =
          'Günlük AI kullanım sınırına (100 istek) ulaştın. Yarın yeniden dene.';
      final parser = service((_) async {
        calls++;
        return json({'error': message}, 429);
      });
      final e = await expectAiError(parser.parse('metin'));
      expect(calls, 1);
      expect(e.statusCode, 429);
      expect(e.message, message);
    });

    test('oturum yoksa istek gitmez', () async {
      var calls = 0;
      final parser = service(
        (_) async {
          calls++;
          return geminiOk(workJson);
        },
        accessToken: () async => null,
      );
      final e = await expectAiError(parser.parse('metin'));
      expect(calls, 0);
      expect(e.statusCode, 401);
    });

    test('haftalık özet de proxy üzerinden gider', () async {
      late http.Request captured;
      final parser = service((request) async {
        captured = request;
        return geminiOk('  İyi bir hafta.  ');
      });
      expect(await parser.generateWeeklySummary({'tasks_done': 5}),
          'İyi bir hafta.');
      expect(captured.url.toString(), proxyUrl);
    });

    test('dispose enjekte edilen istemciyi kapatmaz', () async {
      final parser = service((_) async => geminiOk(workJson))..dispose();
      await parser.parse('metin');
    });
  });

  group('rapor yeniden üretme günlük sınırı (429)', () {
    test('sunucunun Türkçe mesajı kullanıcıya gösterilir', () {
      const message =
          'Bugünlük rapor yenileme hakkın doldu (10). Yarın yeniden dene.';
      expect(
        reportErrorMessage(429, {'ok': false, 'error': message}),
        message,
      );
    });

    test('mesaj yoksa genel iletiye düşer', () {
      expect(reportErrorMessage(429, null), contains('oluşturulamadı'));
      expect(reportErrorMessage(429, 'düz metin'), contains('oluşturulamadı'));
    });
  });
}
