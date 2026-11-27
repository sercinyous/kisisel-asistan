import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/templates/meal_templates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../settings/presentation/settings_providers.dart';
import 'providers/targets_providers.dart';

/// Öğün türünün Türkçe adı.
String presetMealTypeLabel(String mealType) => switch (mealType) {
      'breakfast' => 'Kahvaltı',
      'lunch' => 'Öğle',
      'dinner' => 'Akşam',
      _ => 'Ara öğün',
    };

/// Sağlık > Plan: hazır diyet paketi. Tek dokunuşla (onaydan sonra) hedefleri
/// paketin kalori ve makrolarına ayarlar; menü öğün formunda şablon olarak
/// da durur. Güvenlik denetimi motordadır ([checkPreset]).
class DietPresetCard extends ConsumerWidget {
  const DietPresetCard({
    super.key,
    this.preset = DietPreset.highProtein1800,
  });

  final DietPreset preset;

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${preset.label} uygulansın mı?'),
        content: Text(
          'Günlük hedeflerin ${preset.kcal} kcal, ${preset.proteinG} g '
          'protein, ${preset.carbsG} g karbonhidrat ve ${preset.fatG} g yağ '
          'olarak ayarlanır. Tartı kaydı bu hedefleri değiştirmez; istediğin '
          'zaman önceki plana dönebilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            key: const Key('preset-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(planControllerProvider);
    try {
      final result = await controller.applyPreset(preset);
      final previous = result.previous;
      if (previous == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(result.check.warning ?? 'Paket uygulanamadı.'),
        ));
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text('Hedeflerin ${preset.label} olarak ayarlandı'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => controller.restorePrevious(previous),
        ),
      ));
    } on Object {
      messenger.showSnackBar(
          const SnackBar(content: Text('Hedefler güncellenemedi.')));
    }
  }

  Future<void> _returnToPlan(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final write = await ref
          .read(planControllerProvider)
          .applyPlan(PlanTrigger.suggestionApplied);
      messenger.showSnackBar(SnackBar(
        content: Text(write?.message ?? 'Önceki plana dönüldü'),
      ));
    } on Object {
      messenger.showSnackBar(
          const SnackBar(content: Text('Hedefler güncellenemedi.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsOrDefaultProvider);
    final check = ref.watch(presetCheckProvider(preset)).valueOrNull;
    final active = presetActive(settings, preset);
    final warning = check?.warning;
    return BentoCard(
      key: const Key('plan-preset'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.restaurant_menu_rounded,
            label: 'Hazır paket',
            color: AppColors.accent,
            trailing: active ? 'Etkin' : null,
            trailingColor: AppColors.accent,
          ),
          const SizedBox(height: 10),
          Text(
            preset.label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Diyet için protein ağırlıklı günlük plan.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              RitimBadge('P ${preset.proteinG} g', color: AppColors.accent),
              RitimBadge('K ${preset.carbsG} g'),
              RitimBadge('Y ${preset.fatG} g'),
              RitimBadge('Lif ~${preset.fiberG} g'),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < preset.meals.length; i++)
            _MenuRow(meal: preset.meals[i], first: i == 0),
          const SizedBox(height: 4),
          Text(
            'Toplam ≈ ${preset.menuKcal.round()} kcal · '
            '${preset.menuProteinG.round()} g protein. Değerler yaklaşıktır; '
            'öğünler öğün ekleme formunda şablon olarak durur.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Text(
              warning,
              key: const Key('preset-warning'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: active
                ? RitimPillButton(
                    key: const Key('preset-return'),
                    label: 'Önceki plana dön',
                    icon: Icons.undo_rounded,
                    ghost: true,
                    onPressed: () => _returnToPlan(context, ref),
                  )
                : RitimPillButton(
                    key: const Key('preset-apply'),
                    label: 'Tek dokunuşla uygula',
                    icon: Icons.check_rounded,
                    onPressed: check == null || !check.allowed
                        ? null
                        : () => _apply(context, ref),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.meal, required this.first});

  final MealTemplate meal;
  final bool first;

  @override
  Widget build(BuildContext context) => RitimListRow(
        title: '${presetMealTypeLabel(meal.mealType)} · ${meal.foodName}',
        subtitle: meal.quantityText,
        value: '${meal.calories.round()} kcal',
        delta: '${meal.proteinG.round()} g P',
        deltaColor: AppColors.accent,
        showDivider: !first,
      );
}
