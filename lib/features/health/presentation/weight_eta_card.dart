import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/weight_eta.dart';
import 'health_widgets.dart';
import 'health_providers.dart';

/// Kilo bölümü: son 8 haftanın eğilimine göre hedefe tahmini varış.
class WeightEtaCard extends ConsumerWidget {
  const WeightEtaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(weightSeriesProvider(weightEtaWindowDays));
    final targetKg = ref.watch(settingsOrDefaultProvider).targetWeightKg;
    final theme = Theme.of(context);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.flag_outlined,
            label: 'Hedefe tahmini varış',
            color: AppColors.accent,
            trailing: 'son 8 hafta',
          ),
          const SizedBox(height: 8),
          series.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 40),
            error: (_, __) => HealthCompactMessage(
              text: 'Tahmin hesaplanamadı.',
              onRetry: () => ref.invalidate(weightSeriesProvider),
            ),
            data: (entries) {
              final now = DateTime.now();
              final eta = estimateWeightEta(
                entries,
                targetKg: targetKg,
                now: now,
              );
              final slope = eta.slopeKgPerWeek;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    weightEtaMessage(eta, targetKg: targetKg, now: now),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: eta.status == WeightEtaStatus.notTowards
                          ? AppColors.warning
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (slope != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Eğilim: haftada '
                      '${slope >= 0 ? '+' : '−'}'
                      '${slope.abs().toStringAsFixed(2).replaceAll('.', ',')} kg',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
