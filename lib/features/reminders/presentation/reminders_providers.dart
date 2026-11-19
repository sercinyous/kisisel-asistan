import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_sync.dart';
import '../../../core/services/supabase_providers.dart';
import '../data/reminder_action_inbox.dart';
import '../data/reminders_repository.dart';
import '../domain/reminder.dart';

/// Seri hesabı için geriye bakılan gün sayısı.
const int reminderHistoryDays = 400;

final remindersProvider = FutureProvider<List<Reminder>>(
  (ref) => ref.watch(remindersRepositoryProvider).fetchAll(),
);

/// Hatırlatıcı başına "Yaptım" günleri (son [reminderHistoryDays] gün).
final reminderDoneProvider = FutureProvider<Map<String, Set<DateTime>>>((ref) {
  final today = reminderDay(DateTime.now());
  return ref.watch(remindersRepositoryProvider).fetchDone(
        DateTime(today.year, today.month, today.day - reminderHistoryDays),
      );
});

final remindersControllerProvider =
    Provider<RemindersController>(RemindersController.new);

class RemindersController {
  RemindersController(this._ref);

  final Ref _ref;

  RemindersRepository get _repo => _ref.read(remindersRepositoryProvider);

  void _refresh({bool reschedule = true}) {
    _ref
      ..invalidate(remindersProvider)
      ..invalidate(reminderDoneProvider);
    if (reschedule) _ref.invalidate(notificationSyncProvider);
  }

  Future<void> create(ReminderDraft draft) async {
    await _repo.create(draft);
    _refresh();
  }

  Future<void> update(String id, ReminderDraft draft) async {
    await _repo.update(id, draft);
    _refresh();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
    _refresh();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    _refresh();
  }

  Future<void> setDone(String id, DateTime day, bool done) async {
    await _repo.setDone(id, reminderDay(day), done);
    _refresh(reschedule: false);
  }
}

/// Bildirimdeki "Yaptım" eylemlerini işler: açılışta, ön plana dönüşte ve
/// ön plandaki yeni eylemde kutuyu boşaltır. Eylemin sahibi oturumdaki
/// kullanıcı değilse (çıkış ya da hesap değişimi) kayıt YAZILMAZ ve atılır.
final reminderActionProcessorProvider =
    Provider<ReminderActionProcessor>((ref) {
  final userId =
      ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  final processor = ReminderActionProcessor(
    currentUserId: () => userId,
    write: (action) => ref
        .read(remindersRepositoryProvider)
        .setDone(action.reminderId, action.day, true),
    drain: ReminderActionInbox.drain,
    onWritten: () => ref.invalidate(reminderDoneProvider),
  );
  if (userId == null) return processor;

  unawaited(processor.process());
  final sub = ReminderActionInbox.live.listen((_) => processor.process());
  final lifecycle = AppLifecycleListener(onResume: processor.process);
  ref.onDispose(() {
    unawaited(sub.cancel());
    lifecycle.dispose();
  });
  return processor;
});

class ReminderActionProcessor {
  ReminderActionProcessor({
    required this.currentUserId,
    required this.write,
    required this.drain,
    required this.onWritten,
  });

  final String? Function() currentUserId;
  final Future<void> Function(ReminderDoneAction action) write;
  final Future<List<ReminderDoneAction>> Function() drain;
  final void Function() onWritten;

  Future<void>? _running;

  /// Kutudaki eylemleri işler; eşzamanlı çağrılar aynı turu bekler.
  Future<void> process() => _running ??= _process().whenComplete(() {
        _running = null;
      });

  Future<int> _processCount() async {
    final user = currentUserId();
    if (user == null) return 0;
    final actions = await drain();
    var written = 0;
    for (final action in actions) {
      if (action.ownerId != user) continue;
      try {
        await write(action);
        written++;
      } catch (_) {
        // Bağlantı yoksa eylem kaybolur; kullanıcı uygulamadan işaretleyebilir.
      }
    }
    return written;
  }

  Future<void> _process() async {
    try {
      final written = await _processCount();
      if (written > 0) onWritten();
    } catch (_) {
      // Kutu okunamazsa sessizce geçilir.
    }
  }
}
