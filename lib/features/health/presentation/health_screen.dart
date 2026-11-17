import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/settings_providers.dart';
import 'activity_cards.dart';
import 'energy_card.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'healthkit_card.dart';
import 'meals_section.dart';
import 'weight_card.dart';
import 'workouts_section.dart';

/// Sağlık sekmesi: kilo, enerji dengesi (dokununca hafta/ay detayı), haftalık
/// antrenman, adım, uyku ve kalori (kartlara dokununca trend ekranı),
/// bugünün öğünleri, antrenman günlüğü ve HealthKit durumu.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _refresh(ProviderContainer container) async {
    invalidateHealthData(container);
    await resyncHealthKit(container);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(settingsOrDefaultProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () =>
            _refresh(ProviderScope.containerOf(context, listen: false)),
        // Bölümler az ve kısa olduğu için tembel liste yerine tek sütun:
        // sekme açılınca tüm kartlar birlikte yüklenir.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Alt bar içeriğin üstüne bindiği için altta pay bırakılır.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            12,
            AppSpacing.page,
            120,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sağlık', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                '${HealthFormat.plain(targets.startWeightKg)} kg → '
                '${HealthFormat.plain(targets.targetWeightKg)} kg, '
                'kas kütlesini koruyarak',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              const BentoGrid(
                children: [
                  BentoCell(child: WeightCard()),
                  BentoCell(child: EnergyCard()),
                  BentoCell(span: 1, child: WorkoutWeekCard()),
                  BentoCell(span: 1, child: StepsWeekCard()),
                  BentoCell(span: 1, child: SleepWeekCard()),
                  BentoCell(span: 1, child: CaloriesWeekCard()),
                ],
              ),
              const MealsSection(),
              const WorkoutsSection(),
              const SizedBox(height: AppSpacing.grid),
              const HealthKitCard(),
            ],
          ),
        ),
      ),
    );
  }
}
