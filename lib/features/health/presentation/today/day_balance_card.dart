import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import '../../../kokpit/presentation/kokpit_providers.dart';
import '../fat_loss_providers.dart' show todayMealGapProvider;
import '../health_format.dart';
import '../health_widgets.dart';
import '../providers/streaks_providers.dart';
import '../providers/targets_providers.dart';
import '../providers/water_providers.dart';
import '../providers/week_deficit_providers.dart';
import '../trend_providers.dart' show trendClockProvider;
import '../weekly_detail_screen.dart';
import 'today_common.dart';

/// Su satırında bir bardak (ml).
const int waterGlassMl = 250;

/// Bugünün kalori açığı (şu ana kadar); hesaplanamıyorsa `null`.
final todayDeficitProvider = FutureProvider<double?>((ref) async {
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  final health =
      await ref.watch(healthDaysProvider((from: today, to: today)).future);
  return health.days.isEmpty ? null : health.days.last.deficit;
});

/// Günün dengesi: kalori halkası (alınan/hedef/kalan), protein, şu ana kadarki
/// açık, eksik satırı (en çok 2 kalem) ve su. Dokununca Haftalık detay açılır.
class DayBalanceCard extends ConsumerWidget {
  const DayBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrition = ref.watch(todayNutritionProvider);
    final targets = ref.watch(targetsProvider);
    final lowIntake =
        ref.watch(streaksProvider).valueOrNull?.lowIntake ?? false;

    return BentoCard(
      key: const Key('day-balance-card'),
      onTap: () => WeeklyDetailScreen.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(label: 'Günün dengesi', trailing: '›'),
          if (lowIntake) ...[
            const SizedBox(height: 10),
            const _Notice(
              key: Key('day-low-intake'),
              text: '${SafeTargets.lowIntakeWarning}. Kalori tabanının altında '
                  'kalmak kas kaybı riskini artırabilir; bugün hedefe yaklaşmaya çalış.',
            ),
          ],
          const SizedBox(height: 8),
          nutrition.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 120),
            error: (_, __) => HealthCompactMessage(
              text: 'Günün özeti yüklenemedi.',
              onRetry: () => ref.invalidate(todayNutritionProvider),
            ),
            data: (day) => _Balance(
              eaten: day.calories,
              protein: day.proteinG,
              logged: day.entryCount > 0,
              targets: targets,
            ),
          ),
          const _GapLine(),
          const SizedBox(height: 10),
          const WaterRow(),
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.eaten,
    required this.protein,
    required this.logged,
    required this.targets,
  });

  final double eaten;
  final double protein;
  final bool logged;
  final DailyTargets targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targets.kcal;
    final left = target - eaten;
    final progress = target <= 0 ? 0.0 : eaten / target;
    final over = left < 0;
    final proteinTarget = targets.proteinG;
    final sub = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          key: const Key('day-left'),
          label: over
              ? 'Hedefin ${HealthFormat.count(-left)} kcal üstünde'
              : 'Kalan ${HealthFormat.count(left)} kcal',
          excludeSemantics: true,
          child: KcalRing(
            progress: progress,
            color: AppColors.nutrition,
            center: HealthFormat.count(left.abs()),
            caption: over ? 'fazla' : 'kalan',
            size: 84,
            stroke: 8,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alınan ${HealthFormat.count(eaten)} · '
                'Hedef ${HealthFormat.count(target)} kcal',
                key: const Key('day-eaten'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sub,
              ),
              const SizedBox(height: 4),
              Text(
                'Protein ${HealthFormat.count(protein)} / '
                '${HealthFormat.count(proteinTarget)} g',
                key: const Key('day-protein'),
                style: sub,
              ),
              const SizedBox(height: 6),
              SlimBar(
                progress: proteinTarget <= 0 ? 0 : protein / proteinTarget,
                color: AppColors.protein,
              ),
              if (!logged) ...[
                const SizedBox(height: 8),
                Text(
                  'Henüz öğün girilmedi.',
                  key: const Key('day-empty'),
                  style: sub,
                ),
              ],
              const DayDeficitLine(),
            ],
          ),
        ),
      ],
    );
  }
}

