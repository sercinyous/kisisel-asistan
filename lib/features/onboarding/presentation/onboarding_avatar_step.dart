import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/avatar/avatar_photo_store.dart';
import '../../../core/avatar/avatar_spec.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/avatar_picker_sheet.dart';
import '../../settings/presentation/my_avatar.dart';
import '../../settings/presentation/settings_providers.dart';
import 'onboarding_widgets.dart';

/// Profil adımından sonra isteğe bağlı: maskot ya da fotoğraf seçimi. Seçim
/// hemen kaydedilir; "Atla" baş harflerle devam eder.
class OnboardingAvatarStep extends ConsumerStatefulWidget {
  const OnboardingAvatarStep({
    super.key,
    required this.name,
    required this.onSkip,
  });

  /// Profil adımında yazılan ad (baş harf önizlemesi için).
  final String name;
  final VoidCallback onSkip;

  @override
  ConsumerState<OnboardingAvatarStep> createState() =>
      _OnboardingAvatarStepState();
}

class _OnboardingAvatarStepState extends ConsumerState<OnboardingAvatarStep> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              avatarErrorMessage(error, 'Kaydedilemedi. Tekrar dene.'),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ref.watch(settingsOrDefaultProvider).avatar;
    final photoSupported = ref.watch(avatarPhotoSupportedProvider);
    final actions = AvatarActions(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Profilini seç',
          subtitle: 'Arkadaşların seni bu resimle görür. İstersen şimdilik '
              'atla; baş harflerin kullanılır, sonra Hesap’tan değiştirebilirsin.',
        ),
        Center(
          child: MyAvatar(
            key: const Key('onboarding-avatar-preview'),
            size: 96,
            name: widget.name,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (photoSupported) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('onboarding-avatar-camera'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => actions.pickPhoto(AvatarPhotoSource.camera)),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('Fotoğraf çek'),
                ),
              ),
              const SizedBox(width: AppSpacing.grid),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('onboarding-avatar-gallery'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => actions.pickPhoto(AvatarPhotoSource.gallery)),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Galeriden seç'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        BentoCard(
          child: MascotGrid(
            selectedId:
                avatar.kind == AvatarKind.mascot ? avatar.mascotId : null,
            onSelect:
                _busy ? null : (id) => _run(() => actions.chooseMascot(id)),
          ),
        ),
        Align(
          child: TextButton(
            key: const Key('onboarding-avatar-skip'),
            onPressed: _busy ? null : widget.onSkip,
            child: const Text('Atla'),
          ),
        ),
      ],
    );
  }
}
