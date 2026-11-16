import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_targets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../domain/task_item.dart';
import 'operations_providers.dart';
import 'operations_screen.dart';
import 'operations_widgets.dart';
import 'task_form_sheet.dart';

class TasksView extends ConsumerWidget {
  const TasksView({super.key});

  Future<void> _openForm(BuildContext context, [TaskItem? task]) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await TaskFormSheet.show(context, task: task);
    if (!saved) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(task == null ? 'Görev eklendi.' : 'Görev güncellendi.'),
        ),
      );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Notifier yakalanır: await sonrası ref kullanılmaz.
    final notifier = ref.read(opsTasksProvider.notifier);

    Future<void> run(Future<void> Function() write) async {
      try {
        await write();
      } catch (_) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Görev güncellenemedi.')),
          );
      }
    }

    if (task.isDone) {
      await run(() => notifier.reopen(task));
      return;
    }
    await run(() async {
      await notifier.complete(task);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Görev tamamlandı.'),
            action: SnackBarAction(
              label: 'Geri al',
              onPressed: () => run(() => notifier.reopen(task)),
            ),
          ),
        );
    });
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TaskItem task,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(opsTasksProvider.notifier);
    final confirmed = await confirmDelete(
      context,
      title: 'Görev silinsin mi?',
      message: '"${task.title}" kalıcı olarak silinecek.',
    );
    if (!confirmed) return;
    try {
      await notifier.delete(task);
      messenger.showSnackBar(const SnackBar(content: Text('Görev silindi.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Görev silinemedi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(taskCategoryFilterProvider);
    final tasks = ref.watch(opsTasksProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(opsTasksProvider.notifier).reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: opsListPadding,
        children: [
          OpsSectionHeader(title: 'Görevler', onAdd: () => _openForm(context)),
          OpsFilterChips<String?>(
            options: [
              (null, 'Tümü'),
              for (final c in AppTargets.taskCategories) (c, c),
            ],
            selected: filter,
            onSelected: (value) =>
                ref.read(taskCategoryFilterProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          ...tasks.when(
            loading: () => const [OpsLoading()],
            error: (_, __) => [
              OpsMessage(
                icon: Icons.cloud_off_rounded,
                text: 'Görevler yüklenemedi.',
                onRetry: () => ref.invalidate(opsTasksProvider),
              ),
            ],
            data: (all) {
              final visible = [
                for (final t in all)
                  if (filter == null || t.category == filter) t,
              ];
              if (visible.isEmpty) {
                return [
                  OpsMessage(
                    icon: Icons.task_alt_rounded,
                    text: filter == null
                        ? 'Açık görev yok. "Ekle" ile yeni görev oluştur.'
                        : '$filter kategorisinde açık görev yok.',
                  ),
                ];
              }
              return [
                BentoCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (index, task) in visible.indexed) ...[
                        if (index > 0) const Divider(indent: 52),
                        _TaskRow(
                          task: task,
                          onToggle: () => _toggle(context, ref, task),
                          onEdit: () => _openForm(context, task),
                          onDelete: () => _delete(context, ref, task),
                        ),
                      ],
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = task.scheduledAt;
    final overdue = !task.isDone && when != null && when.isBefore(DateTime.now());
    final muted = theme.textTheme.labelMedium;

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('task-check-${task.id}'),
              value: task.isDone,
              onChanged: (_) => onToggle(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: task.isDone ? AppColors.textMuted : null,
                      decoration:
                          task.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: task.category,
                          style: TextStyle(
                            color: AppColors.forTaskCategory(task.category),
                          ),
                        ),
                        if (task.assignee != null)
                          TextSpan(text: ' · ${task.assignee}'),
                        if (when != null)
                          TextSpan(
                            text: ' · ${AppDates.relativeDayTime(when)}',
                            style: overdue
                                ? const TextStyle(color: AppColors.danger)
                                : null,
                          ),
                        if (task.priority == 'high')
                          const TextSpan(
                            text: ' · Yüksek',
                            style: TextStyle(color: AppColors.danger),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
            OpsItemMenu(onEdit: onEdit, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}
