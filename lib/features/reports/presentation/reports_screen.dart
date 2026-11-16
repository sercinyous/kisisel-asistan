import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/module_roadmap_view.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModuleRoadmapView(
      title: 'Raporlar & Analiz',
      subtitle: 'Son 7 günün iş ve form özeti.',
      icon: Icons.insights_rounded,
      color: AppColors.accent,
      items: [
        'Görev tamamlama oranı ile spor/beslenme istikrarı yan yana grafikler',
        'Haftalık rapor kaydı (weekly_reports)',
        'Gemini ile üretilen haftalık değerlendirme kartı',
      ],
    );
  }
}
