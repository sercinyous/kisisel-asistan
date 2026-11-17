import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/item_actions.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/task_item.dart';
import 'operations_providers.dart';
import 'operations_screen.dart';
import 'operations_widgets.dart';
import 'task_category_style.dart';
import 'task_form_sheet.dart';

/// Görev formunu açar (yeni ya da düzenleme) ve sonucu bildirir. Operasyon
/// listesi ile Kokpit satırlarının ortak yoludur; kayıt sonrası sağlayıcıları
/// ve bildirim planını form kendisi tazeler.
Future<void> openTaskForm(BuildContext context, [TaskItem? task]) async {
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

const String taskDeleteTitle = 'Görev silinsin mi?';

String taskDeleteMessage(TaskItem task) =>
    '"${task.title}" kalıcı olarak silinecek.';

/// Görevi siler; başarılıysa `true`. Bildirim planı ve Kokpit/Ay listeleri
/// `OpsTasksNotifier.delete` içinde tazelenir. [confirm] doğruysa önce onay
/// sorulur (üç nokta menüsü); uzun basış ve kaydırma onayı kendisi sorar.
Future<bool> deleteTask(
  BuildContext context,
  TaskItem task, {
  bool confirm = false,
}) async {
  // Onay ve yazma sürerken ekran kapanabilir; await sonrası context kullanılmaz.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  if (confirm) {
    final confirmed = await confirmDelete(
      context,
      title: taskDeleteTitle,
      message: taskDeleteMessage(task),
    );
    if (!confirmed) return false;
  }
  try {
    await container.read(opsTasksProvider.notifier).delete(task);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Görev silinemedi.')),
    );
    return false;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Görev silindi.')));
  return true;
}

/// Görev satırına uzun basış menüsü (Düzenle / Sil) ve sola kaydırarak silme
/// ekler; Operasyon listesi ve Kokpit ortak kullanır.
class TaskRowActions extends StatelessWidget {
  const TaskRowActions({
    super.key,
    required this.task,
    required this.child,
    this.borderRadius,
  });

  final TaskItem task;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ItemRowActions(
      itemKey: ValueKey('swipe-task-${task.id}'),
      title: task.title,
      confirmTitle: taskDeleteTitle,
      confirmMessage: taskDeleteMessage(task),
      borderRadius: borderRadius,
      onEdit: () => openTaskForm(context, task),
      onDelete: () => deleteTask(context, task),
      child: child,
    );
  }
}

class TasksView extends ConsumerWidget {
  const TasksView({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTaskCategoryNamesProvider);
    final categories = ref.watch(taskCategoriesProvider);
    final selectedFilter = ref.watch(taskCategoryFilterProvider);
    // Kapatılan kategori filtrede kalmışsa Tümü'ye düşülür.
    final filter =
        active.contains(selectedFilter) ? selectedFilter : null;
    final tasks = ref.watch(opsTasksProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(opsTasksProvider.notifier).reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: opsListPadding,
        children: [
          OpsSectionHeader(title: 'Görevler', onAdd: () => openTaskForm(context)),
          OpsFilterChips<String?>(
            options: [
              (null, 'Tümü'),
              for (final c in active) (c, c),
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
                        TaskRowActions(
                          // Durum konuma değil kayda bağlı kalsın: liste
                          // kayınca satır yanlış kaydın eylemini taşımaz.
                          key: ValueKey('ops-task-${task.id}'),
                          task: task,
                          child: _TaskRow(
                          categoryColor: taskCategoryColor(categories, task.category),
                            task: task,
                            onToggle: () => _toggle(context, ref, task),
                            onEdit: () => openTaskForm(context, task),
                            onDelete: () =>
                                deleteTask(context, task, confirm: true),
                          ),
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
    required this.categoryColor,
  });

  final TaskItem task;
  final Color categoryColor;
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
                            color: categoryColor,
                          ),
                        ),
                        if (task.assignee != null)
                          TextSpan(text: ' · ${task.assignee}'),
                        if (when != null)
                          TextSpan(
                            text: ' · ${AppDates.relativeDayTime(when)}',
                            style: overdue
                                ? TextStyle(color: AppColors.danger)
                                : null,
                          ),
                        if (task.priority == 'high')
                          TextSpan(
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
