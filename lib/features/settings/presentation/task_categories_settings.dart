import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/data/tasks_repository.dart';
import '../../operations/domain/task_category.dart';
import '../../operations/presentation/operations_providers.dart';
import '../../operations/presentation/task_category_style.dart';
import 'settings_providers.dart';

/// Ayarlar > Görev kategorileri: aç/kapat, taslaktan ekle, özel kategori
/// oluştur, yeniden adlandır, sil. Değişiklikler anında kaydedilir.
class TaskCategoriesCard extends ConsumerStatefulWidget {
  const TaskCategoriesCard({super.key});

  @override
  ConsumerState<TaskCategoriesCard> createState() => _TaskCategoriesCardState();
}

class _TaskCategoriesCardState extends ConsumerState<TaskCategoriesCard> {
  bool _busy = false;

  Future<bool> _persist(List<TaskCategory> next) async {
    if (_busy) return false;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(userSettingsProvider.notifier).saveTaskCategories(next);
      return true;
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Kategoriler kaydedilemedi.')),
        );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(List<TaskCategory> list, int index, bool value) {
    if (!value && TaskCategory.activeNames(list).length <= 1) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('En az bir kategori açık kalmalı.')),
        );
      return;
    }
    final next = [...list];
    next[index] = list[index].copyWith(enabled: value);
    _persist(next);
  }

  void _addTemplate(List<TaskCategory> list, TaskCategory template) {
    final existing = TaskCategory.find(list, template.name);
    if (existing != null) {
      final index = list.indexOf(existing);
      final next = [...list];
      next[index] = existing.copyWith(enabled: true);
      _persist(next);
      return;
    }
    if (list.length >= TaskCategory.maxCount) {
      _tooMany();
      return;
    }
    _persist([...list, template]);
  }

  void _tooMany() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content:
              Text('En çok ${TaskCategory.maxCount} kategori eklenebilir.'),
        ),
      );
  }

  Future<void> _create(List<TaskCategory> list) async {
    if (list.length >= TaskCategory.maxCount) {
      _tooMany();
      return;
    }
    final created = await _CategoryDialog.show(context, existing: list);
    if (created == null || !mounted) return;
    await _persist([...list, created]);
  }

  Future<void> _edit(List<TaskCategory> list, TaskCategory category) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final edited = await _CategoryDialog.show(
      context,
      existing: list,
      initial: category,
    );
    if (edited == null || !mounted) return;
    final next = [
      for (final c in list) identical(c, category) ? edited : c,
    ];
    final ok = await _persist(next);
    if (!ok || edited.name == category.name) return;
    try {
      await container
          .read(tasksRepositoryProvider)
          .renameCategory(category.name, edited.name);
      container.invalidate(opsTasksProvider);
      notifyTaskChange(container.invalidate);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Mevcut görevler taşınamadı.')),
      );
    }
  }

  Future<void> _delete(List<TaskCategory> list, TaskCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kategori silinsin mi?'),
        content: Text(
          '"${category.name}" listeden kalkar. Bu kategorideki görevler '
          'silinmez, adını korur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = [
      for (final c in list)
        if (!identical(c, category)) c,
    ];
    if (TaskCategory.activeNames(next).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir kategori açık kalmalı.')),
      );
      return;
    }
    await _persist(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ref.watch(taskCategoriesProvider);
    final templates = [
      for (final t in TaskCategory.templates)
        if (TaskCategory.find(list, t.name)?.enabled != true) t,
    ];
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.label_rounded,
            label: 'Görev kategorileri',
            color: AppColors.ops,
            trailing: '${TaskCategory.activeNames(list).length} açık',
          ),
          const SizedBox(height: 4),
          Text(
            'Kapalı kategoriler seçicide, filtrede ve AI önerilerinde görünmez; '
            'mevcut görevler kategorisini korur.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < list.length; i++)
            _CategoryRow(
              key: ValueKey('task-category-${list[i].name}'),
              category: list[i],
              busy: _busy,
              onToggle: (value) => _toggle(list, i, value),
              onEdit: list[i].custom ? () => _edit(list, list[i]) : null,
              onDelete: list[i].custom ? () => _delete(list, list[i]) : null,
            ),
          const SizedBox(height: 12),
          Text(
            'Kategori Taslakları',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (templates.isEmpty)
            Text(
              'Tüm taslaklar ekli.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in templates)
                  ActionChip(
                    key: ValueKey('task-category-template-${t.name}'),
                    avatar: Icon(
                      taskCategoryIcon(t.icon),
                      size: 16,
                      color: taskCategoryRoleColor(t.color),
                    ),
                    label: Text(t.name),
                    onPressed: _busy ? null : () => _addTemplate(list, t),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('task-category-create'),
            onPressed: _busy ? null : () => _create(list),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Özel kategori oluştur'),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.busy,
    required this.onToggle,
    this.onEdit,
    this.onDelete,
  });

  final TaskCategory category;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = taskCategoryRoleColor(category.color);
    return Row(
      children: [
        Icon(taskCategoryIcon(category.icon), size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: category.enabled
                  ? AppColors.textPrimary
                  : AppColors.textMuted,
            ),
          ),
        ),
        if (onEdit != null)
          PopupMenuButton<String>(
            tooltip: 'Kategori seçenekleri',
            enabled: !busy,
            icon: Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
            onSelected: (value) =>
                value == 'edit' ? onEdit!() : onDelete?.call(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              PopupMenuItem(value: 'delete', child: Text('Sil')),
            ],
          ),
        Switch(
          value: category.enabled,
          onChanged: busy ? null : onToggle,
        ),
      ],
    );
  }
}

/// Özel kategori oluşturma / düzenleme penceresi: ad, simge, renk.
class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.existing, this.initial});

  final List<TaskCategory> existing;
  final TaskCategory? initial;

  static Future<TaskCategory?> show(
    BuildContext context, {
    required List<TaskCategory> existing,
    TaskCategory? initial,
  }) =>
      showDialog<TaskCategory>(
        context: context,
        builder: (_) => _CategoryDialog(existing: existing, initial: initial),
      );

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late String _icon;
  late String _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _icon = widget.initial?.icon ?? 'idea';
    _color = widget.initial?.color ?? 'accent';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = TaskCategory.cleanName(_name.text);
    if (name == null) {
      setState(() => _error = 'Ad 1–${TaskCategory.nameMax} karakter olmalı.');
      return;
    }
    final clash = TaskCategory.find(widget.existing, name);
    if (clash != null && !identical(clash, widget.initial)) {
      setState(() => _error = 'Bu adla bir kategori zaten var.');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      initial == null
          ? TaskCategory(name: name, icon: _icon, color: _color, custom: true)
          : initial.copyWith(name: name, icon: _icon, color: _color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title:
          Text(widget.initial == null ? 'Yeni kategori' : 'Kategoriyi düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('task-category-name'),
              controller: _name,
              autofocus: true,
              maxLength: TaskCategory.nameMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Ad', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Text('Simge', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in TaskCategory.iconKeys)
                  ChoiceChip(
                    label: Icon(
                      taskCategoryIcon(key),
                      size: 18,
                      color: taskCategoryRoleColor(_color),
                    ),
                    showCheckmark: false,
                    selected: key == _icon,
                    onSelected: (_) => setState(() => _icon = key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Renk', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final key in TaskCategory.colorKeys)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = key),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: taskCategoryRoleColor(key),
                        shape: BoxShape.circle,
                      ),
                      child: key == _color
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: AppColors.onAccent,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}
