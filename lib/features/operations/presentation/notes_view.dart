import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_targets.dart';
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

class NotesView extends ConsumerWidget {
  const NotesView({super.key});

  Future<void> _openForm(BuildContext context, [NoteItem? note]) async {
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

  /// Notu siler; başarılıysa `true`. [confirm] doğruysa önce onay sorulur
  /// (üç nokta menüsü); uzun basış ve kaydırma onayı kendisi sorar.
  Future<bool> _delete(
    BuildContext context,
    NoteItem note, {
    bool confirm = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    if (confirm) {
      final confirmed = await confirmDelete(
        context,
        title: _deleteTitle,
        message: _deleteMessage(note),
      );
      if (!confirmed) return false;
    }
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
          OpsSectionHeader(title: 'Notlar', onAdd: () => _openForm(context)),
          OpsFilterChips<String?>(
            options: [
              (null, 'Tümü'),
              for (final c in AppTargets.noteCategories) (c, c),
            ],
            selected: filter,
            onSelected: (value) =>
                ref.read(noteCategoryFilterProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          ...notes.when(
            loading: () => const [OpsLoading()],
            error: (_, __) => [
              OpsMessage(
                icon: Icons.cloud_off_rounded,
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
                        ? 'Henüz not yok. "Ekle" ile ilk notunu yaz.'
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
                    onEdit: () => _openForm(context, note),
                    onDelete: () => _delete(context, note),
                    child: _NoteCard(
                      note: note,
                      onEdit: () => _openForm(context, note),
                      onTogglePin: () => _togglePin(context, note),
                      onDelete: () => _delete(context, note, confirm: true),
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
    required this.onDelete,
  });

  final NoteItem note;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      onTap: onEdit,
      tint: note.isPinned ? AppColors.accent : null,
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
                  style: theme.textTheme.titleMedium,
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
                  size: 20,
                  color:
                      note.isPinned ? AppColors.accent : AppColors.textMuted,
                ),
              ),
              OpsItemMenu(onEdit: onEdit, onDelete: onDelete),
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
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.ops),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
