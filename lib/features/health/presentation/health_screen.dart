import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/module_roadmap_view.dart';
import '../../settings/presentation/settings_providers.dart';

class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(settingsOrDefaultProvider);
    final range = '${targets.startWeightKg} kg → ${targets.targetWeightKg} kg';
    return ModuleRoadmapView(
      title: 'Sağlık & Form',
      subtitle: '$range, kas kütlesini koruyarak.',
      icon: Icons.monitor_heart_rounded,
      color: AppColors.fitness,
      items: [
        'Hedef çizgili kilo takip grafiği ($range)',
        'Antrenman günlüğü: ağırlık, kickboks, koşu, halı saha',
        'Öğün ve makro ekleme ekranı',
        'HealthKit senkronizasyon durumu ve geçmişi',
      ],
    );
  }
}
