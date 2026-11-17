import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Google Health API (v4) hata türleri.
enum GoogleHealthErrorKind {
  /// Derlemeye Google istemci kimliği verilmemiş.
  notConfigured,

  /// Google hesabı bağlı değil.
  notConnected,

  /// Oturum yenilenemedi ya da erişim reddedildi (401/403): yeniden bağlan.
  reconnect,

  /// Erişim anahtarı gereken kapsamı taşımıyor (403, kapsam yetersiz).
  missingScope,

  /// Google Cloud projesinde API etkin değil ya da istemci hatalı.
  configuration,

  /// 429: istek sınırı aşıldı.
  rateLimited,

  /// 5xx: sunucu yanıt vermiyor.
  unavailable,

  /// Ağ hatası ya da zaman aşımı.
  network,

  /// Yanıt beklenen biçimde değil.
  invalidResponse,

  /// Diğer 4xx yanıtları.
  requestRejected;

  /// Sağlık verisi kaynağını değil yalnızca isteği etkileyen geçici hatalar.
  bool get isTemporary => switch (this) {
        rateLimited || unavailable || network => true,
        _ => false,
      };
}

class GoogleHealthException implements Exception {
  const GoogleHealthException(this.kind, {this.status, String? message})
      : _message = message;

  final GoogleHealthErrorKind kind;

  /// HTTP durum kodu (varsa).
  final int? status;
  final String? _message;

  /// Kullanıcıya gösterilebilir Türkçe açıklama.
  String get message => _message ?? _defaultMessage();

  String _defaultMessage() => switch (kind) {
        GoogleHealthErrorKind.notConfigured =>
          'Google ile bağlantı bu derlemede yapılandırılmamış.',
        GoogleHealthErrorKind.notConnected => 'Google Health bağlı değil.',
        GoogleHealthErrorKind.reconnect =>
          'Google oturumunun süresi doldu. Google\'a yeniden bağlan.',
        GoogleHealthErrorKind.missingScope =>
          'Google Health izni eksik. Google\'a yeniden bağlanıp adım, uyku '
              've aktivite izinlerini onayla.',
        GoogleHealthErrorKind.configuration =>
          'Google Health API, Google Cloud projesinde etkin değil ya da '
              'yapılandırma hatalı.',
        GoogleHealthErrorKind.rateLimited =>
          'Google Health şu an yoğun. Biraz sonra tekrar dene.',
        GoogleHealthErrorKind.unavailable =>
          'Google Health şu an yanıt vermiyor. Biraz sonra tekrar dene.',
        GoogleHealthErrorKind.network =>
          'Google Health\'e ulaşılamadı. İnternet bağlantını kontrol et.',
        GoogleHealthErrorKind.invalidResponse =>
          'Google Health yanıtı okunamadı.',
        GoogleHealthErrorKind.requestRejected =>
          'Google Health isteği reddetti (HTTP ${status ?? '?'}).',
      };

  @override
  String toString() => message;
}

/// Hata yanıtını ([status], gövde, başlıklar) türüne çevirir. Google API
/// hataları `{"error": {"code", "message", "status", "details": [ErrorInfo]}}`
/// biçimindedir; kapsam eksikliği ErrorInfo `reason` alanından ya da
/// `WWW-Authenticate: ... error="insufficient_scope"` başlığından anlaşılır.
GoogleHealthException googleHealthErrorFor(
  int status,
  String body, {
  Map<String, String> headers = const {},
}) {
  final reasons = <String>{};
  var apiMessage = '';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        apiMessage = '${error['message'] ?? ''}'.toLowerCase();
        final details = error['details'];
        if (details is List) {
          for (final detail in details) {
            if (detail is Map<String, dynamic> && detail['reason'] is String) {
              reasons.add((detail['reason'] as String).toUpperCase());
            }
          }
        }
      }
    }
  } on FormatException {
    // Gövde JSON değil (ör. vekil sunucu sayfası); yalnızca kod kullanılır.
  }
  final authenticate = (headers['www-authenticate'] ?? '').toLowerCase();

  if (status == 401) {
    return const GoogleHealthException(GoogleHealthErrorKind.reconnect,
        status: 401);
  }
  if (status == 403) {
    final scopeMissing = reasons.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT') ||
        reasons.contains('MISSING_OAUTH_SCOPE') ||
        reasons.contains('INSUFFICIENT_SCOPE') ||
        authenticate.contains('insufficient_scope') ||
        apiMessage.contains('insufficient authentication scopes');
    if (scopeMissing) {
      return const GoogleHealthException(GoogleHealthErrorKind.missingScope,
          status: 403);
    }
    final disabled = reasons.contains('SERVICE_DISABLED') ||
        reasons.contains('API_DISABLED') ||
        reasons.contains('ACCESS_NOT_CONFIGURED') ||
        apiMessage.contains('has not been used in project') ||
        apiMessage.contains('it is disabled');
    if (disabled) {
      return const GoogleHealthException(GoogleHealthErrorKind.configuration,
          status: 403);
    }
    return const GoogleHealthException(GoogleHealthErrorKind.reconnect,
        status: 403);
  }
  if (status == 429) {
    return const GoogleHealthException(GoogleHealthErrorKind.rateLimited,
        status: 429);
  }
  if (status >= 500) {
    return GoogleHealthException(GoogleHealthErrorKind.unavailable,
        status: status);
  }
  return GoogleHealthException(GoogleHealthErrorKind.requestRejected,
      status: status);
}

