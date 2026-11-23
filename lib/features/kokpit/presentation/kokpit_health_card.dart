import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../health/presentation/health_segment.dart';
import '../../health/presentation/providers/streaks_providers.dart';
import '../../health/presentation/providers/targets_providers.dart';
import '../../health/presentation/providers/water_providers.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Alt bardaki Sağlık sekmesinin sırası (bkz. `HomeShell`).
const int kokpitHealthTab = 2;

/// Başka bir sekmeden ya da ekrandan Sağlık'ın belirli görünümüne tek giriş
/// noktası (Kokpit, İçgörü, Ayarlar). Açık alt sayfalar kapatılır; Sağlık
/// sekmesine geçilip [segment] seçilir.
void openHealth(BuildContext context, WidgetRef ref, HealthSegment segment) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  ref.read(healthSegmentProvider.notifier).state = segment;
  ref.read(homeTabRequestProvider.notifier).state = kokpitHealthTab;
}

/// Kokpit'ten Sağlık > Bugün (kart, satır, su).
void openHealthToday(WidgetRef ref) {
  ref.read(healthSegmentProvider.notifier).state = HealthSegment.today;
  ref.read(homeTabRequestProvider.notifier).state = kokpitHealthTab;
}

// ------------------------------------------------------------------ halka

/// Kalan kaloriyi gösteren mini halka. [value] 0..1 dışına taşarsa
/// (hedef aşıldı) halka dolu ve [overColor] ile çizilir.
class KokpitRing extends StatelessWidget {
  const KokpitRing({
    super.key,
    required this.value,
    required this.color,
    required this.overColor,
    required this.child,
    this.size = 78,
    this.stroke = 8,
  });

  final double value;
  final Color color;
  final Color overColor;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final over = value > 1;
    final target = value.isNaN ? 0.0 : value.clamp(0, 1).toDouble();
    final track = AppColors.surfaceHigh;
    final arc = over ? overColor : color;
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (_, animated, inner) => CustomPaint(
          painter: _RingPainter(
            value: animated,
            stroke: stroke,
            track: track,
            color: arc,
          ),
          child: inner,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.color,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

// ------------------------------------------------------------ sağlık kartı

/// Kokpit'in tek Sağlık kartı: kalan kalori halkası, adım çubuğu ve seri
/// satırı. Dokununca Sağlık > Bugün açılır.
class KokpitHealthCard extends ConsumerWidget {
  const KokpitHealthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrition = ref.watch(todayNutritionProvider);
    return nutrition.when(
      skipLoadingOnRefresh: true,
      loading: () => const KokpitSkeletonCard(height: 168),
      error: (_, __) => KokpitInlineMessage(
        icon: Icons.cloud_off_outlined,
        message: 'Beslenme özeti yüklenemedi.',
        actionLabel: 'Tekrar dene',
        onAction: () => ref.invalidate(todayNutritionProvider),
      ),
      data: (summary) => _HealthCardBody(eatenKcal: summary.calories),
    );
  }
}

class _HealthCardBody extends ConsumerWidget {
  const _HealthCardBody({required this.eatenKcal});

  final double eatenKcal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(targetsProvider);
    final health = ref.watch(healthTodayProvider).valueOrNull;
    final steps = health?.status == HealthStatus.ok ? health!.steps : null;
    final streaks = ref.watch(streaksProvider).valueOrNull;
    final thousands = KokpitFormat.thousands;

    final target = targets.kcal;
    final eaten = eatenKcal.round();
    final remaining = target - eaten;
    final over = remaining < 0;
    final ratio = target > 0 ? eaten / target : 0.0;
    final streakLine =
        streaks == null || streaks.streaks.isEmpty ? null : streaks.line;

    final headline = over
        ? '${thousands.format(remaining.abs())} kcal fazla'
        : 'Kalan ${thousands.format(remaining)} kcal';
    final semantics = [
      'Sağlık',
      headline,
      '${thousands.format(eaten)} / ${thousands.format(target)} kcal',
      if (steps != null)
        '${thousands.format(steps)} / ${thousands.format(targets.steps)} adım',
      if (streakLine != null) 'Seriler: $streakLine',
    ].join(', ');