class DayDeficitLine extends ConsumerWidget {
  const DayDeficitLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deficit = ref.watch(todayDeficitProvider).valueOrNull;
    if (deficit == null) return const SizedBox.shrink();
    // Kas yapmada fazla hedefin kendisidir: uyarı rengi yalnızca açıkla
    // çalışan hedeflerde.
    final surplusGoal = ref.watch(resolvedTargetsProvider).valueOrNull?.mode ==
        TargetsMode.gain;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: deficit >= 0
                  ? 'Kalori açığı (şu ana kadar): '
                  : 'Kalori fazlası (şu ana kadar): ',
              children: [
                TextSpan(
                  text: TodayFormat.deficit(deficit),
                  style: TextStyle(
                    color: deficit >= 0
                        ? AppColors.accent
                        : surplusGoal
                            ? AppColors.textPrimary
                            : AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            key: const Key('day-deficit'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          Text(
            'Gün bitmeden kesinleşmez',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Eksik satırı: hedeflere göre en önemli en çok 2 sapma; öğün yokken gizli.
class _GapLine extends ConsumerWidget {
  const _GapLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(todayMealGapProvider).valueOrNull;
    if (report == null || report.nothingLogged) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        report.allDone ? '✓ ${report.summary}' : report.summary,
        key: const Key('day-gap-line'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: report.allDone ? AppColors.positive : AppColors.warning,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Su satırı: bardak noktaları ve −/+ (250 ml). Kokpit ile aynı
/// [waterProvider]'ı paylaşır.
class WaterRow extends ConsumerWidget {
  const WaterRow({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final water = ref.watch(waterProvider);
    return water.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox(height: 44),
      error: (_, __) => HealthCompactMessage(
        text: 'Su kayıtları yüklenemedi.',
        onRetry: () => ref.invalidate(waterProvider),
      ),
      data: (today) {
        // Hedef ayardan gelir; kiloya göre öneri Plan > Rehber'de uygulanır.
        final target =
            today.targetMl > 0 ? today.targetMl : defaultDailyWaterMl;
        final glasses =
            math.max(1, math.min(12, (target / waterGlassMl).ceil()));
        final filled = (today.totalMl / waterGlassMl).floor();
        final notifier = ref.read(waterProvider.notifier);
        return Row(
          children: [
            Expanded(
              child: Semantics(
                label: 'Su ${formatWaterMl(today.totalMl)} / '
                    '${formatWaterMl(target)}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Text(
                      'Su',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < glasses; i++)
                            SizedBox(
                              width: 9,
                              height: 9,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      i < filled ? AppColors.textPrimary : null,
                                  border: i < filled
                                      ? null
                                      : Border.all(
                                          color: AppColors.textMuted,
                                          width: 1.2,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatWaterMl(today.totalMl)} / '
                      '${formatWaterMl(target)}',
                      key: const Key('day-water'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              key: const Key('day-water-minus'),
              tooltip: 'Son su kaydını geri al',
              onPressed: today.canUndo
                  ? () =>
                      _run(context, notifier.undo, 'Son kayıt geri alınamadı.')
                  : null,
              icon: const Icon(Icons.remove_outlined, size: 16),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.selection,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor: AppColors.selection,
                fixedSize: const Size.square(30),
                minimumSize: const Size.square(30),
              ),
            ),
            IconButton.filledTonal(
              key: const Key('day-water-plus'),
              tooltip: '$waterGlassMl ml su ekle',
              onPressed: () => _run(context, () => notifier.add(waterGlassMl),
                  'Su kaydı eklenemedi.'),
              icon: const Icon(Icons.add_outlined, size: 16),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                fixedSize: const Size.square(30),
                minimumSize: const Size.square(30),
              ),
            ),
          ],
        );
      },
    );
  }
}
