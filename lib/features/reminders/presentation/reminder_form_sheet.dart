import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/templates/template_chips.dart';
import '../../../core/theme/app_theme.dart';
import '../../operations/presentation/operations_widgets.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/reminder.dart';
import 'reminders_providers.dart';

/// Hatırlatıcı ekleme / düzenleme formu: başlık, saat, tekrar.
class ReminderFormSheet extends ConsumerStatefulWidget {
  const ReminderFormSheet({super.key, this.reminder});

  final Reminder? reminder;

  static Future<bool> show(BuildContext context, {Reminder? reminder}) =>
      showOpsSheet(context, ReminderFormSheet(reminder: reminder));

  @override
  ConsumerState<ReminderFormSheet> createState() => _ReminderFormSheetState();
}

class _ReminderFormSheetState extends ConsumerState<ReminderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late TimeOfDayValue _time;
  late ReminderRepeat _repeat;
  DateTime? _onDate;
  late Set<int> _days;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    _title = TextEditingController(text: r?.title ?? '');
    _time = r?.time ?? const TimeOfDayValue(9, 0);
    _repeat = r?.repeat ?? ReminderRepeat.daily;
    _onDate = r?.onDate;
    _days = {...?(r == null ? null : ReminderDays.daysOf(r.daysMask))};
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _applyTemplate(ReminderTemplate template) => setState(() {
        _title.text = template.title;
        _time = template.time;
        _repeat = template.repeat;
        _days = {...ReminderDays.daysOf(template.daysMask)};
        _error = null;
      });

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _time.hour, minute: _time.minute),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = TimeOfDayValue(picked.hour, picked.minute));
  }

  Future<void> _pickDate() async {
    final today = reminderDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _onDate != null && !_onDate!.isBefore(today) ? _onDate! : today,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _onDate = reminderDay(picked));
  }

  void _selectRepeat(ReminderRepeat repeat) => setState(() {
        _repeat = repeat;
        _error = null;
        if (repeat == ReminderRepeat.once && _onDate == null) {
          final now = DateTime.now();
          final todayAt =
              DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
          _onDate = reminderDay(
            todayAt.isAfter(now) ? now : now.add(const Duration(days: 1)),
          );
        }
      });

  ReminderDraft get _draft => ReminderDraft(
        title: _title.text,
        time: _time,
        repeat: _repeat,
        onDate: _onDate,
        daysMask: ReminderDays.maskOf(_days),
        enabled: widget.reminder?.enabled ?? true,
      );

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = _draft;
    final problem = draft.validationError;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final controller = ref.read(remindersControllerProvider);
      final existing = widget.reminder;
      if (existing == null) {
        await controller.create(draft);
      } else {
        await controller.update(existing.id, draft);
      }
      closeOpsSheet(navigator, route);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onDate = _onDate;
    return OpsSheetFrame(
      title: widget.reminder == null
          ? 'Yeni hatırlatıcı'
          : 'Hatırlatıcıyı düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.reminder == null)
          TemplateChips<ReminderTemplate>(
            title: 'Hazır şablonlar',
            templates: ReminderTemplate.all,
            labelOf: (t) => t.label,
            onSelected: _applyTemplate,
          ),
        TextFormField(
          key: const Key('reminder-title'),
          controller: _title,
          maxLength: ReminderDraft.maxTitleLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Başlık'),
          validator: (value) =>
              validateTitle(value, ReminderDraft.maxTitleLength),
        ),
        const OpsFieldLabel('Saat'),
        OpsPickerRow(
          key: const Key('reminder-time'),
          icon: Icons.schedule_outlined,
          label: _time.format(),
          onTap: _saving ? null : _pickTime,
        ),
        const OpsFieldLabel('Tekrar'),
        OpsChoiceWrap<ReminderRepeat>(
          options: [for (final r in ReminderRepeat.values) (r, r.label)],
          selected: _repeat,
          onSelected: _selectRepeat,
        ),
        if (_repeat == ReminderRepeat.once) ...[
          const OpsFieldLabel('Tarih'),
          OpsPickerRow(
            icon: Icons.event_outlined,
            label: onDate == null
                ? 'Tarih seç'
                : '${onDate.day.toString().padLeft(2, '0')}.'
                    '${onDate.month.toString().padLeft(2, '0')}.${onDate.year}',
            onTap: _saving ? null : _pickDate,
          ),
        ],
        if (_repeat == ReminderRepeat.custom) ...[
          const OpsFieldLabel('Günler'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (index, label) in ReminderDays.shortLabels.indexed)
                FilterChip(
                  label: Text(label),
                  showCheckmark: false,
                  selected: _days.contains(index + 1),
                  onSelected: (selected) => setState(() {
                    selected ? _days.add(index + 1) : _days.remove(index + 1);
                    _error = null;
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
