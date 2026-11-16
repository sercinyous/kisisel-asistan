import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/parsed_entry.dart';

final quickAddRepositoryProvider = Provider<QuickAddRepository>(
  (ref) => QuickAddRepository(ref.watch(supabaseClientProvider)),
);

/// Kaydedilen görevlerden bildirim planlamak için gereken alanlar.
class SavedTask {
  const SavedTask({
    required this.id,
    required this.title,
    this.dueAt,
    this.remindAt,
  });

  final String id;
  final String title;
  final DateTime? dueAt;

  /// Kullanıcının açıkça istediği hatırlatma anı; yoksa bildirim terminden
  /// ayarlardaki süre kadar önce planlanır.
  final DateTime? remindAt;
}

class QuickAddResult {
  const QuickAddResult({
    required this.tasks,
    required this.nutritionCount,
    required this.workoutCount,
    required this.weightCount,
    required this.noteCount,
    this.routineCount = 0,
  });

  final List<SavedTask> tasks;
  final int nutritionCount;
  final int workoutCount;
  final int weightCount;
  final int noteCount;
  final int routineCount;

  int get totalCount =>
      tasks.length +
      nutritionCount +
      workoutCount +
      weightCount +
      noteCount +
      routineCount;
}

class QuickAddRepository {
  const QuickAddRepository(this._client);

  final SupabaseClient _client;

  /// Tüm kalemleri `quick_add_entries` RPC'si ile tek transaction'da yazar:
  /// tablolardan biri hata verirse hiçbir kayıt oluşmaz.
  Future<QuickAddResult> saveAll(ParsedEntry entry) async {
    final Object? response = await _client.rpc<Object?>(
      'quick_add_entries',
      params: {'payload': entry.toJson()},
    );
    final data = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};

    final tasks = <SavedTask>[];
    final rawTasks = data['tasks'];
    if (rawTasks is List) {
      for (final row in rawTasks) {
        if (row is! Map) continue;
        final due = row['due_at'];
        final remind = row['remind_at'];
        tasks.add(
          SavedTask(
            id: row['id'] as String,
            title: row['title'] as String,
            dueAt: due is String ? DateTime.tryParse(due) : null,
            remindAt: remind is String ? DateTime.tryParse(remind) : null,
          ),
        );
      }
    }

    int count(String key) => (data[key] as num?)?.toInt() ?? 0;

    return QuickAddResult(
      tasks: tasks,
      nutritionCount: count('nutrition_count'),
      workoutCount: count('workout_count'),
      weightCount: count('weight_count'),
      noteCount: count('note_count'),
      routineCount: count('routine_count'),
    );
  }
}
