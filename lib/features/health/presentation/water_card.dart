import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import 'health_widgets.dart';
import 'water_providers.dart';

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String error,
) async {
  final messenger = ScaffoldMessenger.of(context);
  unawaited(HapticFeedback.selectionClick());
  try {
    await action();
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

/// Sağlık: bugünün suyu, hedef, +250 / +500 ve geri al.
class WaterCard extends ConsumerWidget {
  const WaterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final water = ref.watch(waterTodayProvider);
    final notifier = ref.read(waterTodayProvider.notifier);
    final theme = Theme.of(context);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.water_drop_rounded,
            label: 'Su',
            color: AppColors.water,
            trailing: 'bugün',
          ),
          const SizedBox(height: 8),
          water.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 96),
            error: (_, __) => HealthCompactMessage(
              text: 'Su kayıtları yüklenemedi.',
              onRetry: () => ref.invalidate(waterTodayProvider),
            ),
            data: (today) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: HealthBigValue(
                        value: formatWaterMl(today.totalMl),
                        unit: '/ ${formatWaterMl(today.targetMl)}',
                        singleLine: true,
                      ),
                    ),
                    Text(
                      '%${(today.progress * 100).round()}',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _WaterBar(progress: today.progress),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final ml in waterQuickAddMl) ...[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _run(
                            context,
                            () => notifier.add(ml),
                            'Su kaydı eklenemedi.',
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text('$ml ml'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: 'Son kaydı geri al',
                      onPressed: today.canUndo
                          ? () => _run(
                                context,
                                notifier.undo,
                                'Son kayıt geri alınamadı.',
                              )
                          : null,
                      icon: const Icon(Icons.undo_rounded),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kokpit: tek satırlık su özeti ve +250 düğmesi.
class WaterSummaryCard extends ConsumerWidget {
  const WaterSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final water = ref.watch(waterTodayProvider);
    final theme = Theme.of(context);
    final today = water.valueOrNull;

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, size: 18, color: AppColors.water),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  today == null
                      ? (water.hasError ? 'Su yüklenemedi' : 'Su')
                      : 'Su  ${formatWaterMl(today.totalMl)} / '
                          '${formatWaterMl(today.targetMl)}',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                _WaterBar(progress: today?.progress ?? 0, height: 6),
              ],
            ),
          ),
          IconButton(
            tooltip: '250 ml ekle',
            onPressed: today == null
                ? (water.hasError
                    ? () => ref.invalidate(waterTodayProvider)
                    : null)
                : () => _run(
                      context,
                      () => ref
                          .read(waterTodayProvider.notifier)
                          .add(waterQuickAddMl.first),
                      'Su kaydı eklenemedi.',
                    ),
            icon: Icon(
              water.hasError && today == null
                  ? Icons.refresh_rounded
                  : Icons.add_circle_rounded,
            ),
            color: AppColors.water,
          ),
        ],
      ),
    );
  }
}

class _WaterBar extends StatelessWidget {
  const _WaterBar({required this.progress, this.height = 8});

  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: height,
        backgroundColor: AppColors.surfaceHigh,
        color: AppColors.water,
      ),
    );
  }
}
