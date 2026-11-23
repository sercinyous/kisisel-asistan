import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import '../../../../core/widgets/ritim_ui.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../providers/body_providers.dart';
import '../weight_sheets.dart';
import 'measurement_form_sheet.dart';
import 'photo_capture.dart';
import 'photo_thumb.dart';

/// Kontrol akışının adımları.
enum CheckinStep {
  weigh('Tartı', 'Sabah, aç karnına, tuvaletten sonra.',
      Icons.monitor_weight_outlined),
  tape('Mezura', 'Bel, kalça ve diğerleri; nefes verince ölç.',
      Icons.straighten_outlined),
  photo('Fotoğraf', 'Ön, yan, arka; aynı ışık ve mesafe.',
      Icons.photo_camera_outlined);

  const CheckinStep(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

/// Adım sonucu.
enum CheckinStepState { pending, done, skipped }

/// KontrolAkışı: tartı → mezura → fotoğraf; her adım atlanabilir.
class CheckinFlowScreen extends ConsumerStatefulWidget {
  const CheckinFlowScreen({super.key});

  /// Vücut banner'ı ve Kokpit'teki "Ölçü ve fotoğraf günü" satırı açar.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CheckinFlowScreen(),
      ));

  @override
  ConsumerState<CheckinFlowScreen> createState() => _CheckinFlowScreenState();
}

class _CheckinFlowScreenState extends ConsumerState<CheckinFlowScreen> {
  final Map<CheckinStep, CheckinStepState> _states = {
    for (final s in CheckinStep.values) s: CheckinStepState.pending,
  };
  int _index = 0;

  bool get _finished => _index >= CheckinStep.values.length;

  DateTime get _today => AppDates.startOfDay(DateTime.now());

  void _complete(CheckinStepState state) => setState(() {
        _states[CheckinStep.values[_index]] = state;
        _index++;
      });

  Future<void> _weigh() async {
    if (await WeightFormSheet.show(context) && mounted) {
      _complete(CheckinStepState.done);
    }
  }

  Future<void> _tape() async {
    if (await MeasurementFormSheet.show(context, date: _today) && mounted) {
      _complete(CheckinStepState.done);
    }
  }

  Future<void> _capture(PhotoPose pose, List<ProgressPhoto> photos) =>
      PhotoCaptureSheet.show(
        context,
        date: _today,
        pose: pose,
        previous: previousPosePhoto(photos, pose, _today),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ölçü ve fotoğraf günü'),
        leading: IconButton(
          tooltip: 'Kapat',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_outlined),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.s, AppSpacing.page, 120),
        children: [
          _Progress(states: _states, index: _index),
          const SizedBox(height: AppSpacing.l),
          if (_finished)
            _Done(states: _states)
          else
            _stepCard(theme, CheckinStep.values[_index]),
        ],
      ),
    );
  }

  Widget _stepCard(ThemeData theme, CheckinStep step) {
    final number = step.index + 1;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BentoLabel(
          label: 'Kontrol · $number/${CheckinStep.values.length}',
          trailing: step.label,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          step.hint,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
    Widget footer(String label, VoidCallback? onPrimary) => Row(
          children: [
            RitimPillButton(
              key: const Key('checkin-skip'),
              label: 'Atla',
              ghost: true,
              onPressed: () => _complete(CheckinStepState.skipped),
            ),
            const Spacer(),
            Flexible(
              child: RitimPillButton(
                key: const Key('checkin-primary'),
                label: label,
                onPressed: onPrimary,
              ),
            ),
          ],
        );

    switch (step) {
      case CheckinStep.weigh:
      case CheckinStep.tape:
        return BentoCard(
          key: Key('checkin-step-${step.name}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              footer(
                step == CheckinStep.weigh ? 'Tartıl' : 'Ölç',
                step == CheckinStep.weigh ? _weigh : _tape,
              ),
            ],
          ),
        );
      case CheckinStep.photo:
        final supported = ref.watch(bodyRepositoryProvider).photosSupported;
        final photos =
            ref.watch(progressPhotosProvider).valueOrNull ?? const [];
        final todays = {
          for (final p in photos)
            if (p.takenOn == _today) p.pose: p,
        };
        final hidden = ref.watch(settingsOrDefaultProvider).hidePhotos;
        return BentoCard(
          key: Key('checkin-step-${step.name}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (supported)
                BodyPoseRow(
                  photos: todays,
                  blurred: hidden,
                  onEmptyTap: (pose) => _capture(pose, photos),
                  onPhotoTap: (p) => _capture(p.pose, photos),
                )
              else
                Text(
                  bodyPhotoUnsupported,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              const SizedBox(height: AppSpacing.md),
              footer(
                todays.isEmpty ? 'Poza dokun' : 'Bitir (${todays.length}/3)',
                todays.isEmpty ? null : () => _complete(CheckinStepState.done),
              ),
            ],
          ),
        );
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.states, required this.index});

  final Map<CheckinStep, CheckinStepState> states;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final step in CheckinStep.values) ...[
          if (step.index > 0) const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    color: switch (states[step]!) {
                      CheckinStepState.done => AppColors.accent,
                      CheckinStepState.skipped => AppColors.textMuted,
                      CheckinStepState.pending => step.index == index
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.track,
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.states});

  final Map<CheckinStep, CheckinStepState> states;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = states.values.where((s) => s == CheckinStepState.done).length;
    return BentoCard(
      key: const Key('checkin-done'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            done > 0
                ? Icons.check_circle_rounded
                : Icons.do_not_disturb_on_outlined,
            size: 56,
            color: done > 0 ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            done > 0 ? 'Kontrol tamam' : 'Bugün atlandı',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          for (final s in CheckinStep.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    states[s] == CheckinStepState.done
                        ? Icons.check_outlined
                        : Icons.remove_outlined,
                    size: 16,
                    color: states[s] == CheckinStepState.done
                        ? AppColors.accent
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${s.label}${states[s] == CheckinStepState.done ? '' : ' · atlandı'}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.l),
          FilledButton(
            key: const Key('checkin-close'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}
