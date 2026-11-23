import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/task_category.dart';

/// Kategori simge anahtarını ikona çevirir.
IconData taskCategoryIcon(String key) => switch (key) {
      'work' => Icons.work_outlined,
      'group' => Icons.groups_outlined,
      'payments' => Icons.payments_outlined,
      'person' => Icons.person_outlined,
      'school' => Icons.school_outlined,
      'sport' => Icons.fitness_center_outlined,
      'home' => Icons.home_outlined,
      'health' => Icons.favorite_rounded,
      'project' => Icons.folder_outlined,
      'shopping' => Icons.shopping_cart_outlined,
      'family' => Icons.family_restroom_outlined,
      'growth' => Icons.self_improvement_outlined,
      'travel' => Icons.flight_outlined,
      'pet' => Icons.pets_outlined,
      'car' => Icons.directions_car_outlined,
      _ => Icons.lightbulb_outlined,
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
