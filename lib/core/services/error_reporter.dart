import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama sürümü (Codemagic `--dart-define=APP_VERSION=...` ile verir).
const String appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

/// "1.2.0+14" biçimini "1.2.0 (14)" olarak gösterir; yapı numarası yoksa
/// sürüm olduğu gibi döner.
String appVersionLabel(String version) {
  final parts = version.split('+');
  if (parts.length != 2 || parts[1].isEmpty) return version;
  return '${parts[0]} (${parts[1]})';
}

/// Sunucuya gidecek tek hata kaydı (`public.app_errors`).
class ErrorReport {
  const ErrorReport({
    required this.message,
    required this.stack,
    required this.appVersion,
    required this.platform,
  });

  static const int maxMessage = 2000;
  static const int maxStack = 8000;

  final String message;
  final String? stack;
  final String appVersion;
  final String platform;

  Map<String, Object?> toRow() => {
        'message': message,
        'stack': stack,
        'app_version': appVersion,
        'platform': platform,
      };
}

/// Yakalanmamış hataları toplar ve [send] ile gönderir. Asla fırlatmaz:
/// aynı hata [dedupWindow] içinde bir kez, cihaz başına 24 saatte en çok
/// [maxPerDay] kayıt gönderilir (sunucu ayrıca günde 50 ile sınırlar).
/// Kayıtlar [debounce] süresince biriktirilip birlikte gönderilir.
class ErrorReporter {
  ErrorReporter({
    required this.send,
    DateTime Function()? now,
    this.maxPerDay = 20,
    this.dedupWindow = const Duration(minutes: 10),
    this.debounce = const Duration(seconds: 2),
    this.platform = 'unknown',
    this.version = appVersion,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function(List<ErrorReport> reports) send;
  final DateTime Function() _now;
  final int maxPerDay;
  final Duration dedupWindow;
  final Duration debounce;
  final String platform;
  final String version;

  final Map<String, DateTime> _lastSeen = {};
  final List<DateTime> _sentTimes = [];
  final List<ErrorReport> _pending = [];
  Timer? _timer;

  /// [install] edilen etkin raporlayıcı; yoksa (test, hata ayıklama) null.
  static ErrorReporter? current;

  /// Bekleyen kayıt sayısı (test için).
  int get pendingCount => _pending.length;

  /// Hatayı kuyruğa alır; alındıysa `true`. Tekrar ya da sınır aşımında `false`.
  bool report(Object error, StackTrace? stack) {
    try {
      final now = _now();
      final message = _clip(scrubMessage(error), ErrorReport.maxMessage);
      final stackText = stack == null || stack.toString().isEmpty
          ? null
          : _clip(stack.toString(), ErrorReport.maxStack);
      final key = '$message\n${_firstFrame(stackText)}';

      final seen = _lastSeen[key];
      if (seen != null && now.difference(seen) < dedupWindow) return false;

      _sentTimes.removeWhere(
        (t) => now.difference(t) >= const Duration(hours: 24),
      );
      if (_sentTimes.length >= maxPerDay) return false;

      _lastSeen[key] = now;
      if (_lastSeen.length > 200) {
        _lastSeen.removeWhere((_, t) => now.difference(t) >= dedupWindow);
      }
      _sentTimes.add(now);
      _pending.add(
        ErrorReport(
          message: message.isEmpty ? 'Bilinmeyen hata' : message,
          stack: stackText,
          appVersion: version,
          platform: platform,
        ),
      );
      _timer?.cancel();
      _timer = Timer(debounce, () => unawaited(flush()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Bekleyenleri hemen gönderir; gönderim hatası yutulur.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = List<ErrorReport>.of(_pending);
    _pending.clear();
    try {
      await send(batch);
    } catch (_) {}
  }

  /// Flutter, platform ve zone hatalarını bu raporlayıcıya bağlar.
  void install() {
    current = this;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      report(details.exception, details.stack);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static final RegExp _doubleQuoted = RegExp(r'"[^"\n]*"');
  static final RegExp _singleQuoted = RegExp(r"'[^'\n]*'");

  /// Hata metninden kullanıcının yazdığı değerler sızmasın: tırnak içindeki
  /// değerler silinir; sunucu/biçim hatalarında yalnızca tür ve ilk satır
  /// tutulur (gizlilik politikası, SEC-12).
  static String scrubMessage(Object error) {
    var text = error.toString();
    if (error is PostgrestException || error is FormatException) {
      text = '${error.runtimeType}: ${text.split('\n').first}';
    }
    return text
        .replaceAll(_doubleQuoted, '"…"')
        .replaceAll(_singleQuoted, "'…'");
  }

  static String _firstFrame(String? stack) {
    if (stack == null) return '';
    final line = stack.split('\n').firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    return line.trim();
  }
}

/// Testte ya da hata ayıklama oturumunda raporlama yapılmaz.
bool get errorReportingEnabled {
  if (kDebugMode) return false;
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Supabase'e yazan raporlayıcı: oturum yoksa hiçbir şey gönderilmez.
ErrorReporter supabaseErrorReporter(SupabaseClient client) {
  String platform;
  try {
    platform = Platform.operatingSystem;
  } catch (_) {
    platform = 'unknown';
  }
  return ErrorReporter(
    platform: platform,
    send: (reports) async {
      if (client.auth.currentUser == null) return;
      await client
          .from('app_errors')
          .insert([for (final r in reports) r.toRow()]).timeout(
              const Duration(seconds: 10));
    },
  );
}

/// Yakalanmış ama sessiz geçilmemesi gereken hataları bildirir. Varsayılan:
/// etkin [ErrorReporter] (yoksa hiçbir şey yapmaz); testte değiştirilebilir.
typedef ReportError = void Function(Object error, StackTrace? stack);

final reportErrorProvider = Provider<ReportError>(
  (ref) => (error, stack) => ErrorReporter.current?.report(error, stack),
);