/// Bir uyku oturumu ve içindeki uyku (uyanık olmayan) bölümleri.
class GoogleSleepSession {
  const GoogleSleepSession({
    required this.start,
    required this.end,
    required this.asleep,
  });

  final DateTime start;
  final DateTime end;

  /// LIGHT, DEEP, REM ve ASLEEP evreleri (AWAKE ve RESTLESS hariç; HealthKit
  /// yolunun SLEEP_ASLEEP/LIGHT/DEEP/REM seçimiyle aynı). Evresi olmayan
  /// oturumda (ör. elle girilmiş uyku) oturumun tamamıdır.
  final List<(DateTime, DateTime)> asleep;
}

/// Bir antrenman (exercise) oturumu.
class GoogleExercise {
  const GoogleExercise({
    required this.id,
    required this.exerciseType,
    required this.start,
    required this.end,
    this.displayName,
    this.activeDuration,
    this.distanceMeters,
    this.caloriesKcal,
    this.notes,
    this.createTime,
  });

  /// Veri noktasının kimliği (`.../dataPoints/{id}` son parçası); adı yoksa
  /// başlangıç anı ve türden türetilir. İçe aktarmada tekilleştirme anahtarı.
  final String id;

  /// `RUNNING`, `WEIGHTLIFTING`, `SOCCER` …
  final String exerciseType;
  final DateTime start;
  final DateTime end;
  final String? displayName;

  /// Duraklamalar hariç süre.
  final Duration? activeDuration;
  final double? distanceMeters;
  final double? caloriesKcal;
  final String? notes;

  /// Google Health'te oluşturulma anı (içe aktarma işareti için).
  final DateTime? createTime;
}

