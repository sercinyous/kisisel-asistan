import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/templates/task_templates.dart';
import '../../../core/templates/template_chips.dart';
import '../../../core/utils/date_utils.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/tasks_repository.dart';
import '../domain/task_category.dart';
import '../domain/task_item.dart';
import 'operations_providers.dart';
import 'operations_widgets.dart';

/// Görev ekleme / düzenleme formu.
class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({super.key, this.task});

  final TaskItem? task;

  static Future<bool> show(BuildContext context, {TaskItem? task}) =>
      showOpsSheet(context, TaskFormSheet(task: task));

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  // schema.sql: tasks.title 1..300.
  static const int _titleMax = 300;
  static const int _descriptionMax = 2000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _category;
  late String _priority;
  String? _assignee;
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  bool _remind = true;

  /// Hatırlatma terminden kaç dakika önce.
  late int _offsetMinutes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _title = TextEditingController(text: task?.title ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    // Mevcut görev kategorisini korur (kapatılmış ya da silinmiş olsa bile).
    _category = task?.category ??
        TaskCategory.defaultName(ref.read(taskCategoriesProvider));
    _priority = task?.priority ?? 'medium';
    _assignee = task?.assignee;
    _offsetMinutes = ref.read(settingsOrDefaultProvider).eventRemindMinutes;

    final when = task?.scheduledAt;
    if (task != null && when != null) {
      _date = AppDates.startOfDay(when);
      _time = TimeOfDay(hour: when.hour, minute: when.minute);
      final due = task.dueAt, remind = task.remindAt;
      // Kapalı kayıt kapalı açılır; AI görevinde hatırlatma saati olmasa da açıktır.
      _remind = task.notify;
      // Kayıtlı aralık korunur; yalnızca hatırlatma varsa tam saatindedir.
      if (remind != null) {
        final diff = due == null ? 0 : due.difference(remind).inMinutes;
        _offsetMinutes = diff < 0 ? 0 : diff;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Şablon başlığı, kategoriyi ve önceliği doldurur; tarih ve kişi kullanıcıda
  /// kalır. Her alan sonradan düzenlenir.
  void _applyTemplate(TaskTemplate template) => setState(() {
        _title.text = template.title;
        final description = template.description;
        if (description != null) _description.text = description;
        if (ref
            .read(activeTaskCategoryNamesProvider)
            .contains(template.category)) {
          _category = template.category;
        }
        _priority = template.priority;
      });

  Future<void> _pickDate() async {
    final today = AppDates.startOfDay(DateTime.now());
    final initial = _date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(today) ? initial : today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });

    final date = _date;
    final due = date == null
        ? null
        : DateTime(date.year, date.month, date.day, _time.hour, _time.minute);
    final remind = due != null && _remind
        ? due.subtract(Duration(minutes: _offsetMinutes))
        : null;
    // Tarihsiz görevde bildirim zaten olmaz; sonradan tarih eklenirse
    // varsayılan (açık) geçerli olsun diye true kalır.
    final notify = due == null || _remind;
    final description = _description.text.trim();

    TaskItem? updated;
    try {
      final repository = container.read(tasksRepositoryProvider);
      final existing = widget.task;
      if (existing == null) {
        await repository.create(
          title: _title.text.trim(),
          description: description.isEmpty ? null : description,
          category: _category,
          priority: _priority,
          assignee: _assignee,
          dueAt: due,
          remindAt: remind,
          notify: notify,
        );
      } else {
        updated = await repository.update(
          TaskItem(
            id: existing.id,
            title: _title.text.trim(),
            description: description.isEmpty ? null : description,
            category: _category,
            priority: _priority,
            status: existing.status,
            assignee: _assignee,
            dueAt: due,
            remindAt: remind,
            completedAt: existing.completedAt,
            notify: notify,
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
    if (updated != null) {
      container.read(opsTasksProvider.notifier).applySaved(updated);
    }
    container.invalidate(opsTasksProvider);
    notifyTaskChange(container.invalidate);
    closeOpsSheet(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(settingsOrDefaultProvider).teamMembers;
    final assignee = _assignee;
    final date = _date;

    return OpsSheetFrame(
      title: widget.task == null ? 'Yeni görev' : 'Görevi düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.task == null)
          TemplateChips<TaskTemplate>(
            templates: TaskTemplates.all,
            labelOf: (template) => template.label,
            onSelected: _applyTemplate,
          ),
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
          controller: _description,
          maxLength: _descriptionMax,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
        ),
        const OpsFieldLabel('Kategori'),
        OpsChoiceWrap<String>(
          options: [
            for (final c in ref.watch(activeTaskCategoryNamesProvider)) (c, c),
            if (!ref.watch(activeTaskCategoryNamesProvider).contains(_category))
              (_category, _category),
          ],
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
        ),
        const OpsFieldLabel('Öncelik'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'low', label: Text('Düşük')),
            ButtonSegment(value: 'medium', label: Text('Orta')),
            ButtonSegment(value: 'high', label: Text('Yüksek')),
          ],
          selected: {_priority},
          onSelectionChanged: (selection) =>
              setState(() => _priority = selection.first),
        ),
        const OpsFieldLabel('İlgili kişi'),
        OpsChoiceWrap<String?>(
          options: [
            (null, 'Yok'),
            for (final name in team) (name, name),
            // Ekipten çıkarılmış kişi kayıtlı görevde kaybolmasın.
            if (assignee != null && !team.contains(assignee))
              (assignee, assignee),
          ],
          selected: assignee,
          onSelected: (value) => setState(() => _assignee = value),
        ),
        const OpsFieldLabel('Tarih ve saat'),
        OpsPickerRow(
          icon: Icons.event_rounded,
          label: date == null
              ? 'Tarih seç'
              : DateFormat('d MMM y, EEE', AppDates.locale).format(date),
          onTap: _pickDate,
          onClear: date == null ? null : () => setState(() => _date = null),
        ),
        if (date != null) ...[
          const SizedBox(height: 8),
          OpsPickerRow(
            icon: Icons.schedule_rounded,
            label: formatTimeOfDay(_time),
            onTap: _pickTime,
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('task-remind'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Hatırlat'),
          subtitle: Text(
            date == null
                ? 'Önce tarih seç.'
                : _offsetMinutes == 0
                    ? 'Tam saatinde bildirim.'
                    : '$_offsetMinutes dk önce bildirim.',
          ),
          value: date != null && _remind,
          onChanged:
              date == null ? null : (value) => setState(() => _remind = value),
        ),
      ],
    );
  }
}
