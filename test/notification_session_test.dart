// Bağımsız inceleme #4: çıkışta bekleyen bildirimler veri sorgulanmadan
// silinir; çıkıştan önce başlamış (eski oturumun) tur, yeni oturumun
// bildirimlerini bozamaz ya da eski başlıkları geri planlayamaz.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fakes.dart';

/// Bekleyen bildirim kümesi; her eklenti çağrısı bir olay döngüsü turu sürer.
class _Pending extends FakeNotificationService {
  final Set<String> pending = {};
  int clears = 0;

  Future<void> _call() => Future<void>.delayed(Duration.zero);

  @override
  Future<void> scheduleReminder(ReminderSchedule reminder) async {
    await _call();
    pending.add(reminder.effectiveKey);
  }

  @override
  Future<void> resync({
    required List<RoutineSchedule> routines,
    required List<ReminderSchedule> reminders,
  }) async {
    await _call();
    pending.clear();
    if (routines.isEmpty && reminders.isEmpty) clears++;
    for (final r in reminders) {
      await scheduleReminder(r);
    }
  }
}

class _GatedTasks extends FakeTasksRepository {
  _GatedTasks({super.tasks});

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

TaskItem _task(String id) => TaskItem(
      id: id,
      title: 'Özel başlık $id',
      category: 'Kişisel',
      priority: 'medium',
      status: 'todo',
      remindAt: DateTime(2099, 1, 5, 14, 30),
    );

Session _session(String id) => Session(
      accessToken: 'token-$id',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue, reason: 'koşul oluşmadı');
}

void main() {
  late StreamController<Session?> auth;
  late _GatedTasks tasks;
  late _Pending notifications;
  late ProviderContainer container;

  setUp(() async {
    auth = StreamController<Session?>.broadcast();
    tasks = _GatedTasks(tasks: [_task('a1'), _task('a2')]);
    notifications = _Pending();
    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith((ref) => auth.stream),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(tasks),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        notificationServiceProvider.overrideWithValue(notifications),
        // Sağlık dürtüleri gerçek saate bağlıdır (ölçü günü ufka girince
        // planlanır); bu testler yalnızca görev/rutin kuyruğunu sınar.
        healthNudgeSyncProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });
    // AuthGate gibi: koruyucu ve oturum hep dinlenir.
    container.listen(notificationSessionGuardProvider, (_, __) {});
    container.listen(authSessionProvider, (_, __) {});
    auth.add(_session('user-a'));
    await _settle();
  });

  test('çıkışta bekleyenler veri okunmadan silinir', () async {
    container.listen(notificationSyncProvider, (_, __) {});
    await container.read(notificationSyncProvider.future);
    expect(notifications.pending, {'task:a1', 'task:a2'});
    final readsBefore = tasks.reads;

    auth.add(null);
    await _settle();

    expect(notifications.pending, isEmpty);
    expect(notifications.clears, 1);
    expect(tasks.reads, readsBefore, reason: 'çıkışta veri sorgulanmaz');
  });

  test('çıkıştan önce başlamış eski tur, çıkıştan ve yeni oturumdan sonra '
      'bitse de planlama yapamaz', () async {
    final gate = Completer<void>();
    tasks.nextReadGate = gate;
    container.listen(notificationSyncProvider, (_, __) {});
    await _until(() => tasks.reads == 1);

    // A çıkış yapar, B girer; B'nin turu biter.
    auth.add(null);
    await _settle();
    expect(notifications.pending, isEmpty);

    tasks.tasks = [_task('b1')];
    auth.add(_session('user-b'));
    await _settle();
    container.invalidate(notificationSyncProvider);
    await container.read(notificationSyncProvider.future);
    expect(notifications.pending, {'task:b1'});

    // A'nın ağda takılan okuması şimdi döner: eski başlıklar geri gelmez.
    gate.complete();
    await _settle();
    expect(notifications.pending, {'task:b1'});
  });

  test('ayarlardaki açık çıkış yolu da aynı kuyruktan siler ve süren turu '
      'geçersiz kılar', () async {
    final gate = Completer<void>();
    tasks.nextReadGate = gate;
    container.listen(notificationSyncProvider, (_, __) {});
    await _until(() => tasks.reads == 1);

    await container
        .read(notificationSyncQueueProvider)
        .endSession(container.read(notificationServiceProvider));
    expect(notifications.pending, isEmpty);

    gate.complete();
    await _settle();
    expect(notifications.pending, isEmpty,
        reason: 'çıkış öncesi başlamış tur yeniden planlayamaz');
  });

  test('çıkıştan sonra sağlık dürtüsü planlanmaz', () async {
    final c = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith((ref) => Stream.value(null)),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(c.dispose);
    c.listen(authSessionProvider, (_, __) {});
    await _settle();
    await c.read(healthNudgeSyncProvider.future);
    expect(notifications.pending.where((k) => k.contains('health')), isEmpty);
  });
}