    return BentoCard(
      key: const ValueKey('kokpit-health-card'),
      onTap: () {
        unawaited(HapticFeedback.selectionClick());
        openHealthToday(ref);
      },
      // Uzun basış Plan'ı açar (hedef, tempo, rehber).
      onLongPress: () {
        unawaited(HapticFeedback.mediumImpact());
        openHealth(context, ref, HealthSegment.plan);
      },
      child: Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BentoLabel(label: 'Sağlık', trailing: 'Detay ›'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                KokpitRing(
                  value: ratio,
                  color: AppColors.nutrition,
                  overColor: AppColors.danger,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          thousands.format(remaining.abs()),
                          style: TextStyle(
                            fontSize: AppType.value,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color:
                                over ? AppColors.danger : AppColors.textPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        over ? 'fazla' : 'kalan',
                        style: TextStyle(
                          fontSize: AppType.micro,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.section),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.value,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color:
                              over ? AppColors.negative : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${thousands.format(eaten)} / '
                        '${thousands.format(target)} kcal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.body,
                          height: 1.3,
                          color: AppColors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      _StepsLine(steps: steps, target: targets.steps),
                    ],
                  ),
                ),
              ],
            ),
            if (streakLine != null) ...[
              const SizedBox(height: AppSpacing.md),
              _StreakLine(line: streakLine),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepsLine extends StatelessWidget {
  const _StepsLine({required this.steps, required this.target});

  final int? steps;
  final int target;

  @override
  Widget build(BuildContext context) {
    final thousands = KokpitFormat.thousands;
    final value = steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? 'Adım verisi yok'
                    : '${thousands.format(value)} / '
                        '${thousands.format(target)} adım',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.caption,
                  height: 1.3,
                  color: AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        KokpitBar(
          value: value == null || target <= 0 ? 0 : value / target,
          color: AppColors.protein,
          height: 4,
        ),
      ],
    );
  }
}

class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.selection,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(
        children: [
          Text(
            'Seriler',
            style: TextStyle(
              fontSize: AppType.chip,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              line,
              key: const ValueKey('kokpit-streak-line'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.chipValue,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- su

/// "0,25" — litre, en fazla iki ondalık, birimsiz.
String kokpitLiters(int ml) {
  final liters = ml / 1000;
  if (liters == liters.roundToDouble()) return liters.toStringAsFixed(0);
  return liters
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceAll('.', ',');
}

/// Kokpit'in küçük su kutusu (`WaterTracker` kompakt): Sağlık ile aynı
/// [waterProvider] durumunu paylaşır.
class KokpitWaterTile extends ConsumerWidget {
  const KokpitWaterTile({super.key});

  static const int stepMl = 250;

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
    final water = ref.watch(waterProvider);
    final today = water.valueOrNull;
    final notifier = ref.read(waterProvider.notifier);
    final failed = today == null && water.hasError;

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BentoLabel(label: 'Su'),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              today == null
                  ? (failed ? 'Yüklenemedi' : '—')
                  : '${kokpitLiters(today.totalMl)} / '
                      '${kokpitLiters(today.targetMl)} L',
              maxLines: 1,
              style: TextStyle(
                fontSize: AppType.value,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.s),
          if (failed)
            TextButton(
              onPressed: () => ref.invalidate(waterProvider),
              child: const Text('Tekrar dene'),
            )
          else
            Row(
              children: [
                SizedBox.square(
                  dimension: 30,
                  child: IconButton.outlined(
                    tooltip: 'Son su kaydını geri al',
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    onPressed: today == null || today.logs.isEmpty
                        ? null
                        : () => _run(
                              context,
                              notifier.undo,
                              'Su kaydı geri alınamadı.',
                            ),
                    icon: const Icon(Icons.remove_outlined),
                    color: AppColors.textPrimary,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.selection,
                      side: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: today == null
                        ? null
                        : () => _run(
                              context,
                              () => notifier.add(stepMl),
                              'Su kaydı eklenemedi.',
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccent,
                      minimumSize: const Size(0, 30),
                      textStyle: const TextStyle(
                        fontSize: AppType.chip,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: const StadiumBorder(),
                    ),
                    child: const FittedBox(child: Text('+ 250 ml')),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
