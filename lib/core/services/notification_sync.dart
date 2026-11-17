import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/operations/data/tasks_repository.dart';
import '../../features/routines/data/routines_repository.dart';
import '../../features/routines/domain/routine.dart';
import '../../features/settings/domain/user_settings.dart';
import '../../features/settings/presentation/settings_providers.dart';
import 'notification_plan.dart';
import 'notification_service.dart';
import 'supabase_providers.dart';

export 'notification_plan.dart';

/// Bildirim izninin güncel durumu. Yalnızca okur; izin penceresi açmaz
/// (Ayarlar'ı açmak kullanıcıya izin sorusu göstermemeli).
final notificationPermissionProvider = FutureProvider<bool>(
  (ref) => ref.watch(notificationServiceProvider).hasPermission(),
);

/// Eşitleme turlarının eklenti çağrılarını tek sıraya dizer ve oturum
/// bitince süren turları geçersiz kılar.
final notificationSyncQueueProvider =
    Provider<NotificationSyncQueue>((ref) => NotificationSyncQueue());

class NotificationSyncQueue {
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  /// Oturum her bittiğinde artar. Bir tur başladığı nesli saklar; nesil
  /// değiştiyse (çıkış ya da hesap değişimi) eklentiye hiç dokunmaz.
  int get generation => _generation;

  /// [apply]'ı önceki turun eklenti çağrıları bittikten sonra çalıştırır;
  /// tur o ana dek bayatladıysa ([isCurrent] `false`) hiç çalıştırmaz.
  Future<void> run(bool Function() isCurrent, Future<void> Function() apply) {
    final result = _tail.then((_) async {
      if (isCurrent()) await apply();
    });
    // Bir turun hatası sıradakileri kilitlemez; hatayı çağıran görür.
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Oturum bitti: veri sorgulamadan süren turları geçersiz kılar ve bekleyen
  /// tüm bildirimleri aynı sıradan siler (önce kuyruğa girmiş eski tur bile
  /// bu silmeden sonra yeniden planlayamaz). Tekrar çağrılması zararsızdır.
  Future<void> endSession(NotificationService notifications) {
    _generation++;
    return run(
      () => true,
      () => notifications.resync(routines: const [], reminders: const []),
    );
  }
}

/// Oturum kapanınca ya da kullanıcı değişince bekleyen bildirimleri siler.
/// Kök kapı (AuthGate) dinler; ana kabuk kapandıktan sonra da çalışır.
final notificationSessionGuardProvider = Provider<void>((ref) {
  final queue = ref.watch(notificationSyncQueueProvider);
  ref.listen<String?>(
    authSessionProvider.select((s) => s.valueOrNull?.user.id),
    (previous, next) {
      if (previous == null || previous == next) return;
      // Servis yalnızca gerektiğinde okunur (kök kapı onsuz da kurulabilsin).
      queue
          .endSession(ref.read(notificationServiceProvider))
          .catchError((Object _) {});
    },
  );
});

/// Bekleyen bildirimleri ayarlar ve veritabanıyla eşitler.
/// Oturum (kullanıcı) başına bir kez çalışır; ayar, görev ya da aylık iş
/// değişince yenilenir.
final notificationSyncProvider = FutureProvider<void>((ref) async {
  final notifications = ref.watch(notificationServiceProvider);
  final routinesRepository = ref.watch(routinesRepositoryProvider);
  final tasksRepository = ref.watch(tasksRepositoryProvider);
  final queue = ref.watch(notificationSyncQueueProvider);

  // Riverpod, sağlayıcı tazelenince süren turu durdurmaz. Bayatlayan tur
  // eklentiye dokunmaz; yoksa yenisinden sonra bitip eski veriyi geri planlar.
  // Oturum biterse ([NotificationSyncQueue.endSession]) nesil değişir ve tur
  // yine eklentiye dokunmaz.
  var alive = true;
  ref.onDispose(() => alive = false);
  final generation = queue.generation;
  bool current() => alive && queue.generation == generation;

  UserSettings settings;
  try {
    settings = await ref.watch(userSettingsProvider.future);
  } catch (_) {
    // Ayarlar okunamazsa hatırlatmalar kaybolmasın diye varsayılanla sürer.
    settings = const UserSettings.defaults();
  }

  if (!settings.notificationsEnabled) {
    // Kapalıyken bekleyenlerin tamamı silinir; izin de sorulmaz.
    await queue.run(
      current,
      () => notifications.resync(routines: const [], reminders: const []),
    );
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

  await queue.run(current, () async {
    await notifications.resync(
      routines: routineSchedulesOf(plan, routines),
      reminders: [
        for (final p in plan)
          if (p.kind == PlannedKind.task) _reminderOf(p),
      ],
    );
    // resync bekleyenleri sildiği için aylık tek seferlikler ondan sonra eklenir.
    for (final p in plan) {
      if (p.kind == PlannedKind.monthlyLead ||
          p.kind == PlannedKind.monthlyDue) {
        await notifications.scheduleReminder(_reminderOf(p));
      }
    }
  });
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
