import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/templates/meal_templates.dart';
import '../../../core/templates/template_chips.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/presentation/operations_widgets.dart';
import '../data/food_catalog.dart';
import '../domain/food_item.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// Öğün kalemi ekleme / düzenleme formu. "Besin ara" paketli listeden besin
/// seçtirir ve gram/porsiyona göre kalori ile makroları doldurur; değerler
/// sonradan elle düzenlenebilir, elle giriş her zaman çalışır. Kaydın kaynağı
/// besin seçilse de değişmez.
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

  /// Besin seçilince gram alanının başlangıç değeri (listedeki değerler 100 g).
  static const double _defaultGrams = 100;

  /// Gram üst sınırı: en yağlı besinde bile makro sütun sınırını
  /// (`numeric(6,1)`) aşmaz.
  static const double _gramsMax = 5000;
  static const int _portionCountMax = 99;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _search;
  late final TextEditingController _grams;
  late String _mealType;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  /// Listeden seçilen besin; boşsa elle giriş (gram alanı görünmez).
  FoodItem? _food;

  /// Seçili porsiyonun `_food.portions` sırası ve adedi; boşsa gram elle yazıldı.
  int? _portionIndex;
  int _portionCount = 1;

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
    _search = TextEditingController();
    _grams = TextEditingController();
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
    _search.dispose();
    _grams.dispose();
    super.dispose();
  }

  /// Gram alanı geçerliyse değeri, değilse `null` (hesap uygulanmaz).
  static double? _validGrams(String? text) {
    final grams = parseDecimal(text, decimals: 1);
    if (grams == null || grams <= 0 || grams > _gramsMax) return null;
    return grams;
  }

  static String? _gramsError(String? text) {
    if ((text ?? '').trim().isEmpty) return 'Gram girilmeli.';
    final grams = parseDecimal(text, decimals: 1);
    if (grams == null) return 'Geçerli bir sayı gir.';
    if (grams <= 0) return 'Gram 0\'dan büyük olmalı.';
    if (grams > _gramsMax) {
      return 'Gram en fazla ${HealthFormat.plain(_gramsMax)} olabilir.';
    }
    return null;
  }

  /// Form alanı metni: tek ondalık (veritabanı ölçeği), sıfır boş alan.
  static String _fieldNumber(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == 0 ? '' : HealthFormat.plain(rounded);
  }

  /// [grams] gram [food] için kalori, makro ve miktar metnini doldurur.
  void _fill(FoodItem food, double grams) {
    final macros = food.forGrams(grams);
    _calories.text = _fieldNumber(macros.kcal);
    _protein.text = _fieldNumber(macros.protein);
    _carbs.text = _fieldNumber(macros.carbs);
    _fat.text = _fieldNumber(macros.fat);
    final amount = '${HealthFormat.plain(grams)} g';
    final index = _portionIndex;
    _quantity.text = index == null
        ? amount
        : '${food.portions[index].describe(_portionCount)} · $amount';
  }

  void _selectFood(FoodItem food) {
    FocusScope.of(context).unfocus();
    setState(() {
      _food = food;
      _portionIndex = null;
      _portionCount = 1;
      _search.clear();
      _name.text = food.name;
      _grams.text = HealthFormat.plain(_defaultGrams);
      _fill(food, _defaultGrams);
    });
  }

  /// Şablon öğün türünü, adı, miktarı, kalori ve makroları doldurur (yaklaşık
  /// değerler). Besin listesinden seçim bırakılır; her alan elle düzenlenir.
  void _applyTemplate(MealTemplate template) {
    FocusScope.of(context).unfocus();
    setState(() {
      _food = null;
      _portionIndex = null;
      _portionCount = 1;
      _search.clear();
      _grams.clear();
      _mealType = template.mealType;
      _name.text = template.foodName;
      _quantity.text = template.quantityText;
      _calories.text = _fieldNumber(template.calories);
      _protein.text = _fieldNumber(template.proteinG);
      _carbs.text = _fieldNumber(template.carbsG);
      _fat.text = _fieldNumber(template.fatG);
    });
  }

  /// Seçimi bırakır; doldurulmuş alanlar silinmez, elle sürdürülür.
  void _clearFood() => setState(() {
        _food = null;
        _portionIndex = null;
        _portionCount = 1;
      });

  /// Gram elle yazıldı: porsiyon seçimi düşer, geçerliyse değerler yeniden
  /// hesaplanır. Boş/0/negatif/aşırı gramda alanlara dokunulmaz.
  void _onGramsChanged(String value) {
    final food = _food;
    if (food == null) return;
    setState(() {
      _portionIndex = null;
      _portionCount = 1;
      final grams = _validGrams(value);
      if (grams != null) _fill(food, grams);
    });
  }

  void _applyPortion(FoodItem food) {
    final grams = food.portions[_portionIndex!].grams * _portionCount;
    _grams.text = HealthFormat.plain(grams);
    _fill(food, grams);
  }

  void _onPortionSelected(FoodItem food, int index, bool selected) {
    setState(() {
      _portionCount = 1;
      if (selected) {
        _portionIndex = index;
        _applyPortion(food);
        return;
      }
      // Seçimi kaldırmak gramı korur; yalnızca miktar metni sadeleşir.
      _portionIndex = null;
      final grams = _validGrams(_grams.text);
      if (grams != null) _fill(food, grams);
    });
  }

  bool _canChangeCount(FoodItem food, int delta) {
    final index = _portionIndex;
    if (index == null) return false;
    final next = _portionCount + delta;
    return next >= 1 &&
        next <= _portionCountMax &&
        food.portions[index].grams * next <= _gramsMax;
  }

  void _changeCount(FoodItem food, int delta) {
    if (!_canChangeCount(food, delta)) return;
    setState(() {
      _portionCount += delta;
      _applyPortion(food);
    });
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

  Widget _hint(String message) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
        child: Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );

  Widget _buildResults(AsyncValue<FoodCatalog> catalog, String query) {
    return catalog.when(
      loading: () => _hint('Besin listesi yükleniyor…'),
      error: (_, __) => _hint('Besin listesi yüklenemedi. Elle girebilirsin.'),
      data: (data) {
        final matches = data.search(query);
        if (matches.isEmpty) {
          return _hint('Listede yok. Ad ve değerleri aşağıdan elle gir.');
        }
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final food in matches)
              ListTile(
                key: Key('food-${food.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                title: Text(
                  food.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                subtitle: Text(
                  '100 g: ${HealthFormat.kcal(food.kcal100)} · '
                  'protein ${HealthFormat.grams(food.protein100)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                onTap: () => _selectFood(food),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSelection(FoodItem food) {
    final theme = Theme.of(context);
    final secondary =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final portionIndex = _portionIndex;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BentoCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    food.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const Key('food-clear'),
                  tooltip: 'Seçimi kaldır',
                  onPressed: _clearFood,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '100 g için: ${HealthFormat.kcal(food.kcal100)} · '
                'protein ${HealthFormat.grams(food.protein100)} · '
                'karbonhidrat ${HealthFormat.grams(food.carbs100)} · '
                'yağ ${HealthFormat.grams(food.fat100)}',
                style: secondary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: TextFormField(
                key: const Key('meal-grams'),
                controller: _grams,
                keyboardType: healthDecimalKeyboard,
                textInputAction: TextInputAction.next,
                autovalidateMode: AutovalidateMode.always,
                decoration: const InputDecoration(
                  labelText: 'Gram',
                  suffixText: 'g',
                ),
                validator: _gramsError,
                onChanged: _onGramsChanged,
              ),
            ),
            if (food.portions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (index, portion) in food.portions.indexed)
                      ChoiceChip(
                        label: Text(
                          '${portion.name} '
                          '(${HealthFormat.plain(portion.grams)} g)',
                        ),
                        showCheckmark: false,
                        selected: portionIndex == index,
                        onSelected: (selected) =>
                            _onPortionSelected(food, index, selected),
                      ),
                  ],
                ),
              ),
            if (portionIndex != null)
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('Adet', style: theme.textTheme.labelLarge),
                  ),
                  IconButton(
                    key: const Key('portion-dec'),
                    tooltip: 'Azalt',
                    onPressed: _canChangeCount(food, -1)
                        ? () => _changeCount(food, -1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$_portionCount',
                      key: const Key('portion-count'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('portion-inc'),
                    tooltip: 'Artır',
                    onPressed: _canChangeCount(food, 1)
                        ? () => _changeCount(food, 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            if (food.source.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 12),
                child: Text(
                  'Kaynak: ${food.source}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodSearch() {
    // Liste form açılır açılmaz okunmaya başlar; ilk harfte hazır olur.
    final catalog = ref.watch(foodCatalogProvider);
    final query = _search.text.trim();
    final food = _food;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('meal-food-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Besin ara',
            hintText: 'ör. yumurta, süt, yulaf',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Aramayı temizle',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (query.isNotEmpty) _buildResults(catalog, query),
        if (food != null) _buildSelection(food),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return OpsSheetFrame(
      title: widget.log == null ? 'Öğün ekle' : 'Öğünü düzenle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.log == null)
          TemplateChips<MealTemplate>(
            templates: MealTemplates.all,
            labelOf: (template) => template.label,
            onSelected: _applyTemplate,
            hint: 'Değerler yaklaşıktır; kendi porsiyonuna göre düzenle.',
          ),
        OpsChoiceWrap<String>(
          options: [
            for (final type in NutritionLog.mealTypes)
              (type, HealthFormat.mealLabel(type)),
          ],
          selected: _mealType,
          onSelected: (value) => setState(() => _mealType = value),
        ),
        const SizedBox(height: 12),
        _buildFoodSearch(),
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
