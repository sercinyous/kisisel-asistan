import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/templates/routine_templates.dart';
import '../../../core/templates/template_chips.dart';
import '../../../core/theme/app_theme.dart';
import '../../routines/data/routines_repository.dart';
import '../../routines/domain/routine.dart';
import 'operations_providers.dart';
import 'operations_widgets.dart';
import 'routines_view.dart';

const Map<String, String> _categoryLabels = {
  'operasyon': 'İş',
  'spor': 'Spor',
  'beslenme': 'Beslenme',
  'kisisel': 'Kişisel',
  'finans': 'Finans',
};

/// Rutin (tekrarlayan iş) ekleme / düzenleme formu.
class RoutineFormSheet extends ConsumerStatefulWidget {
  const RoutineFormSheet({super.key, this.routine, this.nextSortOrder = 0});

  final Routine? routine;

  /// Yeni kayıt için sıra numarası.
  final int nextSortOrder;

  static Future<bool> show(
    BuildContext context, {
    Routine? routine,
    int nextSortOrder = 0,
  }) =>
      showOpsSheet(
        context,
        RoutineFormSheet(routine: routine, nextSortOrder: nextSortOrder),
      );

  @override
  ConsumerState<RoutineFormSheet> createState() => _RoutineFormSheetState();
}

class _RoutineFormSheetState extends ConsumerState<RoutineFormSheet> {
  // schema.sql: routines.title 1..200.
  static const int _titleMax = 200;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late String _scope;
  late String _category;
  late RoutineFrequency _frequency;
  late Set<int> _days;
  late int _dayOfMonth;
  TimeOfDay? _time;
  late bool _notify;
  late bool _isActive;
  bool _daysError = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.routine;
    _title = TextEditingController(text: r?.title ?? '');
    _scope = Routine.scopes.contains(r?.scope) ? r!.scope : Routine.scopePersonal;
    _category =
        Routine.categories.contains(r?.category) ? r!.category : 'kisisel';
    _frequency = r?.frequency ?? RoutineFrequency.weekly;
    _days = {
      ...(r == null || r.isMonthly ? Routine.everyDay : r.daysOfWeek)
          .where((d) => d >= 1 && d <= 7),
    };
    _dayOfMonth = (r?.dayOfMonth ?? 1).clamp(1, 31);
    _time = r != null && r.hasTime
        ? TimeOfDay(hour: r.hour!, minute: r.minute!)
        : null;
    _notify = r?.notify ?? true;
    _isActive = r?.isActive ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _isMonthly => _frequency == RoutineFrequency.monthly;

  /// Şablon başlığı, sıklığı, günleri ve saati doldurur (kişisel kapsam);
  /// her alan sonradan düzenlenir.
  void _applyTemplate(RoutineTemplate template) => setState(() {
        _title.text = template.title;
        _scope = Routine.scopePersonal;
        if (Routine.categories.contains(template.category)) {
          _category = template.category;
        }
        _frequency = template.frequency;
        _days = {
          ...(template.isMonthly ? Routine.everyDay : template.daysOfWeek)
              .where((d) => d >= 1 && d <= 7),
        };
        _daysError = false;
        _dayOfMonth = (template.dayOfMonth ?? _dayOfMonth).clamp(1, 31);
        _time = template.hasTime
            ? TimeOfDay(hour: template.hour!, minute: template.minute!)
            : null;
      });

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  void _toggleDay(int day, bool selected) => setState(() {
        selected ? _days.add(day) : _days.remove(day);
        if (_days.isNotEmpty) _daysError = false;
      });

