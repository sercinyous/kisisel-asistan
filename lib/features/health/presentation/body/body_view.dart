import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../domain/weight_eta.dart';
import '../health_format.dart';
import '../health_providers.dart';
import '../health_widgets.dart';
import '../providers/body_providers.dart';
import '../weight_detail_screen.dart';
import '../weight_sheets.dart';
import 'body_format.dart';
import 'checkin_flow.dart';
import 'measurement_form_sheet.dart';
import 'measurements_screen.dart';
import 'photo_thumb.dart';
import 'photos_screen.dart';

/// Sağlık > Vücut bölümü: kontrol günü, kilo, ölçüler, fotoğraflar.
/// Kendisi kaydırmaz; sağlık ekranının listesine yerleşir (alt boşluk orada).
class BodyView extends ConsumerWidget {
  const BodyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckinBanner(),
        SizedBox(height: AppSpacing.grid),
        BodyWeightCard(),
        SizedBox(height: AppSpacing.grid),
        BodyMeasurementsCard(),
        SizedBox(height: AppSpacing.grid),
        BodyPhotosCard(),
      ],
    );
  }
}

/// Ölçü günü banner'ı ya da (başka gün) ince "Sonraki ölçü günü" satırı.
class CheckinBanner extends ConsumerWidget {
  const CheckinBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = AppDates.startOfDay(DateTime.now());
    final dismissed = ref.watch(checkinDismissedProvider) == today;
    final state = ref.watch(checkinTodayProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    if (state.showBanner && !dismissed) {
      return BentoCard(
        key: const Key('checkin-banner'),
        gradient: [AppColors.accent, AppColors.sleep],
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.cardPadding, AppSpacing.m, AppSpacing.s, AppSpacing.m),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.straighten_outlined, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bugün ölçü ve fotoğraf günü',
                      style: theme.textTheme.titleSmall),
                  Text(
                    '3 adım, ~3 dk',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            FilledButton(
              key: const Key('checkin-start'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: TextStyle(
                  fontSize: AppType.chip,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => CheckinFlowScreen.open(context),
              child: const Text('Başla'),
            ),
            IconButton(
              key: const Key('checkin-dismiss'),
              tooltip: 'Bugün gösterme',
              onPressed: () =>
                  ref.read(checkinDismissedProvider.notifier).dismiss(today),
              icon: Icon(Icons.close_outlined,
                  size: 18, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final text = state.isCheckinDay && state.done
        ? 'Bugünün ölçüsü tamam'
        : state.scheduleLine;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        key: const Key('checkin-schedule'),
        children: [
          Icon(
            state.isCheckinDay && state.done
                ? Icons.check_circle_outline_outlined
                : Icons.event_repeat_outlined,
            size: 16,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kart başlığı + sağda tek eylem.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            title,
            style:
                Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            key: actionKey,
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(healthMinTouch, healthMinTouch),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// "Hedefe ~9 hafta" (tek ETA fonksiyonundan).
String? weeksToTargetText(WeightEta eta, DateTime now) {
  switch (eta.status) {
    case WeightEtaStatus.onTrack:
      final days = eta.eta!.difference(AppDates.startOfDay(now)).inDays;
      final weeks = (days / 7).ceil();
      return weeks <= 1 ? 'Hedefe ~1 hafta' : 'Hedefe ~$weeks hafta';
    case WeightEtaStatus.reached:
      return 'Hedefe ulaşıldı';
    case WeightEtaStatus.notTowards:
      return 'Trend hedefe doğru değil';
    case WeightEtaStatus.insufficient:
      return null;
  }
}

/// Son kilodan 7 gün önceki (ya da daha eski en yakın) ölçüme fark.
double? weekChangeKg(List<WeightEntry> series) {
  if (series.length < 2) return null;
  final latest = series.last;
  final cutoff = latest.loggedAt.subtract(const Duration(days: 7));
  WeightEntry? base;
  for (final e in series) {
    if (!e.loggedAt.isAfter(cutoff)) base = e;
  }
  base ??= series.first;
  if (identical(base, latest)) return null;
  return roundCm(latest.weightKg - base.weightKg);
}

/// Vücut > Kilo: son kilo, 7 günlük fark, 30 günlük çizgi, hedefe varış.
class BodyWeightCard extends ConsumerWidget {
  const BodyWeightCard({super.key});

  static const int _window = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final series = ref.watch(weightSeriesProvider(_window));
    final etaSeries =
        ref.watch(weightSeriesProvider(weightEtaWindowDays)).valueOrNull;
    final target = ref.watch(settingsOrDefaultProvider).targetWeightKg;

    return BentoCard(
      key: const Key('body-weight-card'),
      onTap: () => WeightDetailScreen.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.monitor_weight_outlined,
            title: 'Kilo',
            color: AppColors.accent,
            actionKey: const Key('body-weigh'),
            actionLabel: '+ Tartıl',
            onAction: () => WeightFormSheet.show(context),
          ),
          series.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 96),
            error: (_, __) => HealthCompactMessage(
              text: 'Kilo ölçümleri yüklenemedi.',
              onRetry: () => ref.invalidate(weightSeriesProvider),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Text(
                  'Son $_window günde tartı yok.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                );
              }
              final now = DateTime.now();
              final change = weekChangeKg(entries);
              final eta = etaSeries == null
                  ? null
                  : weeksToTargetText(
                      weightEta(etaSeries, targetKg: target, now: now), now);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HealthBigValue(
                        key: const Key('body-weight-latest'),
                        value: HealthFormat.kg(entries.last.weightKg),
                        unit: 'kg',
                        large: true,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          if (change != null)
                            '${BodyFormat.delta(change)} kg · 7 gün',
                          if (eta != null) eta,
                        ].join('\n'),
                        key: const Key('body-weight-summary'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: IgnorePointer(
                      child: SizedBox(
                        height: 64,
                        child: _Sparkline(entries: entries),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.length < 2) return const SizedBox.shrink();
    final origin = entries.first.loggedAt;
    final spots = [
      for (final e in entries)
        FlSpot(e.loggedAt.difference(origin).inHours / 24, e.weightKg),
    ];
    final ys = entries.map((e) => e.weightKg);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.2).clamp(0.2, 5.0);
    final color = AppColors.accent;
    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            dotData: FlDotData(
              checkToShowDot: (spot, _) => spot == spots.last,
              getDotPainter: (_, __, ___, ____) =>
                  FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

/// Vücut > Ölçüler: alan başına son değer ve farklar.
class BodyMeasurementsCard extends ConsumerWidget {
  const BodyMeasurementsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(measurementSummaryProvider);
    return BentoCard(
      key: const Key('body-measurements-card'),
      onTap: () => MeasurementsScreen.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.straighten_outlined,
            title: 'Ölçüler',
            color: AppColors.ops,
            actionKey: const Key('body-measure'),
            actionLabel: '+ Ölç',
            onAction: () => MeasurementFormSheet.show(context),
          ),
          summary.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 96),
            error: (_, __) => HealthCompactMessage(
              text: 'Ölçüler yüklenemedi.',
              onRetry: () => ref.invalidate(measurementsProvider),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return _EmptyCta(
                  text: 'Henüz ölçüm yok.',
                  action: 'İlk ölçümü ekle',
                  onAction: () => MeasurementFormSheet.show(context),
                );
              }
              return Column(
                children: [
                  for (final (i, s) in rows.indexed)
                    _MeasurementRow(
                      divider: i < rows.length - 1,
                      summary: s,
                      onTap: () =>
                          MeasurementsScreen.open(context, field: s.field),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.summary,
    required this.onTap,
    this.divider = true,
  });

  final BodyFieldSummary summary;

  /// Satırın altına 1 px kart çizgisi çizilir (son satır hariç).
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final tabular = const [FontFeature.tabularFigures()];
    return Semantics(
      label: BodyFormat.summaryLine(s),
      button: true,
      excludeSemantics: true,
      child: InkWell(
        key: Key('body-field-${s.field.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: AppColors.border))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(s.field.label, style: theme.textTheme.bodyMedium),
              ),
              Text(
                '${BodyFormat.cm(s.last)} cm',
                style:
                    theme.textTheme.titleSmall?.copyWith(fontFeatures: tabular),
              ),
              const Spacer(),
              if (s.fromStart != null)
                Text(
                  '${BodyFormat.delta(s.fromStart!)} başlangıçtan',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: bodyDeltaColor(s.field, s.fromStart),
                    fontFeatures: tabular,
                  ),
                ),
              if (s.fromPrevious != null) ...[
                const SizedBox(width: AppSpacing.s),
                Text(
                  '${BodyFormat.delta(s.fromPrevious!)} geçen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Vücut > Fotoğraflar: son kontrol gününün küçük resimleri.
class BodyPhotosCard extends ConsumerWidget {
  const BodyPhotosCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final checkins = ref.watch(photoCheckinsProvider);
    final hidden = ref.watch(settingsOrDefaultProvider).hidePhotos;
    final supported = ref.watch(bodyRepositoryProvider).photosSupported;
    return BentoCard(
      key: const Key('body-photos-card'),
      onTap: () => PhotosScreen.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.photo_camera_outlined,
            title: 'Fotoğraflar',
            color: AppColors.sleep,
            actionKey: const Key('body-compare'),
            actionLabel:
                (checkins.valueOrNull?.length ?? 0) >= 2 ? 'Karşılaştır' : null,
            onAction: () => PhotosScreen.open(context, compare: true),
          ),
          checkins.when(
            skipLoadingOnRefresh: true,
            loading: () => const HealthCardLoading(height: 120),
            error: (_, __) => HealthCompactMessage(
              text: 'Fotoğraflar yüklenemedi.',
              onRetry: () => ref.invalidate(progressPhotosProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return supported
                    ? _EmptyCta(
                        text: 'Henüz fotoğraf yok.',
                        action: 'İlk fotoğrafı çek',
                        onAction: () => CheckinFlowScreen.open(context),
                      )
                    : Text(
                        'Henüz fotoğraf yok. Fotoğraflar iPhone '
                        'uygulamasında çekilir.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      );
              }
              final last = list.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BodyFormat.longDate(last.date),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  BodyPoseRow(
                    photos: last.photos,
                    blurred: hidden,
                    onPhotoTap: (_) => PhotosScreen.open(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyCta extends StatelessWidget {
  const _EmptyCta({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: onAction,
          child: Text(action),
        ),
      ],
    );
  }
}
