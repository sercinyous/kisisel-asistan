import 'package:kisisel_asistan/features/reminders/data/reminders_repository.dart';
import 'package:kisisel_asistan/features/reminders/domain/reminder.dart';

/// Bellekte çalışan hatırlatıcı deposu (demo ve testler).
class MemoryRemindersRepository implements RemindersRepository {
  MemoryRemindersRepository({
    this.userId = 'demo-user',
    List<Reminder>? reminders,
    Map<String, Set<DateTime>>? done,
  })  : reminders = reminders ?? [],
        done = done ?? {};

  /// Oturumdaki kullanıcı (`null`: oturum yok).
  String? userId;
  final List<Reminder> reminders;
  final Map<String, Set<DateTime>> done;
  int _next = 1;

  /// Doluysa yazma çağrıları bu hatayı fırlatır.
  Object? error;

  void _check() {
    if (error != null) throw error!;
  }

  @override
  String? get currentUserId => userId;

  @override
  Future<List<Reminder>> fetchAll() async => List.unmodifiable(reminders);

  @override
  Future<Reminder> create(ReminderDraft draft) async {
    _check();
    final base = Reminder(
      id: 'rem-${_next++}',
      userId: userId ?? 'demo-user',
      title: '',
      time: draft.time,
      repeat: draft.repeat,
      createdAt: DateTime.now(),
    );
    final created = base.copyWithDraft(draft);
    reminders.add(created);
    return created;
  }

  @override
  Future<void> update(String id, ReminderDraft draft) async {
    _check();
    final i = reminders.indexWhere((r) => r.id == id);
    if (i >= 0) reminders[i] = reminders[i].copyWithDraft(draft);
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    _check();
    final i = reminders.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final r = reminders[i];
    reminders[i] = r.copyWithDraft(
      ReminderDraft(
        title: r.title,
        time: r.time,
        repeat: r.repeat,
        onDate: r.onDate,
        daysMask: r.daysMask,
        enabled: enabled,
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    _check();
    reminders.removeWhere((r) => r.id == id);
    done.remove(id);
  }

  @override
  Future<Map<String, Set<DateTime>>> fetchDone(DateTime from) async => {
        for (final e in done.entries)
          e.key: {
            for (final d in e.value)
              if (!d.isBefore(reminderDay(from))) d,
          },
      };

  @override
  Future<void> setDone(String reminderId, DateTime day, bool isDone) async {
    _check();
    final key = reminderDay(day);
    if (isDone) {
      done.putIfAbsent(reminderId, () => {}).add(key);
    } else {
      done[reminderId]?.remove(key);
    }
  }
}