  Future<void> _save() async {
    final fieldsOk = _formKey.currentState!.validate();
    final daysOk = _isMonthly || _days.isNotEmpty;
    setState(() => _daysError = !daysOk);
    if (!fieldsOk || !daysOk) return;

    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });

    final existing = widget.routine;
    final draft = Routine(
      id: existing?.id ?? '',
      title: _title.text.trim(),
      scope: _scope,
      category: _category,
      frequency: _frequency,
      // Aylıkta günler yok sayılır; tablo boş listeyi kabul etmez.
      daysOfWeek: _isMonthly ? Routine.everyDay : (_days.toList()..sort()),
      dayOfMonth: _isMonthly ? _dayOfMonth : null,
      hour: _time?.hour,
      minute: _time?.minute,
      notify: _notify,
      isActive: _isActive,
      sortOrder: existing?.sortOrder ?? widget.nextSortOrder,
      createdAt: existing?.createdAt,
    );

    try {
      final repository = container.read(routinesRepositoryProvider);
      if (existing == null) {
        await repository.create(draft);
      } else {
        await repository.update(draft);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    notifyRoutineChange(container.invalidate);
    closeOpsSheet(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint =
        theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted);
    final time = _time;

    return OpsSheetFrame(
      title: widget.routine == null ? 'Yeni rutin' : 'Rutini düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.routine == null)
          TemplateChips<RoutineTemplate>(
            templates: RoutineTemplates.all,
            labelOf: (template) => template.label,
            onSelected: _applyTemplate,
          ),
        TextFormField(
          controller: _title,
          maxLength: _titleMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Başlık'),
          validator: (value) => validateTitle(value, _titleMax),
        ),
        const OpsFieldLabel('Kapsam'),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final s in Routine.scopes)
              ButtonSegment(value: s, label: Text(s)),
          ],
          selected: {_scope},
          onSelectionChanged: (selection) =>
              setState(() => _scope = selection.first),
        ),
        const OpsFieldLabel('Kategori'),
        OpsChoiceWrap<String>(
          options: [
            for (final c in Routine.categories) (c, _categoryLabels[c] ?? c),
          ],
          selected: _category,
          onSelected: (value) => setState(() => _category = value),
        ),
        const OpsFieldLabel('Sıklık'),
        SegmentedButton<RoutineFrequency>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: RoutineFrequency.weekly,
              label: Text('Haftalık'),
            ),
            ButtonSegment(
              value: RoutineFrequency.monthly,
              label: Text('Aylık'),
            ),
          ],
          selected: {_frequency},
          onSelectionChanged: (selection) =>
              setState(() => _frequency = selection.first),
        ),
        if (_isMonthly) ...[
          const OpsFieldLabel('Ayın günü'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 1; day <= 31; day++)
                _DayOfMonthCell(
                  key: ValueKey('dom-$day'),
                  day: day,
                  selected: day == _dayOfMonth,
                  onTap: () => setState(() => _dayOfMonth = day),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '29–31 seçilirse, o günün olmadığı aylarda ayın son günü geçerli '
            'olur.',
            style: hint,
          ),
        ] else ...[
          const OpsFieldLabel('Günler'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ActionChip(
                avatar: const Icon(Icons.done_all_outlined, size: 18),
                label: const Text('Her gün'),
                onPressed: () => setState(() {
                  _days = {...Routine.everyDay};
                  _daysError = false;
                }),
              ),
              for (final (index, label) in opsWeekdayLabels.indexed)
                FilterChip(
                  label: Text(label),
                  showCheckmark: false,
                  selected: _days.contains(index + 1),
                  onSelected: (selected) => _toggleDay(index + 1, selected),
                ),
            ],
          ),
          if (_daysError)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'En az bir gün seç.',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
        ],
        const OpsFieldLabel('Saat (isteğe bağlı)'),
        OpsPickerRow(
          icon: Icons.schedule_outlined,
          label: time == null ? 'Saat seç' : formatTimeOfDay(time),
          onTap: _pickTime,
          onClear: time == null ? null : () => setState(() => _time = null),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bildirim'),
          // Günlük/haftalık bildirim yalnızca saat verilmişse planlanır.
          subtitle: !_isMonthly && time == null
              ? const Text('Bildirim için saat seç.')
              : null,
          // Saat yokken anahtar devre dışı; görev formundaki "Hatırlat" gibi.
          value: !_isMonthly && time == null ? false : _notify,
          onChanged: !_isMonthly && time == null
              ? null
              : (value) => setState(() => _notify = value),
        ),
        if (widget.routine != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktif'),
            subtitle: const Text('Pasif rutin Gün ve Ay ekranında görünmez.'),
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
          ),
      ],
    );
  }
}

class _DayOfMonthCell extends StatelessWidget {
  const _DayOfMonthCell({
    super.key,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ayın $day. günü',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primary : AppColors.selection,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: Text(
                '$day',
                // Sabit hücre: metin ölçeği büyüse de taşmasın.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: AppType.chipValue,
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimary : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
