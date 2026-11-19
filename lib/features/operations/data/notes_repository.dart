import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../domain/note_item.dart';

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return NotesRepository(ref.watch(supabaseClientProvider));
});

class NotesRepository {
  const NotesRepository(this._client);

  final SupabaseClient _client;

  /// Sabitlenenler üstte, sonra en son düzenlenen. [category] verilirse
  /// yalnızca o kategori.
  Future<List<NoteItem>> fetchAll({String? category}) async {
    var query = _client.from('notes').select();
    if (category != null) query = query.eq('category', category);
    final rows = await query
        .order('is_pinned', ascending: false)
        .order('updated_at', ascending: false);
    return [for (final row in rows) NoteItem.fromMap(row)];
  }

  Future<NoteItem> create({
    required String title,
    String content = '',
    String category = 'Kişisel',
    bool isPinned = false,
  }) async {
    final draft = NoteItem(
      id: '',
      title: title,
      content: content,
      category: category,
      isPinned: isPinned,
    );
    final row = await _client
        .from('notes')
        .insert(draft.toWriteMap())
        .select()
        .single();
    return NoteItem.fromMap(row);
  }

  Future<NoteItem> update(NoteItem note) async {
    final row = await _client
        .from('notes')
        .update(note.toWriteMap())
        .eq('id', note.id)
        .select()
        .single();
    return NoteItem.fromMap(row);
  }

  Future<void> delete(String id) async {
    await _client.from('notes').delete().eq('id', id);
  }
}
