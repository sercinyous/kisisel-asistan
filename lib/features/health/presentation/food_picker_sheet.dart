import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/presentation/operations_widgets.dart';
import '../data/food_catalog.dart';
import '../domain/food_item.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'meal_form_sheet.dart';

/// Satır özeti: varsayılan porsiyonun ve 100 g'ın kalorisi.
/// "1 adet (50 g): 78 kcal · 100 g: 156 kcal"
String foodSummary(FoodItem food) {
  final per100 = '100 g: ${HealthFormat.kcal(food.kcal100)}';
  if (food.portions.isEmpty) return per100;
  final portion = food.portions.first;
  final kcal = food.forGrams(portion.grams).kcal;
  return '${portion.name} (${HealthFormat.plain(portion.grams)} g): '
      '${HealthFormat.kcal(kcal)} · $per100';
}

/// 100 g için kalori ve (biliniyorsa) makrolar.
String food100Detail(FoodItem food) {
  final parts = ['100 g için: ${HealthFormat.kcal(food.kcal100)}'];
  if (food.hasMacros) {
    parts
      ..add('protein ${HealthFormat.grams(food.protein100!)}')
      ..add('karbonhidrat ${HealthFormat.grams(food.carbs100!)}')
      ..add('yağ ${HealthFormat.grams(food.fat100!)}');
  } else {
    parts.add('makro bilgisi yok');
  }
  return parts.join(' · ');
}

/// Son eklenen besin kimlikleri (cihazda, en yeni başta).
class RecentFoodsStore {
  const RecentFoodsStore({this.open = SharedPreferences.getInstance});

  static const String key = 'recent_food_ids';
  static const int max = 8;

  final Future<SharedPreferences> Function() open;

