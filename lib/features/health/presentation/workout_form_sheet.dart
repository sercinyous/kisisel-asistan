import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/templates/template_chips.dart';
import '../../../core/templates/workout_templates.dart';
import '../../../core/utils/date_utils.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// Antrenman ekleme / düzenleme formu.
class WorkoutFormSheet extends ConsumerStatefulWidget {
  const WorkoutFormSheet({super.key, this.workout});

  /// Doluysa düzenleme.
  final WorkoutLog? workout;

  static Future<bool> show(BuildContext context, {WorkoutLog? workout}) =>
      showOpsSheet(context, WorkoutFormSheet(workout: workout));

  @override
  ConsumerState<WorkoutFormSheet> createState() => _WorkoutFormSheetState();
}

class _WorkoutFormSheetState extends ConsumerState<WorkoutFormSheet> {
  static const int _titleMax = 120;
  static const int _notesMax = 500;

  /// `calories_burned` için alt sınır 0'dır; üst sınır yalnızca yazım
  /// hatasını yakalamak içindir.
  static const int _caloriesMax = 20000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _duration;
  late final TextEditingController _distance;
  late final TextEditingController _calories;
  late final TextEditingController _notes;
  late String _type;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final workout = widget.workout;
    final when = workout?.loggedAt ?? DateTime.now();
    final distance = workout?.distanceKm;
    _title = TextEditingController(text: workout?.title ?? '');
    _duration =
        TextEditingController(text: workout?.durationMin?.toString() ?? '');
    _distance = TextEditingController(
      text: distance == null ? '' : HealthFormat.plain(distance),
    );
    _calories =
        TextEditingController(text: workout?.caloriesBurned?.toString() ?? '');
    _notes = TextEditingController(text: workout?.notes ?? '');
    _type = WorkoutLog.workoutTypes.contains(workout?.workoutType)
        ? workout!.workoutType
        : WorkoutLog.workoutTypes.first;
    _date = AppDates.startOfDay(when);
    _time = TimeOfDay(hour: when.hour, minute: when.minute);
  }

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    _distance.dispose();
    _calories.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Şablon türü, başlığı ve süreyi doldurur; mesafe ve kalori kullanıcıda
  /// kalır. Her alan sonradan düzenlenir.
  void _applyTemplate(WorkoutTemplate template) => setState(() {
        if (WorkoutLog.workoutTypes.contains(template.workoutType)) {
          _type = template.workoutType;
        }
        _title.text = template.title;
        _duration.text = '${template.durationMin}';
      });

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final at = combineDateTime(_date, _time);
    if (at.isAfter(DateTime.now())) {
      setState(() => _error = 'Gelecekteki bir zaman seçilemez.');
      return;
    }
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });

    final title = _title.text.trim();
    final notes = _notes.text.trim();
    final existing = widget.workout;
    final draft = WorkoutLog(
      id: existing?.id ?? '',
      workoutType: _type,
      title: title.isEmpty ? null : title,
      durationMin: int.tryParse(_duration.text.trim()),
      distanceKm: parseDecimal(_distance.text),
      caloriesBurned: int.tryParse(_calories.text.trim()),
      notes: notes.isEmpty ? null : notes,
      loggedAt: at,
      source: existing?.source ?? 'manual',
    );

    try {
      final repository = container.read(healthRepositoryProvider);
      if (existing == null) {
        await repository.createWorkout(draft);
      } else {
        await repository.updateWorkout(draft);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    invalidateHealthData(container);
    closeOpsSheet(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
    return OpsSheetFrame(
      title: widget.workout == null ? 'Antrenman ekle' : 'Antrenmanı düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.workout == null)
          TemplateChips<WorkoutTemplate>(
            templates: WorkoutTemplates.all,
            labelOf: (template) => template.label,
            onSelected: _applyTemplate,
          ),
        OpsChoiceWrap<String>(
          options: [
            for (final type in WorkoutLog.workoutTypes)
              (type, HealthFormat.workoutLabel(type)),
          ],
          selected: _type,
          onSelected: (value) => setState(() => _type = value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('workout-title'),
          controller: _title,
          maxLength: _titleMax,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Başlık (isteğe bağlı)'),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('workout-duration'),
          controller: _duration,
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Süre (dk)'),
          validator: (value) => validateInteger(
            value,
            min: WorkoutLog.durationMinMin,
            max: WorkoutLog.durationMinMax,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('workout-distance'),
          controller: _distance,
          keyboardType: healthDecimalKeyboard,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Mesafe (km)'),
          validator: (value) => validateDecimal(
            value,
            min: 0,
            max: WorkoutLog.distanceKmMax,
            decimals: 2,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('workout-calories'),
          controller: _calories,
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Yakılan kalori (kcal)'),
          validator: (value) =>
              validateInteger(value, min: 0, max: _caloriesMax),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('workout-notes'),
          controller: _notes,
          maxLength: _notesMax,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)'),
        ),
        const OpsFieldLabel('Zaman'),
        HealthWhenPicker(
          date: _date,
          time: _time,
          onDate: (value) {
            if (mounted) setState(() => _date = value);
          },
          onTime: (value) {
            if (mounted) setState(() => _time = value);
          },
        ),
      ],
    );
  }
}
