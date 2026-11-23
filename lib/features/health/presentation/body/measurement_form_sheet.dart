import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../operations/presentation/operations_widgets.dart';
import '../health_format.dart';
import '../health_widgets.dart';
import '../providers/body_providers.dart';
import 'body_format.dart';

/// Mezura formu: 6 alan (cm, bir ondalık), önceki değer ipucu, alan başına
/// yardım satırı; en az bir alan; 5 cm'den büyük farkta onay sorar. Aynı gün
/// varsa üzerine yazar.
class MeasurementFormSheet extends ConsumerStatefulWidget {
  const MeasurementFormSheet({super.key, this.date});

  /// Ölçüm günü; verilmezse bugün.
  final DateTime? date;

  /// Kaydedildiyse `true`.
  static Future<bool> show(BuildContext context, {DateTime? date}) =>
      showOpsSheet(context, MeasurementFormSheet(date: date));

  @override
  ConsumerState<MeasurementFormSheet> createState() =>
      _MeasurementFormSheetState();
}

class _MeasurementFormSheetState extends ConsumerState<MeasurementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = {
    for (final f in BodyField.values) f: TextEditingController(),
  };
  late DateTime _date;
  bool _prefilled = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = AppDates.startOfDay(widget.date ?? DateTime.now());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Seçili günün kaydı varsa alanlar onunla dolar (düzenleme).
  void _prefill(List<BodyMeasurement> entries) {
    if (_prefilled) return;
    _prefilled = true;
    final same = entries.where((m) => m.measuredOn == _date);
    if (same.isEmpty) return;
    for (final e in same.first.values.entries) {
      _controllers[e.key]!.text = BodyFormat.cm(e.value);
    }
  }

  Map<BodyField, double?> _values() => {
        for (final f in BodyField.values)
          f: parseDecimal(_controllers[f]!.text, decimals: 1),
      };

  Future<void> _pickDate() async {
    final today = AppDates.startOfDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(() => _date = AppDates.startOfDay(picked));
    }
  }

  Future<bool> _confirmSuspicious(
    List<BodyField> fields,
    BodyMeasurement previous,
    Map<BodyField, double?> next,
  ) async {
    final lines = [
      for (final f in fields)
        '${f.label}: ${BodyFormat.cm(previous[f]!)} → '
            '${BodyFormat.cm(next[f]!)} cm',
    ].join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yanlış girmiş olabilir misin?'),
        content: Text('Önceki ölçüden 5 cm\'den fazla fark var.\n\n$lines'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Düzelt'),
          ),
          FilledButton(
            key: const Key('measurement-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Doğru'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save(List<BodyMeasurement> entries) async {
    if (!_formKey.currentState!.validate()) return;
    final values = _values();
    final invalid = validateMeasurement(values);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    final previous = measurementBefore(entries, _date);
    final suspicious = suspiciousFields(previous, values);
    if (suspicious.isNotEmpty &&
        !await _confirmSuspicious(suspicious, previous!, values)) {
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(bodyRepositoryProvider).upsertMeasurement(
            BodyMeasurement(
              measuredOn: _date,
              values: {
                for (final e in values.entries)
                  if (e.value != null) e.key: e.value!,
              },
            ),
          );
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    ref.invalidate(measurementsProvider);
    closeOpsSheet(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = ref.watch(measurementsProvider).valueOrNull ??
        const <BodyMeasurement>[];
    _prefill(entries);
    final previous = measurementBefore(entries, _date);

    return OpsSheetFrame(
      title: 'Ölçü ekle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: () => _save(entries),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('measurement-date'),
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(BodyFormat.longDate(_date)),
          ),
        ),
        for (final f in BodyField.values) ...[
          TextFormField(
            key: Key('measurement-${f.name}'),
            controller: _controllers[f],
            keyboardType: healthDecimalKeyboard,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: f.label,
              suffixText: 'cm',
              hintText: previous?[f] == null
                  ? null
                  : 'Önceki: ${BodyFormat.cm(previous![f]!)}',
              helperText: f.help,
              helperMaxLines: 2,
            ),
            validator: (v) => validateDecimal(
              v,
              min: BodyLimits.minCm,
              max: BodyLimits.maxCm,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        Text(
          'Her alan isteğe bağlı; en az birini doldur.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}
