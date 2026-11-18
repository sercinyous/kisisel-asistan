// Hatırlatıcılar oturuma bağlı eşitleme kuyruğundan planlanır: çıkışta
// silinir, hesap değişince eski hesabın hatırlatıcısı ve "Yaptım" eylemi
// yeni hesaba sızmaz.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/demo/demo_reminders.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/reminders/data/reminder_action_inbox.dart';
import 'package:kisisel_asistan/features/reminders/data/reminders_repository.dart';
import 'package:kisisel_asistan/features/reminders/domain/reminder.dart';
import 'package:kisisel_asistan/features/reminders/presentation/reminders_providers.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fakes.dart';

class _Pending extends FakeNotificationService {
  final Set<String> pending = {};

  @override
  Future<void> resync({
    required List<RoutineSchedule> routines,
    required List<ReminderSchedule> reminders,
  }) async {
    await Future<void>.delayed(Duration.zero);
    pending.clear();
    for (final r in reminders) {
      pending.add(r.effectiveKey);
    }
  }

  @override
  Future<void> scheduleHabitReminders(
    List<HabitReminderSchedule> reminders,
  ) async {
    await Future<void>.delayed(Duration.zero);
    for (final r in reminders) {
      pending.add(r.payload);
    }
  }
}

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

Reminder _reminder(String id, String owner) => Reminder(
      id: id,
      userId: owner,
      title: 'Su iç ($owner)',
      time: const TimeOfDayValue(22, 0),
      repeat: ReminderRepeat.daily,
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late StreamController<Session?> auth;
  late _Pending notifications;
  late MemoryRemindersRepository reminders;
  late ProviderContainer container;

  setUp(() async {
    auth = StreamController<Session?>.broadcast();
    notifications = _Pending();
    reminders = MemoryRemindersRepository(
      userId: 'user-a',
      reminders: [_reminder('ra', 'user-a')],
    );
    container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith((ref) => auth.stream),
        routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
        tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        notificationServiceProvider.overrideWithValue(notifications),
        remindersRepositoryProvider.overrideWithValue(reminders),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });
    container.listen(notificationSessionGuardProvider, (_, __) {});
    container.listen(authSessionProvider, (_, __) {});
    auth.add(_session('user-a'));
    await _settle();
  });

  test('hatırlatıcı planlanır; çıkışta silinir', () async {
    container.listen(notificationSyncProvider, (_, __) {});
    await container.read(notificationSyncProvider.future);
    expect(notifications.pending, {'reminder:ra:user-a'});

    auth.add(null);
    await _settle();
    expect(notifications.pending, isEmpty);
  });

  test('hesap değişince yalnızca yeni hesabın hatırlatıcısı planlanır', () async {
    container.listen(notificationSyncProvider, (_, __) {});
    await container.read(notificationSyncProvider.future);

    auth.add(null);
    await _settle();
    reminders
      ..userId = 'user-b'
      ..reminders
          .setAll(0, [_reminder('rb', 'user-b')]);
    auth.add(_session('user-b'));
    await _settle();
    container.invalidate(notificationSyncProvider);
    await container.read(notificationSyncProvider.future);
    expect(notifications.pending, {'reminder:rb:user-b'});
  });

  test('"Yaptım" eylemi yalnızca sahibi oturumdayken yazılır', () async {
    final written = <String>[];
    final inbox = [
      ReminderDoneAction(
        reminderId: 'ra',
        ownerId: 'user-a',
        day: DateTime(2026, 11, 18),
      ),
      ReminderDoneAction(
        reminderId: 'rb',
        ownerId: 'user-b',
        day: DateTime(2026, 11, 18),
      ),
    ];
    var refreshed = 0;
    final processor = ReminderActionProcessor(
      currentUserId: () => 'user-b',
      write: (a) async => written.add(a.reminderId),
      drain: () async {
        final copy = [...inbox];
        inbox.clear();
        return copy;
      },
      onWritten: () => refreshed++,
    );
    await processor.process();
    expect(written, ['rb']);
    expect(refreshed, 1);
    expect(inbox, isEmpty, reason: 'yabancı eylem kutuda kalmaz');

    final loggedOut = ReminderActionProcessor(
      currentUserId: () => null,
      write: (a) async => written.add(a.reminderId),
      drain: () async => fail('oturum yokken kutu boşaltılmaz'),
      onWritten: () {},
    );
    await loggedOut.process();
  });

  test('ekrandaki Yaptım: denetleyici bugünü işaretler ve geri alır', () async {
    final controller = container.read(remindersControllerProvider);
    final today = DateTime.now();
    await controller.setDone('ra', today, true);
    expect(
      (await container.read(reminderDoneProvider.future))['ra'],
      {reminderDay(today)},
    );
    await controller.setDone('ra', today, false);
    expect((await container.read(reminderDoneProvider.future))['ra'], isEmpty);
  });
}
