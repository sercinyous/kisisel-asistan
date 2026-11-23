import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/bento.dart';
import '../meals_section.dart';
import 'day_balance_card.dart';
import 'movement_tiles.dart';
import 'streak_strip.dart';
import 'week_card.dart';

/// Sağlık > Bugün: seriler, günün dengesi, öğünler, hareket ve bu hafta.
class TodayView extends StatelessWidget {
  const TodayView({super.key});

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoGrid(children: [
            BentoCell(child: StreakStrip()),
            BentoCell(child: DayBalanceCard()),
          ]),
          MealsSection(),
          SizedBox(height: AppSpacing.grid),
          MovementTiles(),
          SizedBox(height: AppSpacing.grid),
          BentoGrid(children: [BentoCell(child: WeekCard())]),
        ],
      );
}
