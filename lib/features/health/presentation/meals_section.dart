import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/item_actions.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'food_picker_sheet.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'meal_form_sheet.dart';

IconData _mealIcon(String mealType) => switch (mealType) {
      'breakfast' => Icons.wb_sunny_rounded,
      'lunch' => Icons.light_mode_outlined,
      'dinner' => Icons.nightlight_round,
      _ => Icons.cookie_outlined,
    };

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthSectionHeader(
          title: 'Bugünün öğünleri',
          actionLabel: 'Öğün ekle',
          onAction: () => FoodPickerSheet.show(context),
        ),
        logs.when(
          skipLoadingOnRefresh: true,
          loading: () => const KokpitSkeletonCard(height: 168),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Öğünler yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(dayNutritionLogsProvider),
          ),
          data: (items) => HealthListCard(
            children: [
              for (final group in groupMeals(items))
                _MealGroupTile(
                  group: group,
                  onAdd: () =>
                      FoodPickerSheet.show(context, mealType: group.mealType),
                  onEdit: (log) => MealFormSheet.show(context, log: log),
                  onDelete: (log) => _delete(context, log, confirm: true),
                  onRemove: (log) => _delete(context, log),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MealGroupTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final empty = group.logs.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthListRow(
          icon: _mealIcon(group.mealType),
          color: AppColors.nutrition,
          title: HealthFormat.mealLabel(group.mealType),
          subtitle: empty
              ? 'Henüz kayıt yok'
              : '${group.logs.length} kalem · '
                  'P ${HealthFormat.grams(group.proteinG)}',
          value: empty ? '—' : HealthFormat.kcal(group.calories),
          valueMuted: empty,
          // Öğün satırına dokunmak o öğüne kalem ekler.
          onTap: onAdd,
        ),
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
              subtitle: _logDetail(log),
              onTap: () => onEdit(log),
              trailing: OpsItemMenu(
                onEdit: () => onEdit(log),
                onDelete: () => onDelete(log),
              ),
            ),
          ),
      ],
    );
  }
}