  Future<List<String>> read() async {
    try {
      final prefs = await open();
      return prefs.getStringList(key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(List<String> ids) async {
    try {
      final prefs = await open();
      await prefs.setStringList(key, ids);
    } catch (_) {
      // Cihazda saklanamazsa liste yalnızca bu oturumda kalır.
    }
  }
}

final recentFoodsStoreProvider =
    Provider<RecentFoodsStore>((ref) => const RecentFoodsStore());

class RecentFoodsNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() => ref.read(recentFoodsStoreProvider).read();

  /// [id]'yi başa alır; liste [RecentFoodsStore.max] ile sınırlıdır.
  Future<void> add(String id) async {
    final current = state.valueOrNull ?? await future;
    final next = [
      id,
      for (final other in current)
        if (other != id) other,
    ].take(RecentFoodsStore.max).toList();
    state = AsyncData(next);
    await ref.read(recentFoodsStoreProvider).write(next);
  }
}

final recentFoodsProvider =
    AsyncNotifierProvider<RecentFoodsNotifier, List<String>>(
  RecentFoodsNotifier.new,
);

/// Besin seçici: kategori çipleri, arama, son kullanılanlar. Satıra dokunmak
/// miktar sayfasını açar; eklenince seçici de kapanır.
class FoodPickerSheet extends ConsumerStatefulWidget {
  const FoodPickerSheet({super.key, this.mealType});

  /// Önceden seçili öğün; boşsa saate göre.
  final String? mealType;

  static Future<bool> show(BuildContext context, {String? mealType}) =>
      showOpsSheet(context, FoodPickerSheet(mealType: mealType));

  @override
  ConsumerState<FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends ConsumerState<FoodPickerSheet> {
  static const int _searchLimit = 60;

  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(FoodItem food) async {
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final saved = await FoodAmountSheet.show(context,
        food: food, mealType: widget.mealType);
    if (saved) closeOpsSheet(navigator, route);
  }

  Future<void> _manual() async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final saved = await MealFormSheet.show(context, mealType: widget.mealType);
    if (saved) closeOpsSheet(navigator, route);
  }

  List<FoodItem> _filtered(FoodCatalog catalog, String query) {
    final category = _category;
    if (query.isNotEmpty) {
      final hits = catalog.search(query, limit: catalog.items.length);
      return [
        for (final food in hits)
          if (category == null || food.categories.contains(category)) food,
      ].take(_searchLimit).toList();
    }
    if (category != null) return catalog.inCategory(category);
    return [
      for (final food in catalog.items)
        if (food.categories.isNotEmpty) food,
    ];
  }

  Widget _hint(String message) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );

  Widget _row(FoodItem food, {String prefix = 'picker-food'}) {
    final theme = Theme.of(context);
    final note = food.note;
    return ListTile(
      key: Key('$prefix-${food.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      title: Text(
        food.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        note == null ? foodSummary(food) : '${foodSummary(food)}\n$note',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style:
            theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      trailing:
          Icon(Icons.add_circle_outline_outlined, color: AppColors.nutrition),
      onTap: () => _open(food),
    );
  }

  Widget _list(FoodCatalog catalog, List<String> recentIds) {
    final query = _search.text.trim();
    final foods = _filtered(catalog, query);
    final showRecent = query.isEmpty && _category == null;
    final recent = showRecent
        ? [
            for (final id in recentIds)
              if (catalog.byId(id) case final FoodItem food) food,
          ]
        : const <FoodItem>[];
    if (foods.isEmpty && recent.isEmpty) {
      return ListView(
        children: [_hint('Listede yok. "Elle gir" ile ekleyebilirsin.')],
      );
    }
    return ListView(
      key: const Key('food-picker-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          _label('Son kullanılanlar'),
          for (final food in recent) _row(food, prefix: 'recent-food'),
          _label('Tüm besinler'),
        ],
        for (final food in foods) _row(food),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(foodCatalogProvider);
    final recent = ref.watch(recentFoodsProvider).valueOrNull ?? const [];
    final height = MediaQuery.sizeOf(context).height * 0.85;
    final query = _search.text.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                        Text('Besin ekle', style: theme.textTheme.titleLarge),
                  ),
                  TextButton.icon(
                    key: const Key('food-picker-manual'),
                    onPressed: _manual,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Elle gir'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('food-picker-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Besin ara',
                  hintText: 'ör. yumurta, muz, ayran',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramayı temizle',
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_outlined),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: SingleChildScrollView(
                  key: const Key('food-picker-categories'),
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final category in FoodCategories.all)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('food-category-$category'),
                          label: Text(category),
                          showCheckmark: false,
                          selected: _category == category,
                          onSelected: (selected) => setState(
                            () => _category = selected ? category : null,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              Expanded(
                child: catalog.when(
                  loading: () => _hint('Besin listesi yükleniyor…'),
                  error: (_, __) => _hint(
                    'Besin listesi yüklenemedi. "Elle gir" ile ekleyebilirsin.',
                  ),
                  data: (data) => _list(data, recent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seçilen besinin miktar sayfası: porsiyon ya da gram, adet, canlı kalori ve
/// makrolar, öğün seçimi; "Kaydet" kaydı ekler.
class FoodAmountSheet extends ConsumerStatefulWidget {
  const FoodAmountSheet({super.key, required this.food, this.mealType});

  final FoodItem food;
  final String? mealType;

  static Future<bool> show(
    BuildContext context, {
    required FoodItem food,
    String? mealType,
  }) =>
      showOpsSheet(context, FoodAmountSheet(food: food, mealType: mealType));

  @override
  ConsumerState<FoodAmountSheet> createState() => _FoodAmountSheetState();
}

class _FoodAmountSheetState extends ConsumerState<FoodAmountSheet> {
  static const double _gramsMax = 5000;
  static const double _gramStep = 10;
  static const double _portionStep = 0.5;
  static const double _portionMax = 99;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _grams;

  /// Seçili porsiyon sırası; `null` gram birimi.
  int? _portionIndex;
  double _count = 1;
  late String _mealType;
  bool _saving = false;
  String? _error;

  FoodItem get _food => widget.food;

  @override
  void initState() {
    super.initState();
    _portionIndex = _food.portions.isEmpty ? null : 0;
    _grams = TextEditingController(text: HealthFormat.plain(100));
    final preset = widget.mealType;
    _mealType = NutritionLog.mealTypes.contains(preset)
        ? preset!
        : mealTypeForHour(DateTime.now().hour);
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  /// Seçime göre toplam gram; gram alanı geçersizse `null`.
  double? get _totalGrams {
    final index = _portionIndex;
    if (index != null) return _food.portions[index].grams * _count;
    final grams = parseDecimal(_grams.text, decimals: 1);
    if (grams == null || grams <= 0 || grams > _gramsMax) return null;
    return grams;
  }

  String? _gramsError(String? text) {
    if (_portionIndex != null) return null;
    if ((text ?? '').trim().isEmpty) return 'Gram girilmeli.';
    final grams = parseDecimal(text, decimals: 1);
    if (grams == null) return 'Geçerli bir sayı gir.';
    if (grams <= 0) return 'Gram 0\'dan büyük olmalı.';
    if (grams > _gramsMax) {
      return 'Gram en fazla ${HealthFormat.plain(_gramsMax)} olabilir.';
    }
    return null;
  }

  void _selectUnit(int? index) => setState(() {
        _portionIndex = index;
        _count = 1;
      });

  bool _canStep(int direction) {
    final index = _portionIndex;
    if (index != null) {
      final next = _count + direction * _portionStep;
      return next >= _portionStep &&
          next <= _portionMax &&
          _food.portions[index].grams * next <= _gramsMax;
    }
    final grams = _totalGrams ?? 0;
    final next = grams + direction * _gramStep;
    return next > 0 && next <= _gramsMax;
  }

  void _step(int direction) {
    if (!_canStep(direction)) return;
    setState(() {
      if (_portionIndex != null) {
        _count += direction * _portionStep;
      } else {
        final next = (_totalGrams ?? 0) + direction * _gramStep;
        _grams.text = HealthFormat.plain(next);
      }
    });
  }

  String _quantityText(double grams) {
    final amount = '${HealthFormat.plain(grams)} g';
    final index = _portionIndex;
    if (index == null) return amount;
    final portion = _food.portions[index];
    final whole = _count == _count.truncateToDouble();
    final label = whole
        ? portion.describe(_count.toInt())
        : '${HealthFormat.plain(_count)} × ${portion.name}';
    return '$label · $amount';
  }

  static double _round1(double value) => (value * 10).round() / 10;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final grams = _totalGrams;
    if (grams == null) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });

    final macros = _food.forGrams(grams);
    final draft = NutritionLog(
      id: '',
      mealType: _mealType,
      foodName: _food.name.length > NutritionLog.foodNameMaxLength
          ? _food.name.substring(0, NutritionLog.foodNameMaxLength)
          : _food.name,
      quantityText: _quantityText(grams),
      calories: _round1(macros.kcal),
      proteinG: _round1(macros.protein ?? 0),
      carbsG: _round1(macros.carbs ?? 0),
      fatG: _round1(macros.fat ?? 0),
      eatenAt: DateTime.now(),
      source: 'manual',
    );

    try {
      await container.read(healthRepositoryProvider).createNutritionLog(draft);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    await container.read(recentFoodsProvider.notifier).add(_food.id);
    invalidateHealthData(container);
    closeOpsSheet(navigator, route);
  }

  Widget _macroCell(String label, double? value) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value == null ? '—' : HealthFormat.grams(value),
            style: theme.textTheme.titleSmall,
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _totals() {
    final theme = Theme.of(context);
    final grams = _totalGrams;
    final macros = grams == null ? null : _food.forGrams(grams);
    return BentoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            macros == null ? '—' : HealthFormat.kcal(macros.kcal),
            key: const Key('amount-kcal'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: AppColors.nutrition),
          ),
          if (grams != null)
            Text(
              '${HealthFormat.plain(grams)} g',
              key: const Key('amount-grams-total'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          const SizedBox(height: 12),
          if (_food.hasMacros)
            Row(
              children: [
                _macroCell('Protein', macros?.protein),
                _macroCell('Karbonhidrat', macros?.carbs),
                _macroCell('Yağ', macros?.fat),
              ],
            )
          else
            Text(
              'Bu besinin makro bilgisi yok; yalnızca kalori kaydedilir.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = _food.note;
    final index = _portionIndex;
    return OpsSheetFrame(
      title: _food.name,
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        Text(
          food100Detail(_food),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    key: const Key('amount-note'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        const OpsFieldLabel('Birim'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (i, portion) in _food.portions.indexed)
              ChoiceChip(
                key: Key('amount-unit-$i'),
                label: Text(
                  '${portion.name} (${HealthFormat.plain(portion.grams)} g)',
                ),
                showCheckmark: false,
                selected: index == i,
                onSelected: (_) => _selectUnit(i),
              ),
            ChoiceChip(
              key: const Key('amount-unit-gram'),
              label: const Text('Gram'),
              showCheckmark: false,
              selected: index == null,
              onSelected: (_) => _selectUnit(null),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              key: const Key('amount-dec'),
              tooltip: 'Azalt',
              onPressed: _canStep(-1) ? () => _step(-1) : null,
              icon: const Icon(Icons.remove_circle_outline_outlined),
            ),
            Expanded(
              child: index != null
                  ? Text(
                      HealthFormat.plain(_count),
                      key: const Key('amount-count'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    )
                  : TextFormField(
                      key: const Key('amount-grams'),
                      controller: _grams,
                      keyboardType: healthDecimalKeyboard,
                      textAlign: TextAlign.center,
                      autovalidateMode: AutovalidateMode.always,
                      decoration: const InputDecoration(suffixText: 'g'),
                      validator: _gramsError,
                      onChanged: (_) => setState(() {}),
                    ),
            ),
            IconButton(
              key: const Key('amount-inc'),
              tooltip: 'Artır',
              onPressed: _canStep(1) ? () => _step(1) : null,
              icon: const Icon(Icons.add_circle_outline_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _totals(),
        const OpsFieldLabel('Öğün'),
        OpsChoiceWrap<String>(
          options: [
            for (final type in NutritionLog.mealTypes)
              (type, HealthFormat.mealLabel(type)),
          ],
          selected: _mealType,
          onSelected: (value) => setState(() => _mealType = value),
        ),
      ],
    );
  }
}
