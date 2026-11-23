import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/bento.dart';
import '../health_format.dart';
import '../health_providers.dart';
import '../providers/body_providers.dart';
import 'body_format.dart';
import 'photo_thumb.dart';

/// Karşılaştırmada kilo için bakılan pencere (gün).
const int compareWeightWindowDays = 730;

/// İki kontrol günü yan yana, tek poz: altında tarih, kilo (±3 gün en
/// yakın) ve bel.
class CompareView extends ConsumerStatefulWidget {
  const CompareView({
    super.key,
    required this.checkins,
    required this.blurred,
  });

  /// Yeniden eskiye.
  final List<PhotoCheckin> checkins;
  final bool blurred;

  @override
  ConsumerState<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends ConsumerState<CompareView> {
  DateTime? _before;
  DateTime? _after;
  PhotoPose _pose = PhotoPose.front;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkins = widget.checkins;
    if (checkins.length < 2) {
      return BentoCard(
        child: Text(
          'Karşılaştırmak için en az iki kontrol gününde fotoğraf gerekli.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    final dates = [for (final c in checkins) c.date];
    final after = dates.contains(_after) ? _after! : dates.first;
    final before = dates.contains(_before) ? _before! : dates.last;
    PhotoCheckin of(DateTime d) => checkins.firstWhere((c) => c.date == d);

    final weights =
        ref.watch(weightSeriesProvider(compareWeightWindowDays)).valueOrNull ??
            const <WeightEntry>[];
    final measurements = ref.watch(measurementsProvider).valueOrNull ??
        const <BodyMeasurement>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateChip(
                key: const Key('compare-before'),
                label: 'Önce',
                value: before,
                dates: dates,
                onChanged: (d) => setState(() => _before = d),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Icon(Icons.arrow_forward_outlined,
                  size: 18, color: AppColors.textMuted),
            ),
            Expanded(
              child: _DateChip(
                key: const Key('compare-after'),
                label: 'Sonra',
                value: after,
                dates: dates,
                onChanged: (d) => setState(() => _after = d),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: SegmentedButton<PhotoPose>(
            key: const Key('compare-pose'),
            showSelectedIcon: false,
            segments: [
              for (final p in PhotoPose.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_pose},
            onSelectionChanged: (s) => setState(() => _pose = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, d) in [before, after].indexed) ...[
              if (i > 0) const SizedBox(width: AppSpacing.grid),
              Expanded(
                child: _ComparePane(
                  date: d,
                  photo: of(d).photos[_pose],
                  pose: _pose,
                  blurred: widget.blurred,
                  weight: nearestWeight(weights, d),
                  waist: nearestMeasurement(measurements, d, BodyField.waist),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        _Diff(
          weights: weights,
          measurements: measurements,
          before: before,
          after: after,
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    super.key,
    required this.label,
    required this.value,
    required this.dates,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final List<DateTime> dates;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<DateTime>(
      tooltip: '$label tarihi',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final d in dates)
          PopupMenuItem(value: d, child: Text(BodyFormat.longDate(d))),
      ],
      child: Material(
        color: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.textMuted)),
                    Text(BodyFormat.shortDate(value),
                        style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
              Icon(Icons.expand_more_outlined,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparePane extends StatelessWidget {
  const _ComparePane({
    required this.date,
    required this.photo,
    required this.pose,
    required this.blurred,
    required this.weight,
    required this.waist,
  });

  final DateTime date;
  final ProgressPhoto? photo;
  final PhotoPose pose;
  final bool blurred;
  final WeightEntry? weight;
  final double? waist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: photo == null
              ? BodyPhotoPlaceholder(
                  icon: Icons.hide_image_outlined,
                  label: '${pose.label} yok',
                )
              : BodyPhotoImage(photo: photo!, blurred: blurred),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(BodyFormat.longDate(date), style: theme.textTheme.titleSmall),
        Text(
          weight == null ? 'Kilo –' : '${HealthFormat.kg(weight!.weightKg)} kg',
          style: muted,
        ),
        Text(
          waist == null ? 'Bel –' : 'Bel ${BodyFormat.cm(waist!)} cm',
          style: muted,
        ),
      ],
    );
  }
}

/// "−3,2 kg · Bel −4 cm · 8 hafta"
class _Diff extends StatelessWidget {
  const _Diff({
    required this.weights,
    required this.measurements,
    required this.before,
    required this.after,
  });

  final List<WeightEntry> weights;
  final List<BodyMeasurement> measurements;
  final DateTime before;
  final DateTime after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w0 = nearestWeight(weights, before);
    final w1 = nearestWeight(weights, after);
    final b0 = nearestMeasurement(measurements, before, BodyField.waist);
    final b1 = nearestMeasurement(measurements, after, BodyField.waist);
    final days = after.difference(before).inDays.abs();
    final parts = [
      if (w0 != null && w1 != null)
        '${BodyFormat.delta(roundCm(w1.weightKg - w0.weightKg))} kg',
      if (b0 != null && b1 != null)
        'Bel ${BodyFormat.delta(roundCm(b1 - b0))} cm',
      days >= 14 ? '${(days / 7).round()} hafta' : '$days gün',
    ];
    return BentoCard(
      key: const Key('compare-diff'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.compare_arrows_outlined,
              size: 18, color: AppColors.accent),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(parts.join(' · '), style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
