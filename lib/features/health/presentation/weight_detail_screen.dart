import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'weight_card.dart';
import 'weight_eta_card.dart';

/// Kilo ayrıntısı: 30/90 gün grafiği, ölçümler, kilo ekle ve hedefe tahmini
/// varış.
class WeightDetailScreen extends StatelessWidget {
  const WeightDetailScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const WeightDetailScreen()),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kilo')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          8,
          AppSpacing.page,
          120,
        ),
        child: BentoGrid(
          children: [
            BentoCell(child: WeightHistoryCard()),
            BentoCell(child: WeightEtaCard()),
          ],
        ),
      ),
    );
  }
}
