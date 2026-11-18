import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reminder.dart';

/// Bildirimdeki "Yaptım" eylemi: hangi hatırlatıcı, kimin adına, hangi gün.
class ReminderDoneAction {
  const ReminderDoneAction({
    required this.reminderId,
    required this.ownerId,
    required this.day,
  });

  final String reminderId;
  final String ownerId;
  final DateTime day;

  static ReminderDoneAction? fromPayload(String? payload, DateTime at) {
    final parsed = ReminderPayload.tryParse(payload);
    if (parsed == null) return null;
    return ReminderDoneAction(
      reminderId: parsed.reminderId,
      ownerId: parsed.ownerId,
      day: reminderDay(at),
    );
  }

  Map<String, dynamic> toJson() => {
        'r': reminderId,
        'o': ownerId,
        'd': '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
      };

  static ReminderDoneAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final r = json['r'];
    final o = json['o'];
    final d = json['d'];
    if (r is! String || o is! String || d is! String) return null;
    final day = DateTime.tryParse(d);
    if (day == null) return null;
    return ReminderDoneAction(reminderId: r, ownerId: o, day: day);
  }
}

/// "Yaptım" eylemlerinin kalıcı gelen kutusu. Uygulama arka planda ya da
/// kapalıyken gelen eylemler (ayrı isolate) buraya yazılır; uygulama
/// açılınca/ön plana gelince oturumdaki kullanıcıya göre işlenir.
/// Ön plandaki eylemler [live] akışından da anında gelir.
class ReminderActionInbox {
  ReminderActionInbox._();

  static const String _key = 'reminder_done_inbox_v1';
  static const int _maxItems = 50;

  static final StreamController<void> _live =
      StreamController<void>.broadcast();

  /// Yeni eylem kutuya yazıldı (aynı isolate).
  static Stream<void> get live => _live.stream;

  static Future<void> add(ReminderDoneAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final items = prefs.getStringList(_key) ?? <String>[];
    items.add(jsonEncode(action.toJson()));
    final trimmed = items.length > _maxItems
        ? items.sublist(items.length - _maxItems)
        : items;
    await prefs.setStringList(_key, trimmed);
    if (!_live.isClosed) _live.add(null);
  }

  /// Kutudaki eylemleri alır ve kutuyu boşaltır.
  static Future<List<ReminderDoneAction>> drain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final items = prefs.getStringList(_key) ?? const <String>[];
    if (items.isEmpty) return const [];
    await prefs.remove(_key);
    final result = <ReminderDoneAction>[];
    for (final raw in items) {
      try {
        final action = ReminderDoneAction.fromJson(jsonDecode(raw));
        if (action != null) result.add(action);
      } on FormatException {
        continue;
      }
    }
    return result;
  }
}
