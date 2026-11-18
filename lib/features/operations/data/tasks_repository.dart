import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/task_item.dart';

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return TasksRepository(ref.watch(supabaseClientProvider));
});

class TasksRepository {
  const TasksRepository(this._client);

  final SupabaseClient _client;

  /// Tamamlanmamış tüm görevler; termini olanlar önce ve yakından uzağa.
  Future<List<TaskItem>> fetchOpen() async {
    final rows = await _client
        .from('tasks')
        .select()
        .neq('status', 'done')
        .order('due_at', ascending: true, nullsFirst: false)
        .order('created_at', ascending: true);
    return [for (final row in rows) TaskItem.fromMap(row)];
  }

  /// Takvim anı ([TaskItem.scheduledAt]: termin, yoksa hatırlatma)
  /// `[from, to)` aralığına düşen görevler; tamamlananlar dahil, zamana göre.
  Future<List<TaskItem>> fetchInRange(DateTime from, DateTime to) async {
    final start = from.toUtc().toIso8601String();
    final end = to.toUtc().toIso8601String();
    // İki ayrı sorgu: PostgREST'in or() sözdiziminde zaman damgası kaçışına
    // bağımlı kalmamak için.
    final results = await Future.wait([
      _client.from('tasks').select().gte('due_at', start).lt('due_at', end),
      _client
          .from('tasks')
          .select()
          .isFilter('due_at', null)
          .gte('remind_at', start)
          .lt('remind_at', end),
    ]);
    final tasks = [
      for (final rows in results)
        for (final row in rows) TaskItem.fromMap(row),
    ]..sort((a, b) => a.scheduledAt!.compareTo(b.scheduledAt!));
    return tasks;
  }

  /// [from] anından bu yana tamamlanan görevler (terminsiz olanlar dahil),
  /// tamamlanma zamanına göre eskiden yeniye.
  Future<List<TaskItem>> fetchCompletedSince(DateTime from) async {
    final rows = await _client
        .from('tasks')
        .select()
        .eq('status', 'done')
        .gte('completed_at', from.toUtc().toIso8601String())
        .order('completed_at', ascending: true);
    return [for (final row in rows) TaskItem.fromMap(row)];
  }

  /// Tamamlanmamış ve zamanı gelecekte olan görev/hatırlatmalar.
  Future<List<TaskItem>> fetchUpcoming({DateTime? from, int limit = 6}) async {
    final now = from ?? DateTime.now();
    final iso = now.toUtc().toIso8601String();
    // İki sıralı sorgu: tek bir OR sorgusunda limit, sıralamadan önce kesilir
    // ve en yakın hatırlatmalar listenin dışında kalabilir.
    final results = await Future.wait([
      _client
          .from('tasks')
          .select()
          .neq('status', 'done')
          .gte('remind_at', iso)
          .order('remind_at', ascending: true)
          .limit(50),
      _client
          .from('tasks')
          .select()
          .neq('status', 'done')
          .gte('due_at', iso)
          .order('due_at', ascending: true)
          .limit(50),
    ]);
    final byId = <String, TaskItem>{
      for (final rows in results)
        for (final row in rows) row['id'] as String: TaskItem.fromMap(row),
    };
    final tasks = byId.values.toList()
      ..sort((a, b) => a.nextTime(now)!.compareTo(b.nextTime(now)!));
    return tasks.take(limit).toList();
  }

  Future<TaskItem> create({
    required String title,
    String? description,
    String category = 'Kişisel',
    String priority = 'medium',
    String? assignee,
    DateTime? dueAt,
    DateTime? remindAt,
    bool notify = true,
  }) async {
    final draft = TaskItem(
      id: '',
      title: title,
      description: description,
      category: category,
      priority: priority,
      status: 'todo',
      assignee: assignee,
      dueAt: dueAt,
      remindAt: remindAt,
      notify: notify,
    );
    final row =
        await _client.from('tasks').insert(draft.toWriteMap()).select().single();
    return TaskItem.fromMap(row);
  }

  /// Düzenlenebilir alanları yazar; durum değişmez.
  Future<TaskItem> update(TaskItem task) async {
    final row = await _client
        .from('tasks')
        .update(task.toWriteMap())
        .eq('id', task.id)
        .select()
        .single();
    return TaskItem.fromMap(row);
  }

  Future<void> complete(String id) async {
    await _client.from('tasks').update({
      'status': 'done',
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> reopen(String id) async {
    await _client
        .from('tasks')
        .update({'status': 'todo', 'completed_at': null}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('tasks').delete().eq('id', id);
  }

  /// Yeniden adlandırılan kategoriyi kullanıcının görevlerine taşır (RLS
  /// yalnızca kendi satırlarını günceller).
  Future<void> renameCategory(String from, String to) async {
    if (from == to) return;
    await _client.from('tasks').update({'category': to}).eq('category', from);
  }
}
