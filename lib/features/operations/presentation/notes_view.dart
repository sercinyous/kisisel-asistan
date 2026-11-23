import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/item_actions.dart';
import '../data/notes_repository.dart';
import '../domain/note_item.dart';
import 'note_form_sheet.dart';
import 'operations_providers.dart';
import 'operations_screen.dart';
import 'operations_widgets.dart';

const String _deleteTitle = 'Not silinsin mi?';

String _deleteMessage(NoteItem note) =>
    '"${note.title}" kalıcı olarak silinecek.';

/// Not formunu açar (yeni ya da düzenleme) ve sonucu bildirir.
Future<void> openNoteForm(BuildContext context, [NoteItem? note]) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await NoteFormSheet.show(context, note: note);
  if (!saved) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(note == null ? 'Not eklendi.' : 'Not güncellendi.'),
      ),
    );
}

class NotesView extends ConsumerWidget {
  const NotesView({super.key});

  Future<void> _togglePin(BuildContext context, NoteItem note) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container
          .read(notesRepositoryProvider)
          .update(note.copyWith(isPinned: !note.isPinned));
      container.invalidate(opsNotesProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Not güncellenemedi.')),
      );
    }
  }

  /// Notu siler; başarılıysa `true`. Uzun basış ve kaydırma onayı kendisi
  /// sorar.
  Future<bool> _delete(BuildContext context, NoteItem note) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(notesRepositoryProvider).delete(note.id);
      container.invalidate(opsNotesProvider);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Not silinemedi.')));
      return false;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Not silindi.')));
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(noteCategoryFilterProvider);
    final notes = ref.watch(opsNotesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(opsNotesProvider);
        try {
          await ref.read(opsNotesProvider.future);
        } catch (_) {
          // Hata durumu ekranda zaten gösterilir.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: opsListPadding,
        children: [
          ...notes.when(
            loading: () => const [OpsLoading()],
            error: (_, __) => [
              OpsMessage(
                icon: Icons.cloud_off_outlined,
                text: 'Notlar yüklenemedi.',
                onRetry: () => ref.invalidate(opsNotesProvider),
              ),
            ],
            data: (all) {
              final visible = [
                for (final n in all)
                  if (filter == null || n.category == filter) n,
              ];
              if (visible.isEmpty) {
                return [
                  OpsMessage(
                    icon: Icons.sticky_note_2_outlined,
                    text: filter == null
                        ? 'Henüz not yok. + ile ilk notunu yaz.'
                        : '$filter kategorisinde not yok.',
                  ),
                ];
              }
              return [
                for (final (index, note) in visible.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.grid),
                  ItemRowActions(
                    key: ValueKey('ops-note-${note.id}'),
                    itemKey: ValueKey('swipe-note-${note.id}'),
                    title: note.title,
                    confirmTitle: _deleteTitle,
                    confirmMessage: _deleteMessage(note),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    onEdit: () => openNoteForm(context, note),
                    onDelete: () => _delete(context, note),
                    child: _NoteCard(
                      note: note,
                      onEdit: () => openNoteForm(context, note),
                      onTogglePin: () => _togglePin(context, note),
                    ),
                  ),
                ],
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onTogglePin,
  });

  final NoteItem note;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(AppSpacing.cardPadding, 8, 0, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                key: ValueKey('note-pin-${note.id}'),
                tooltip: note.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                onPressed: onTogglePin,
                icon: Icon(
                  note.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                  color: note.isPinned
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.content.isNotEmpty) ...[
                  Text(
                    note.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  note.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
