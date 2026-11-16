import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../operations/presentation/operations_widgets.dart';
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

/// Bugünün öğünleri, öğün bazında gruplanmış; kalem ekle / düzenle / sil.
class MealsSection extends ConsumerWidget {
  const MealsSection({super.key});

  Future<void> _delete(BuildContext context, NutritionLog log) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await confirmDelete(
      context,
      title: 'Kayıt silinsin mi?',
      message: '"${log.foodName}" bugünün öğünlerinden kaldırılacak.',
    );
    if (!confirmed) return;
    try {
      await container.read(healthRepositoryProvider).deleteNutritionLog(log.id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text(healthDeleteError)));
      return;
    }
    invalidateHealthData(container);
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
          onAction: () => MealFormSheet.show(context),
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
                      MealFormSheet.show(context, mealType: group.mealType),
                  onEdit: (log) => MealFormSheet.show(context, log: log),
                  onDelete: (log) => _delete(context, log),
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
  });

  final MealGroup group;
  final VoidCallback onAdd;
  final ValueChanged<NutritionLog> onEdit;
  final ValueChanged<NutritionLog> onDelete;

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
          HealthListRow(
            key: ValueKey('meal-${log.id}'),
            title: log.foodName,
            subtitle: _logDetail(log),
            onTap: () => onEdit(log),
            trailing: OpsItemMenu(
              onEdit: () => onEdit(log),
              onDelete: () => onDelete(log),
            ),
          ),
      ],
    );
  }
}
