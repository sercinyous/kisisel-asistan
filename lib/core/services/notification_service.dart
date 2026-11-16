import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_plan.dart';

/// main() içinde `init()` edilmiş örnek ProviderScope override'ı ile verilir.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider main() içinde override edilmelidir.',
  ),
);

/// Sabit rutin bildirimi için gereken en küçük veri.
class RoutineSchedule {
  const RoutineSchedule({
    required this.routineId,
    required this.title,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
  });

  final String routineId;
  final String title;
  final int hour;
  final int minute;

  /// ISO gün numaraları (1 = Pazartesi ... 7 = Pazar).
  final List<int> daysOfWeek;
}

/// Tek seferlik saatli hatırlatma.
class ReminderSchedule {
  const ReminderSchedule({
    required this.taskId,
    required this.title,
    required this.when,
    this.body,
    this.key,
  });

  final String taskId;
  final String title;
  final DateTime when;
  final String? body;

  /// Bildirim kimliğinin türetildiği anahtar; boşsa `task:<taskId>`.
  /// Aylık iş hatırlatmaları kendi anahtarlarını verir.
  final String? key;

  String get effectiveKey => key ?? 'task:$taskId';
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const int _maxPending = maxPendingNotifications;

  static const NotificationDetails _details = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
    android: AndroidNotificationDetails(
      'asistan_hatirlatma',
      'Hatırlatmalar',
      channelDescription: 'Saatli hatırlatmalar ve sabit rutin bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> init() async {
    if (!_supported || _ready) return;

    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    }

    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _ready = true;
  }

  /// İzin durumunu pencere açmadan okur; Ayarlar ekranı yalnızca durumu
  /// göstereceği için izin istemez.
  Future<bool> hasPermission() async {
    if (!_ready) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return (await ios.checkPermissions())?.isEnabled ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// iOS izin penceresini gösterir (daha önce yanıtlandıysa sessizce döner).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Tek bir görev hatırlatması planlar. Geçmiş saatler yok sayılır.
  Future<void> scheduleReminder(ReminderSchedule reminder) async {
    if (!_ready) return;
    final when = tz.TZDateTime.from(reminder.when, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      _stableId(reminder.effectiveKey),
      reminder.title,
      reminder.body ?? 'Hatırlatma zamanı',
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.effectiveKey,
    );
  }

  Future<void> cancelReminder(String taskId) async {
    if (!_ready) return;
    await _plugin.cancel(_stableId('task:$taskId'));
  }

  /// Bekleyen bildirimleri siler ve verilen planı uygular. Listeler
  /// `buildNotificationPlan` çıktısından gelir (sessiz saat ve sınır orada
  /// hesaplanır); silinmiş rutin/görevlerin bildirimleri de böylece temizlenir.
  Future<void> resync({
    required List<RoutineSchedule> routines,
    required List<ReminderSchedule> reminders,
  }) async {
    if (!_ready) return;
    // Yalnızca bekleyenler silinir; teslim edilmiş bildirimler
    // Bildirim Merkezi'nde kalır.
    await _plugin.cancelAllPendingNotifications();

    var used = 0;
    for (final routine in routines) {
      final everyDay = routine.daysOfWeek.toSet().length == 7;
      if (everyDay) {
        if (used >= _maxPending) break;
        await _plugin.zonedSchedule(
          _stableId('routine:${routine.routineId}'),
          routine.title,
          'Günlük rutin zamanı',
          _nextTime(routine.hour, routine.minute),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'routine:${routine.routineId}',
        );
        used++;
        continue;
      }
      for (final weekday in routine.daysOfWeek.toSet()) {
        if (used >= _maxPending) break;
        await _plugin.zonedSchedule(
          _stableId('routine:${routine.routineId}:$weekday'),
          routine.title,
          'Bugünün rutini',
          _nextWeekdayTime(weekday, routine.hour, routine.minute),
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: 'routine:${routine.routineId}',
        );
        used++;
      }
    }

    final upcoming = [...reminders]..sort((a, b) => a.when.compareTo(b.when));
    for (final reminder in upcoming) {
      if (used >= _maxPending) break;
      if (!reminder.when.isAfter(DateTime.now())) continue;
      await scheduleReminder(reminder);
      used++;
    }
  }

  tz.TZDateTime _nextTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    var next = _nextTime(hour, minute);
    while (next.weekday != weekday) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static int _stableId(String key) => stableNotificationId(key);
}
