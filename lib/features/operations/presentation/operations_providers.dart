import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_sync.dart';
import '../../health/presentation/health_providers.dart'
    show weekWorkoutPlanProvider;
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../routines/data/routines_repository.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import '../data/notes_repository.dart';
import '../data/tasks_repository.dart';
import '../domain/note_item.dart';
import '../domain/task_item.dart';

enum OpsSegment { tasks, routines, notes }

final opsSegmentProvider =
    StateProvider<OpsSegment>((ref) => OpsSegment.tasks);

/// Filtreler: `null` = Tümü.
final taskCategoryFilterProvider = StateProvider<String?>((ref) => null);
final routineScopeFilterProvider = StateProvider<String?>((ref) => null);
final noteCategoryFilterProvider = StateProvider<String?>((ref) => null);

/// Görevlerdeki "Sonra" grubu açık mı. `null`: kullanıcı seçmedi; grup
/// kapalı başlar, yalnızca Bugün ve Bu hafta boşsa açık gösterilir.
final opsLaterExpandedProvider = StateProvider<bool?>((ref) => null);

/// `ref.invalidate` ya da `container.invalidate`.
typedef OpsInvalidate = void Function(ProviderOrFamily provider);

/// Görev değişince Kokpit (Gün/Ay) ve bildirim planı bayatlar.
void notifyTaskChange(OpsInvalidate invalidate) {
  invalidate(upcomingRemindersProvider);
  invalidate(monthOverviewProvider);
  invalidate(notificationSyncProvider);
}

/// Rutin değişince Gün/Ay ekranları, Sağlık sekmesinin haftalık antrenman
/// planı (spor rutinleri) ve bildirim planı bayatlar.
void notifyRoutineChange(OpsInvalidate invalidate) {
  invalidate(opsRoutinesProvider);
  invalidate(activeRoutinesProvider);
  invalidate(todayOccurrencesProvider);
  invalidate(weekWorkoutPlanProvider);
  invalidate(monthOverviewProvider);
  invalidate(notificationSyncProvider);
}

/// Başka bir ekran (ör. AI girişi) [source]'u tazeleyip yeni veri gelince
/// `true`. İlk yükleme sayılmaz; yoksa açılışta çift okuma olur.
bool _refreshedElsewhere<T>(AsyncValue<T>? previous, AsyncValue<T> next) =>
    previous != null &&
    previous.hasValue &&
    next.hasValue &&
    !next.isLoading &&
    !identical(previous.valueOrNull, next.valueOrNull);

int _byDate(TaskItem a, TaskItem b) {
  final ta = a.scheduledAt, tb = b.scheduledAt;
  if (ta == null && tb == null) return 0;
  // Tarihsizler sonda.
  if (ta == null) return 1;
  if (tb == null) return -1;
  return ta.compareTo(tb);
}

/// Açık görevler (tarihe göre) + bu oturumda tamamlananlar. Tamamlanan görev
/// yanlışlıkla işaretlendiyse geri alınabilsin diye listede kalır.
final opsTasksProvider =
    AsyncNotifierProvider<OpsTasksNotifier, List<TaskItem>>(
  OpsTasksNotifier.new,
);

class OpsTasksNotifier extends AsyncNotifier<List<TaskItem>> {
  // Notifier örneği invalidate sonrası da yaşar; yenileme bunları silmez.
  final Map<String, TaskItem> _doneInSession = {};
  final Set<String> _busy = {};
  List<TaskItem> _open = const [];

  List<TaskItem> _compose() => [
        ...[..._open]..sort(_byDate),
        ..._doneInSession.values,
      ];

  @override
  Future<List<TaskItem>> build() async {
    // AI girişi ya da Kokpit görev eklediğinde bu sağlayıcıyı tazeler.
    ref.listen(upcomingRemindersProvider, (previous, next) {
      if (_refreshedElsewhere(previous, next)) ref.invalidateSelf();
    });
    final open = await ref.watch(tasksRepositoryProvider).fetchOpen();
    _open = open;
    _doneInSession.removeWhere((id, _) => open.any((t) => t.id == id));
    return _compose();
  }

  /// Aşağı çekerek yenileme: tamamlananlar da listeden düşer.
  Future<void> reload() async {
    _doneInSession.clear();
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Hata durumu ekranda zaten gösterilir.
    }
  }

  /// Formdan kaydedilen görev bu oturumda tamamlanmışsa listede tutulan kopya
  /// da güncellenir; `build` yalnızca açık görevleri okuduğu için tazeleme
  /// onu yenilemez. Ardından sağlayıcı tazelenmelidir.
  void applySaved(TaskItem saved) {
    if (saved.isDone && _doneInSession.containsKey(saved.id)) {
      _doneInSession[saved.id] = saved;
    }
  }

  Future<void> complete(TaskItem task) => _guard(task.id, () async {
        await ref.read(tasksRepositoryProvider).complete(task.id);
        _open = _open.where((t) => t.id != task.id).toList();
        _doneInSession[task.id] =
            task.copyWith(status: 'done', completedAt: DateTime.now());
      });

  Future<void> reopen(TaskItem task) => _guard(task.id, () async {
        await ref.read(tasksRepositoryProvider).reopen(task.id);
        _doneInSession.remove(task.id);
        _open = [
          ..._open.where((t) => t.id != task.id),
          task.copyWith(status: 'todo', clearCompletedAt: true),
        ];
      });

  Future<void> delete(TaskItem task) => _guard(task.id, () async {
        await ref.read(tasksRepositoryProvider).delete(task.id);
        _doneInSession.remove(task.id);
        _open = _open.where((t) => t.id != task.id).toList();
      });

  /// Aynı görev için yazma sürerken ikinci dokunuş yok sayılır.
  /// Hata çağırana iletilir.
  Future<void> _guard(String id, Future<void> Function() write) async {
    if (!_busy.add(id)) return;
    try {
      await write();
    } finally {
      _busy.remove(id);
    }
    if (state.hasValue) state = AsyncData(_compose());
    notifyTaskChange(ref.invalidate);
  }
}

/// Pasifler dahil tüm rutinler (yönetim listesi).
final opsRoutinesProvider = FutureProvider<List<Routine>>((ref) {
  // AI girişi rutin eklediğinde aktif listeyi tazeler; bu liste de izler.
  ref.listen(activeRoutinesProvider, (previous, next) {
    if (_refreshedElsewhere(previous, next)) ref.invalidateSelf();
  });
  return ref.watch(routinesRepositoryProvider).fetchAll();
});

/// Tüm notlar; kategori filtresi ekranda uygulanır.
final opsNotesProvider = FutureProvider<List<NoteItem>>(
  (ref) => ref.watch(notesRepositoryProvider).fetchAll(),
);
