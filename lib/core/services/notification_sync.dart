import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/operations/data/tasks_repository.dart';
import '../../features/routines/data/routines_repository.dart';
import '../../features/routines/domain/routine.dart';
import '../../features/settings/domain/user_settings.dart';
import '../../features/settings/presentation/settings_providers.dart';
import 'notification_plan.dart';
import 'notification_service.dart';

export 'notification_plan.dart';

/// Bildirim izninin güncel durumu. iOS'ta daha önce yanıtlandıysa pencere
/// açılmaz, yalnızca mevcut karar döner.
final notificationPermissionProvider = FutureProvider<bool>(
  (ref) => ref.watch(notificationServiceProvider).requestPermission(),
);

/// Bekleyen bildirimleri ayarlar ve veritabanıyla eşitler.
/// Oturum (kullanıcı) başına bir kez çalışır; ayar, görev ya da aylık iş
/// değişince yenilenir.
final notificationSyncProvider = FutureProvider<void>((ref) async {
  final notifications = ref.watch(notificationServiceProvider);
  final routinesRepository = ref.watch(routinesRepositoryProvider);
  final tasksRepository = ref.watch(tasksRepositoryProvider);

  UserSettings settings;
  try {
    settings = await ref.watch(userSettingsProvider.future);
  } catch (_) {
    // Ayarlar okunamazsa hatırlatmalar kaybolmasın diye varsayılanla sürer.
    settings = const UserSettings.defaults();
  }

  if (!settings.notificationsEnabled) {
    // Kapalıyken bekleyenlerin tamamı silinir; izin de sorulmaz.
    await notifications.resync(routines: const [], reminders: const []);
    return;
  }

  final granted = await notifications.requestPermission();
  if (!granted) return;

  final now = DateTime.now();
  final routines = await routinesRepository.fetchActive();
  final hasMonthly = routines.any((r) => r.isMonthly);
  // Aylık dönem anahtarı ayın 1'idir: bu ay ve gelecek ay.
  final completions = hasMonthly
      ? await routinesRepository.fetchCompletions(
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1),
        )
      : const <RoutineCompletionKey>{};
  final tasks = await tasksRepository.fetchOpen();

  final plan = buildNotificationPlan(
    now: now,
    settings: settings,
    routines: routines,
    completions: completions,
    tasks: tasks,
  );

  await notifications.resync(
    routines: routineSchedulesOf(plan, routines),
    reminders: [
      for (final p in plan)
        if (p.kind == PlannedKind.task) _reminderOf(p),
    ],
  );
  // resync bekleyenleri sildiği için aylık tek seferlikler ondan sonra eklenir.
  for (final p in plan) {
    if (p.kind == PlannedKind.monthlyLead || p.kind == PlannedKind.monthlyDue) {
      await notifications.scheduleReminder(_reminderOf(p));
    }
  }
});

ReminderSchedule _reminderOf(PlannedNotification p) => ReminderSchedule(
      taskId: p.sourceId,
      title: p.title,
      when: p.fireAt,
      body: p.body,
      key: p.kind == PlannedKind.task ? null : p.key,
    );

/// Plandaki tekrar eden bildirimleri rutin başına tek kayıtta toplar
/// ([routines] sırası korunur). Saat ve günler plandaki — sessiz saate göre
/// kaydırılmış — değerlerdir.
List<RoutineSchedule> routineSchedulesOf(
  List<PlannedNotification> plan,
  List<Routine> routines,
) {
  final result = <RoutineSchedule>[];
  for (final r in routines) {
    final items = [
      for (final p in plan)
        if (p.isRepeating && p.sourceId == r.id) p,
    ];
    if (items.isEmpty) continue;
    final daily = items.any((p) => p.repeat == PlannedRepeat.daily);
    final days = {for (final p in items) p.fireAt.weekday}.toList()..sort();
    result.add(
      RoutineSchedule(
        routineId: r.id,
        title: r.title,
        hour: items.first.fireAt.hour,
        minute: items.first.fireAt.minute,
        daysOfWeek: daily ? Routine.everyDay : days,
      ),
    );
  }
  return result;
}
