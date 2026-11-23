import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/item_actions.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'food_picker_sheet.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'meal_form_sheet.dart';

const String _deleteTitle = 'Kayıt silinsin mi?';

String _deleteMessage(NutritionLog log) =>
    '"${log.foodName}" bugünün öğünlerinden kaldırılacak.';

/// Bugünün öğünleri, öğün bazında gruplanmış; kalem ekle / düzenle / sil.
class MealsSection extends ConsumerWidget {
  const MealsSection({super.key});

  /// Kaydı siler; başarılıysa `true`. [confirm] doğruysa önce onay sorulur
  /// (üç nokta menüsü); uzun basış ve kaydırma onayı kendisi sorar.
  Future<bool> _delete(
    BuildContext context,
    NutritionLog log, {
    bool confirm = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    if (confirm) {
      final confirmed = await confirmDelete(
        context,
        title: _deleteTitle,
        message: _deleteMessage(log),
      );
      if (!confirmed) return false;
    }
    try {
      await container.read(healthRepositoryProvider).deleteNutritionLog(log.id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text(healthDeleteError)));
      return false;
    }
    invalidateHealthData(container);
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = AppDates.startOfDay(DateTime.now());
    final logs = ref.watch(dayNutritionLogsProvider(today));

    final count = logs.valueOrNull?.map((l) => l.mealType).toSet().length;
    return BentoCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: BentoLabel(
              label: 'Öğünler',
              trailing: count == null ? null : '$count öğün',
            ),
          ),
          const SizedBox(height: 4),
          logs.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 120),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: KokpitInlineMessage(
                icon: Icons.cloud_off_outlined,
                message: 'Öğünler yüklenemedi.',
                actionLabel: 'Tekrar dene',
                onAction: () => ref.invalidate(dayNutritionLogsProvider),
              ),
            ),
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, group) in groupMeals(items).indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 12,
                      endIndent: 12,
                      color: AppColors.border,
                    ),
                  _MealGroupTile(
                    group: group,
                    onAdd: () =>
                        FoodPickerSheet.show(context, mealType: group.mealType),
                    onEdit: (log) => MealFormSheet.show(context, log: log),
                    onDelete: (log) => _delete(context, log, confirm: true),
                    onRemove: (log) => _delete(context, log),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                key: const Key('meal-add'),
                constraints: const BoxConstraints(
                  minHeight: healthMinTouch,
                  minWidth: healthMinTouch,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: RitimPillButton(
                    label: 'Öğün ekle',
                    icon: Icons.add_outlined,
                    ghost: true,
                    onPressed: () => FoodPickerSheet.show(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Öğün grubu: kapalıyken tek satır ("Kahvaltı · 420 kcal"); dokununca
/// kalemler açılır. Boş öğüne dokunmak o öğüne kalem ekler.
class _MealGroupTile extends StatefulWidget {
  const _MealGroupTile({
    required this.group,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRemove,
  });

  final MealGroup group;
  final VoidCallback onAdd;
  final ValueChanged<NutritionLog> onEdit;

  /// Üç nokta menüsü: önce onay sorar, sonra siler.
  final ValueChanged<NutritionLog> onDelete;

  /// Uzun basış ve kaydırma: onayı satır bileşeni sorar; silindiyse `true`.
  final Future<bool> Function(NutritionLog log) onRemove;

  String _logDetail(NutritionLog log) {
    final quantity = log.quantityText?.trim() ?? '';
    return [
      if (quantity.isNotEmpty) quantity,
      HealthFormat.kcal(log.calories),
      'P ${HealthFormat.grams(log.proteinG)}',
    ].join(' · ');
  }

  @override
  State<_MealGroupTile> createState() => _MealGroupTileState();
}

class _MealGroupTileState extends State<_MealGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final onRemove = widget.onRemove;
    final empty = group.logs.isEmpty;
    final label = HealthFormat.mealLabel(group.mealType);
    final expanded = _expanded && !empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthListRow(
          key: ValueKey('meal-group-${group.mealType}'),
          title:
              empty ? label : '$label · ${HealthFormat.kcal(group.calories)}',
          subtitle: empty
              ? 'Henüz kayıt yok'
              : '${group.logs.length} kalem · '
                  'P ${HealthFormat.grams(group.proteinG)}',
          onTap: empty
              ? widget.onAdd
              : () => setState(() => _expanded = !_expanded),
          trailing: empty
              ? IconButton(
                  tooltip: '$label ekle',
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add_outlined),
                  color: AppColors.nutrition,
                )
              : IconButton(
                  tooltip: expanded ? 'Öğünü daralt' : 'Öğünü genişlet',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    expanded
                        ? Icons.expand_less_outlined
                        : Icons.expand_more_outlined,
                  ),
                  color: AppColors.textSecondary,
                ),
        ),
        if (expanded)
          for (final log in group.logs)
            ItemRowActions(
              key: ValueKey('meal-actions-${log.id}'),
              itemKey: ValueKey('swipe-meal-${log.id}'),
              title: log.foodName,
              confirmTitle: _deleteTitle,
              confirmMessage: _deleteMessage(log),
              onEdit: () => onEdit(log),
              onDelete: () => onRemove(log),
              child: HealthListRow(
                key: ValueKey('meal-${log.id}'),
                title: log.foodName,
                subtitle: widget._logDetail(log),
                onTap: () => onEdit(log),
                trailing: OpsItemMenu(
                  onEdit: () => onEdit(log),
                  onDelete: () => onDelete(log),
                ),
              ),
            ),
        if (expanded)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: widget.onAdd,
                style: TextButton.styleFrom(
                  minimumSize: const Size(healthMinTouch, healthMinTouch),
                  foregroundColor: AppColors.nutrition,
                ),
                icon: const Icon(Icons.add_outlined, size: 18),
                label: Text('$label için kalem ekle'),
              ),
            ),
          ),
      ],
    );
  }
}