/// Google Health API REST istemcisi (`https://health.googleapis.com/v4/`).
/// Her istek [accessToken] ile alınan anahtarı taşır; [client] testlerde
/// `MockClient` ile değiştirilir.
class GoogleHealthApi {
  GoogleHealthApi({
    required this.accessToken,
    http.Client? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        baseUri = baseUri ?? defaultBaseUri;

  static final Uri defaultBaseUri =
      Uri.parse('https://health.googleapis.com/v4/');

  /// `dailyRollUp` tek istekte en çok 90 günü kapsar.
  static const int maxRollUpDays = 90;

  /// `list` için uyku ve antrenmanda sayfa boyu üst sınırı 25'tir.
  static const int sessionPageSize = 25;

  /// Sonsuz sayfalamaya karşı üst sınır.
  static const int maxPages = 200;

  final Future<String> Function() accessToken;
  final Uri baseUri;
  final Duration timeout;
  final http.Client _client;

  void close() => _client.close();

  /// [from] gününden (yerel gün başı) [to] anına kadar günlük adım toplamı.
  /// Anahtar yerel gün başıdır; verisi olmayan gün listede yer almaz.
  Future<Map<DateTime, int>> dailySteps({
    required DateTime from,
    required DateTime to,
  }) async {
    final points = await _dailyRollUp('steps', from, to);
    return {
      for (final (day, point) in points)
        day: _toInt((point['steps'] as Map?)?['countSum']),
    };
  }

  /// [from] gününden [to] anına kadar günlük aktif kalori (kcal) toplamı.
  Future<Map<DateTime, double>> dailyActiveKcal({
    required DateTime from,
    required DateTime to,
  }) async {
    final points = await _dailyRollUp('active-energy-burned', from, to);
    return {
      for (final (day, point) in points)
        day: _toDouble((point['activeEnergyBurned'] as Map?)?['kcalSum']),
    };
  }

  /// Bitişi `[endFrom, endTo)` aralığına düşen uyku oturumları. Uyku `list`
  /// yalnızca bitiş zamanıyla süzülebilir; pencereyle kesişen her oturumu
  /// almak için çağıran, aralığı bir gün geniş verir.
  Future<List<GoogleSleepSession>> sleepSessions({
    required DateTime endFrom,
    required DateTime endTo,
  }) async {
    final filter = 'sleep.interval.end_time >= "${rfc3339(endFrom)}" AND '
        'sleep.interval.end_time < "${rfc3339(endTo)}"';
    final points = await _list('sleep', filter);
    return [
      for (final point in points)
        if (_parseSleep(point['sleep']) case final session?) session,
    ];
  }

  /// Başlangıcı `[fromDay, toDay)` yerel takvim günlerine düşen antrenmanlar.
  Future<List<GoogleExercise>> exercises({
    required DateTime fromDay,
    required DateTime toDay,
  }) async {
    final filter =
        'exercise.interval.civil_start_time >= "${civilDate(fromDay)}" AND '
        'exercise.interval.civil_start_time < "${civilDate(toDay)}"';
    final points = await _list('exercise', filter);
    return [
      for (final point in points)
        if (_parseExercise(point) case final exercise?) exercise,
    ];
  }

  // ------------------------------------------------------------ istekler

  Future<List<(DateTime, Map<String, dynamic>)>> _dailyRollUp(
    String dataType,
    DateTime from,
    DateTime to,
  ) async {
    final uri =
        baseUri.resolve('users/me/dataTypes/$dataType/dataPoints:dailyRollUp');
    final result = <(DateTime, Map<String, dynamic>)>[];
    var chunkStart = DateTime(from.year, from.month, from.day);
    while (chunkStart.isBefore(to)) {
      final limit = DateTime(
        chunkStart.year,
        chunkStart.month,
        chunkStart.day + maxRollUpDays,
      );
      final chunkEnd = limit.isBefore(to) ? limit : to;
      String? pageToken;
      final seen = <String>{};
      for (var page = 0; page < maxPages; page++) {
        final response = await _send(
          'POST',
          uri,
          body: {
            'range': {
              'start': civilDateTime(chunkStart),
              'end': civilDateTime(chunkEnd),
            },
            'windowSizeDays': 1,
            'pageSize': maxRollUpDays,
            if (pageToken != null) 'pageToken': pageToken,
          },
        );
        final points = response['rollupDataPoints'];
        if (points != null && points is! List) {
          throw const GoogleHealthException(
            GoogleHealthErrorKind.invalidResponse,
          );
        }
        for (final point in (points as List?) ?? const []) {
          if (point is! Map<String, dynamic>) continue;
          final day = _civilDay(point['civilStartTime']);
          if (day != null) result.add((day, point));
        }
        pageToken = _nextToken(response, seen);
        if (pageToken == null) break;
      }
      chunkStart = chunkEnd;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _list(
    String dataType,
    String filter,
  ) async {
    final result = <Map<String, dynamic>>[];
    String? pageToken;
    final seen = <String>{};
    for (var page = 0; page < maxPages; page++) {
      final uri = baseUri
          .resolve('users/me/dataTypes/$dataType/dataPoints')
          .replace(queryParameters: {
        'filter': filter,
        'pageSize': '$sessionPageSize',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final response = await _send('GET', uri);
      final points = response['dataPoints'];
      if (points != null && points is! List) {
        throw const GoogleHealthException(
          GoogleHealthErrorKind.invalidResponse,
        );
      }
      for (final point in (points as List?) ?? const []) {
        if (point is Map<String, dynamic>) result.add(point);
      }
      pageToken = _nextToken(response, seen);
      if (pageToken == null) break;
    }
    return result;
  }

  /// Boş ya da daha önce görülmüş anahtar sayfalamayı bitirir.
  static String? _nextToken(Map<String, dynamic> response, Set<String> seen) {
    final token = response['nextPageToken'];
    if (token is! String || token.isEmpty || !seen.add(token)) return null;
    return token;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await accessToken();
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on Exception {
      // ClientException (soket, TLS), zaman aşımı: bağlantı sorunu.
      throw const GoogleHealthException(GoogleHealthErrorKind.network);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw googleHealthErrorFor(
        response.statusCode,
        text,
        headers: response.headers,
      );
    }
    if (text.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Aşağıda geçersiz yanıt sayılır.
    }
    throw GoogleHealthException(
      GoogleHealthErrorKind.invalidResponse,
      status: response.statusCode,
    );
  }

  // ------------------------------------------------------------ biçimler

  /// RFC 3339, UTC, saniye hassasiyetinde: `2026-11-16T15:00:00Z`.
  static String rfc3339(DateTime time) {
    final u = time.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }

  /// Yerel takvim günü: `2026-11-16`.
  static String civilDate(DateTime day) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-'
        '${two(day.day)}';
  }

  /// `CivilDateTime` JSON'u; gece yarısında saat alanı yazılmaz.
  static Map<String, dynamic> civilDateTime(DateTime local) => {
        'date': {'year': local.year, 'month': local.month, 'day': local.day},
        if (local.hour != 0 || local.minute != 0 || local.second != 0)
          'time': {
            'hours': local.hour,
            'minutes': local.minute,
            'seconds': local.second,
          },
      };

  static DateTime? _civilDay(Object? civil) {
    if (civil is! Map) return null;
    final date = civil['date'];
    if (date is! Map) return null;
    final year = _toInt(date['year']);
    final month = _toInt(date['month']);
    final day = _toInt(date['day']);
    if (year <= 0 || month <= 0 || day <= 0) return null;
    return DateTime(year, month, day);
  }

  static GoogleSleepSession? _parseSleep(Object? raw) {
    if (raw is! Map) return null;
    final interval = raw['interval'];
    if (interval is! Map) return null;
    final start = _time(interval['startTime']);
    final end = _time(interval['endTime']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    final stages = raw['stages'];
    final asleep = <(DateTime, DateTime)>[];
    if (stages is List && stages.isNotEmpty) {
      for (final stage in stages) {
        if (stage is! Map || !_asleepStages.contains(stage['type'])) continue;
        final s = _time(stage['startTime']);
        final e = _time(stage['endTime']);
        if (s != null && e != null && e.isAfter(s)) asleep.add((s, e));
      }
    } else {
      asleep.add((start, end));
    }
    return GoogleSleepSession(start: start, end: end, asleep: asleep);
  }

  static const Set<String> _asleepStages = {'LIGHT', 'DEEP', 'REM', 'ASLEEP'};

  static GoogleExercise? _parseExercise(Map<String, dynamic> point) {
    final raw = point['exercise'];
    if (raw is! Map) return null;
    final interval = raw['interval'];
    if (interval is! Map) return null;
    final start = _time(interval['startTime']);
    final end = _time(interval['endTime']);
    if (start == null || end == null) return null;
    final type =
        raw['exerciseType'] is String ? raw['exerciseType'] as String : 'OTHER';
    final name = point['name'];
    final id = name is String && name.contains('/dataPoints/')
        ? name.substring(name.lastIndexOf('/') + 1)
        : '${rfc3339(start)}-$type';
    final summary = raw['metricsSummary'];
    final distanceMm = summary is Map
        ? _toNullableDouble(summary['distanceMillimeters'])
        : null;
    return GoogleExercise(
      id: id,
      exerciseType: type,
      start: start,
      end: end,
      displayName:
          raw['displayName'] is String ? raw['displayName'] as String : null,
      activeDuration: _duration(raw['activeDuration']),
      distanceMeters: distanceMm == null ? null : distanceMm / 1000,
      caloriesKcal:
          summary is Map ? _toNullableDouble(summary['caloriesKcal']) : null,
      notes: raw['notes'] is String ? raw['notes'] as String : null,
      createTime: _time(raw['createTime']),
    );
  }

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  /// `google-duration`: "3600s", "1834.250s".
  static Duration? _duration(Object? raw) {
    if (raw is! String || !raw.endsWith('s')) return null;
    final seconds = double.tryParse(raw.substring(0, raw.length - 1));
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// int64 alanları JSON'da metin olarak gelir ("1234").
  static int _toInt(Object? raw) => switch (raw) {
        final int v => v,
        final num v => v.round(),
        final String v => int.tryParse(v) ?? double.tryParse(v)?.round() ?? 0,
        _ => 0,
      };

  static double _toDouble(Object? raw) => _toNullableDouble(raw) ?? 0;

  static double? _toNullableDouble(Object? raw) {
    final value = switch (raw) {
      final num v => v.toDouble(),
      final String v => double.tryParse(v),
      _ => null,
    };
    return value == null || !value.isFinite ? null : value;
  }
}
