import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/task_category.dart';

/// Kategori simge anahtarını ikona çevirir.
IconData taskCategoryIcon(String key) => switch (key) {
      'work' => Icons.work_rounded,
      'group' => Icons.groups_rounded,
      'payments' => Icons.payments_rounded,
      'person' => Icons.person_rounded,
      'school' => Icons.school_rounded,
      'sport' => Icons.fitness_center_rounded,
      'home' => Icons.home_rounded,
      'health' => Icons.favorite_rounded,
      'project' => Icons.folder_rounded,
      'shopping' => Icons.shopping_cart_rounded,
      'family' => Icons.family_restroom_rounded,
      'growth' => Icons.self_improvement_rounded,
      'travel' => Icons.flight_rounded,
      'pet' => Icons.pets_rounded,
      'car' => Icons.directions_car_rounded,
      _ => Icons.lightbulb_rounded,
    };

/// Renk anahtarını (AppColors rol adı) etkin paletten okur; her build'de
/// yeniden çağrılır.
Color taskCategoryRoleColor(String key) => switch (key) {
      'ops' => AppColors.ops,
      'accent' => AppColors.accent,
      'fitness' => AppColors.fitness,
      'nutrition' => AppColors.nutrition,
      'warning' => AppColors.warning,
      'danger' => AppColors.danger,
      'textSecondary' => AppColors.textSecondary,
      _ => AppColors.accent,
    };

/// Görevin kategori rengi: tanımlıysa kullanıcının seçtiği rol, değilse
/// (silinmiş kategori) yerleşik eşleme.
Color taskCategoryColor(List<TaskCategory> categories, String name) {
  final def = TaskCategory.find(categories, name);
  return def == null
      ? AppColors.forTaskCategory(name)
      : taskCategoryRoleColor(def.color);
}
