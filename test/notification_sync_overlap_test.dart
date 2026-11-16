// Üst üste binen eşitleme turları: eski (bayat) tur, yenisinden sonra bitse
// bile bekleyen bildirimleri bozmamalı.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';

import 'helpers/fakes.dart';

/// Bekleyen bildirim kümesini gerçek servis gibi tutar: `resync` önce hepsini
/// siler, sonra tek tek planlar; her eklenti çağrısı bir olay döngüsü turu sürer.
class _PendingNotifications extends FakeNotificationService {
  final Set<String> pending = {};

  /// Doluysa her eklenti çağrısından sonra çağrılır (araya iş sokmak için).
  void Function()? afterCall;

  Future<void> _platformCall() async {
    await Future<void>.delayed(Duration.zero);
    afterCall?.call();
  }

  @override
  Future<void> scheduleReminder(ReminderSchedule reminder) async {
    await _platformCall();
    pending.add(reminder.effectiveKey);
  }

  @override
  Future<void> resync({
    required List<RoutineSchedule> routines,
    required List<ReminderSchedule> reminders,
  }) async {
    await super.resync(routines: routines, reminders: reminders);
    await _platformCall();
    pending.clear();
    for (final r in routines) {
      await _platformCall();
      pending.add('routine:${r.routineId}');
    }
    for (final r in reminders) {
      await scheduleReminder(r);
    }
  }
}

/// `fetchOpen` yanıtını (istek anındaki veriyle) [nextReadGate] tamamlanana
/// kadar bekletir: ağda takılan eski okuma.
class _GatedTasksRepository extends FakeTasksRepository {
  _GatedTasksRepository({super.tasks});

  Completer<void>? nextReadGate;
  int reads = 0;

  @override
  Future<List<TaskItem>> fetchOpen() async {
    reads++;
    final snapshot = await super.fetchOpen();
    final gate = nextReadGate;
    nextReadGate = null;
    if (gate != null) await gate.future;
    return snapshot;
  }
}

/// `fetchCompletions` yanıtını aynı şekilde bekletir.
class _GatedRoutinesRepository extends FakeRoutinesRepository {
  Completer<void>? nextReadGate;
  int completionReads = 0;

  @override
  Future<Set<RoutineCompletionKey>> fetchCompletions(
    DateTime from,
    DateTime to,
  ) async {
    completionReads++;
    final snapshot = await super.fetchCompletions(from, to);
    final gate = nextReadGate;
    nextReadGate = null;
    if (gate != null) await gate.future;
    return snapshot;
  }
}

TaskItem _task(String id) => TaskItem(
      id: id,
      title: 'Görev $id',
      category: 'Kişisel',
      priority: 'medium',
      status: 'todo',
      remindAt: DateTime(2099, 1, 5, 14, 30),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'koşul oluşmadı');
}

void main() {
  late _GatedRoutinesRepository routines;
  late _GatedTasksRepository tasks;
  late FakeSettingsRepository settings;
  late _PendingNotifications notifications;

  setUp(() {
    routines = _GatedRoutinesRepository();
    tasks = _GatedTasksRepository(tasks: [_task('a'), _task('b')]);
    settings = FakeSettingsRepository();
    notifications = _PendingNotifications();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        routinesRepositoryProvider.overrideWithValue(routines),
        tasksRepositoryProvider.overrideWithValue(tasks),
        settingsRepositoryProvider.overrideWithValue(settings),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    // HomeShell gibi: sağlayıcı hep dinlenir.
    container.listen(notificationSyncProvider, (_, __) {});
    return container;
  }

  group('üst üste binen eşitleme turları', () {
    test('okuması geciken eski tur, tamamlanan görevin hatırlatmasını '
        'geri getirmez', () async {
      final stalled = tasks.nextReadGate = Completer<void>();
      final container = makeContainer();
      // 1. tur görev okumasında bekliyor (yanıt, yazmadan önceki veriyi taşır).
      await _until(() => tasks.reads == 1);

      await tasks.complete('a');
      container.invalidate(notificationSyncProvider);
      await container.read(notificationSyncProvider.future);
      expect(notifications.pending, {'task:b'});

      stalled.complete();
      await _settle();

      expect(notifications.pending, {'task:b'});
    });

    test('okuması geciken eski tur, yeni eklenen görevin hatırlatmasını '
        'silmez', () async {
      final stalled = tasks.nextReadGate = Completer<void>();
      final container = makeContainer();
      await _until(() => tasks.reads == 1);

      tasks.tasks = [...tasks.tasks, _task('yeni')];
      container.invalidate(notificationSyncProvider);
      await container.read(notificationSyncProvider.future);
      expect(notifications.pending, {'task:a', 'task:b', 'task:yeni'});

      stalled.complete();
      await _settle();

      expect(notifications.pending, {'task:a', 'task:b', 'task:yeni'});
    });

    test('bildirimler kapatılınca süren eski tur yeniden planlamaz', () async {
      final stalled = tasks.nextReadGate = Completer<void>();
      final container = makeContainer();
      await _until(() => tasks.reads == 1);

      final current = await container.read(userSettingsProvider.future);
      await container
          .read(userSettingsProvider.notifier)
          .save(current.copyWith(notificationsEnabled: false));
      container.invalidate(notificationSyncProvider);
      await container.read(notificationSyncProvider.future);
      expect(notifications.pending, isEmpty);

      stalled.complete();
      await _settle();

      expect(notifications.pending, isEmpty);
    });

    test('okuması geciken eski tur, işaretlenen aylık işin hatırlatmasını '
        'geri getirmez', () async {
      final now = DateTime.now();
      // Gelecek ayın 15'i: bu ay kaçmış olsa bile en az bir hatırlatma planlanır.
      routines.routines = [
        const Routine(
          id: 'kira',
          title: 'Kira',
          frequency: RoutineFrequency.monthly,
          dayOfMonth: 15,
        ),
      ];
      tasks.tasks = [];
      final stalled = routines.nextReadGate = Completer<void>();
      final container = makeContainer();
      await _until(() => routines.completionReads == 1);

      // Bu ay ve gelecek ay işaretlenir.
      for (final month in [
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ]) {
        await routines.setCompleted(
          routineId: 'kira',
          periodKey: month,
          completed: true,
        );
      }
      container.invalidate(notificationSyncProvider);
      await container.read(notificationSyncProvider.future);
      expect(notifications.pending, isEmpty);

      stalled.complete();
      await _settle();

      expect(notifications.pending, isEmpty);
    });

    test('iki turun eklenti çağrıları birbirine karışmaz', () async {
      tasks.tasks = [for (var i = 0; i < 8; i++) _task('t$i')];
      final container = makeContainer();
      final current = await container.read(userSettingsProvider.future);

      // 1. tur planını uygularken (ilk hatırlatmadan sonra) bildirimler kapatılır.
      var triggered = false;
      Future<void>? secondRun;
      notifications.afterCall = () {
        if (triggered || notifications.pending.isEmpty) return;
        triggered = true;
        secondRun = () async {
          await container
              .read(userSettingsProvider.notifier)
              .save(current.copyWith(notificationsEnabled: false));
          container.invalidate(notificationSyncProvider);
          await container.read(notificationSyncProvider.future);
        }();
      };

      await _until(() => triggered);
      await secondRun;
      await _settle();

      expect(notifications.pending, isEmpty);
    });
  });
}
