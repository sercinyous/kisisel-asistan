import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_targets.dart';
import '../data/notes_repository.dart';
import '../domain/note_item.dart';
import 'operations_providers.dart';
import 'operations_widgets.dart';

/// Not ekleme / düzenleme formu.
class NoteFormSheet extends ConsumerStatefulWidget {
  const NoteFormSheet({super.key, this.note});

  final NoteItem? note;

  static Future<bool> show(BuildContext context, {NoteItem? note}) =>
      showOpsSheet(context, NoteFormSheet(note: note));

  @override
  ConsumerState<NoteFormSheet> createState() => _NoteFormSheetState();
}

class _NoteFormSheetState extends ConsumerState<NoteFormSheet> {
  // schema.sql: notes.title 1..200.
  static const int _titleMax = 200;
  static const int _contentMax = 10000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _content;
  late String _category;
  late bool _pinned;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _title = TextEditingController(text: note?.title ?? '');
    _content = TextEditingController(text: note?.content ?? '');
    _category = AppTargets.noteCategories.contains(note?.category)
        ? note!.category
        : 'Kişisel';
    _pinned = note?.isPinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = container.read(notesRepositoryProvider);
      final existing = widget.note;
      if (existing == null) {
        await repository.create(
          title: _title.text.trim(),
          content: _content.text.trim(),
          category: _category,
          isPinned: _pinned,
        );
      } else {
        await repository.update(
          existing.copyWith(
            title: _title.text.trim(),
            content: _content.text.trim(),
            category: _category,
            isPinned: _pinned,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    container.invalidate(opsNotesProvider);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return OpsSheetFrame(
      title: widget.note == null ? 'Yeni not' : 'Notu düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        TextFormField(
          controller: _title,
          maxLength: _titleMax,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Başlık'),
          validator: (value) => validateTitle(value, _titleMax),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _content,
          maxLength: _contentMax,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'İçerik',
            alignLabelWithHint: true,
          ),
        ),
        const OpsFieldLabel('Kategori'),
        OpsChoiceWrap<String>(
          options: [for (final c in AppTargets.noteCategories) (c, c)],
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sabitle'),
          subtitle: const Text('Sabitlenen notlar listenin başında durur.'),
          value: _pinned,
          onChanged: (value) => setState(() => _pinned = value),
        ),
      ],
    );
  }
}
