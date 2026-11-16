import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// Öğün kalemi ekleme / düzenleme formu.
class MealFormSheet extends ConsumerStatefulWidget {
  const MealFormSheet({super.key, this.log, this.mealType});

  /// Doluysa düzenleme.
  final NutritionLog? log;

  /// Yeni kayıtta önceden seçili öğün; boşsa saate göre seçilir.
  final String? mealType;

  static Future<bool> show(
    BuildContext context, {
    NutritionLog? log,
    String? mealType,
  }) =>
      showOpsSheet(context, MealFormSheet(log: log, mealType: mealType));

  @override
  ConsumerState<MealFormSheet> createState() => _MealFormSheetState();
}

class _MealFormSheetState extends ConsumerState<MealFormSheet> {
  static const int _quantityMax = 100;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late String _mealType;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  /// Günün saatine göre en olası öğün.
  static String _mealForHour(int hour) {
    if (hour < 11) return 'breakfast';
    if (hour < 16) return 'lunch';
    if (hour < 22) return 'dinner';
    return 'snack';
  }

  @override
  void initState() {
    super.initState();
    final log = widget.log;
    final when = log?.eatenAt ?? DateTime.now();
    // Sıfır değer boş alan olarak gösterilir; yazarken silmek gerekmesin.
    String number(double? value) =>
        value == null || value == 0 ? '' : HealthFormat.plain(value);

    _name = TextEditingController(text: log?.foodName ?? '');
    _quantity = TextEditingController(text: log?.quantityText ?? '');
    _calories = TextEditingController(text: number(log?.calories));
    _protein = TextEditingController(text: number(log?.proteinG));
    _carbs = TextEditingController(text: number(log?.carbsG));
    _fat = TextEditingController(text: number(log?.fatG));
    final preset = log?.mealType ?? widget.mealType;
    _mealType = NutritionLog.mealTypes.contains(preset)
        ? preset!
        : log != null
            ? 'snack'
            : _mealForHour(when.hour);
    _date = AppDates.startOfDay(when);
    _time = TimeOfDay(hour: when.hour, minute: when.minute);
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
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

    final quantity = _quantity.text.trim();
    double value(TextEditingController c) =>
        parseDecimal(c.text, decimals: 1) ?? 0;
    final existing = widget.log;
    final draft = NutritionLog(
      id: existing?.id ?? '',
      mealType: _mealType,
      foodName: _name.text.trim(),
      quantityText: quantity.isEmpty ? null : quantity,
      calories: value(_calories),
      proteinG: value(_protein),
      carbsG: value(_carbs),
      fatG: value(_fat),
      eatenAt: combineDateTime(_date, _time),
      source: existing?.source ?? 'manual',
    );

    try {
      final repository = container.read(healthRepositoryProvider);
      if (existing == null) {
        await repository.createNutritionLog(draft);
      } else {
        await repository.updateNutritionLog(draft);
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

  Widget _macroField({
    required String key,
    required TextEditingController controller,
    required String label,
    required double max,
    TextInputAction action = TextInputAction.next,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          key: Key(key),
          controller: controller,
          keyboardType: healthDecimalKeyboard,
          textInputAction: action,
          decoration: InputDecoration(labelText: label),
          validator: (value) => validateDecimal(value, min: 0, max: max),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return OpsSheetFrame(
      title: widget.log == null ? 'Öğün ekle' : 'Öğünü düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        OpsChoiceWrap<String>(
          options: [
            for (final type in NutritionLog.mealTypes)
              (type, HealthFormat.mealLabel(type)),
          ],
          selected: _mealType,
          onSelected: (value) => setState(() => _mealType = value),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('meal-name'),
          controller: _name,
          maxLength: NutritionLog.foodNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Ad'),
          validator: validateFoodName,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('meal-quantity'),
          controller: _quantity,
          maxLength: _quantityMax,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Miktar (isteğe bağlı)',
            hintText: 'ör. 150 g, 2 adet',
          ),
        ),
        _macroField(
          key: 'meal-calories',
          controller: _calories,
          label: 'Kalori (kcal)',
          max: NutritionLog.caloriesMax,
        ),
        _macroField(
          key: 'meal-protein',
          controller: _protein,
          label: 'Protein (g)',
          max: NutritionLog.macroMax,
        ),
        _macroField(
          key: 'meal-carbs',
          controller: _carbs,
          label: 'Karbonhidrat (g)',
          max: NutritionLog.macroMax,
        ),
        _macroField(
          key: 'meal-fat',
          controller: _fat,
          label: 'Yağ (g)',
          max: NutritionLog.macroMax,
          action: TextInputAction.done,
        ),
        const OpsFieldLabel('Saat'),
        HealthWhenPicker(
          date: _date,
          time: _time,
          onTime: (value) {
            if (mounted) setState(() => _time = value);
          },
        ),
      ],
    );
  }
}
