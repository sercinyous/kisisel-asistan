import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/bento.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../health_widgets.dart';
import '../providers/body_providers.dart';
import '../providers/targets_providers.dart';
import 'body_format.dart';
import 'compare_view.dart';
import 'photo_capture.dart';
import 'photo_thumb.dart';

/// FotoğraflarScreen: hafta ızgarası (kontrol günü başına 3 poz) ya da
/// Karşılaştır. "Fotoğrafları gizle" açıkken fotoğraflar dokunulana dek
/// bulanıktır.
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key, this.compare = false});

  final bool compare;

  static Future<void> open(BuildContext context, {bool compare = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PhotosScreen(compare: compare),
      ));

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  late bool _compare = widget.compare;

  Future<void> _capture(PhotoPose pose, {DateTime? date}) async {
    final photos = ref.read(progressPhotosProvider).valueOrNull ?? const [];
    final day = date ?? AppDates.startOfDay(DateTime.now());
    await PhotoCaptureSheet.show(
      context,
      date: day,
      pose: pose,
      previous: previousPosePhoto(photos, pose, day),
    );
  }

  Future<void> _choosePose() async {
    final pose = await showModalBottomSheet<PhotoPose>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in PhotoPose.values)
              ListTile(
                leading: const Icon(Icons.accessibility_new_rounded),
                title: Text(p.label),
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        ),
      ),
    );
    if (pose != null && mounted) await _capture(pose);
  }

  Future<void> _open(ProgressPhoto photo, bool blurred) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(AppSpacing.m),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${photo.pose.label} · ${BodyFormat.longDate(photo.takenOn)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: BodyPhotoImage(photo: photo, blurred: blurred),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('photo-delete'),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                    label:
                        Text('Sil', style: TextStyle(color: AppColors.danger)),
                  ),
                  const Spacer(),
                  FilledButton(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (delete != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(bodyRepositoryProvider).deletePhoto(photo);
      ref.invalidate(progressPhotosProvider);
    } on Object {
      messenger.showSnackBar(const SnackBar(content: Text(healthDeleteError)));
    }
  }

  Future<void> _toggleHide(bool hidden) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(planControllerProvider).setHidePhotos(!hidden);
    } on Object {
      messenger.showSnackBar(
          const SnackBar(content: Text('Ayar kaydedilemedi. Tekrar dene.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = ref.watch(settingsOrDefaultProvider).hidePhotos;
    final supported = ref.watch(bodyRepositoryProvider).photosSupported;
    final checkins = ref.watch(photoCheckinsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotoğraflar'),
        actions: [
          IconButton(
            key: const Key('photos-hide'),
            tooltip: hidden ? 'Fotoğrafları göster' : 'Fotoğrafları gizle',
            onPressed: () => _toggleHide(hidden),
            icon: Icon(hidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
          ),
          if (supported)
            IconButton(
              key: const Key('photos-add'),
              tooltip: 'Fotoğraf çek',
              onPressed: _choosePose,
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
        ],
      ),
      body: checkins.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: HealthCompactMessage(
            text: 'Fotoğraflar yüklenemedi.',
            onRetry: () => ref.invalidate(progressPhotosProvider),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.s, AppSpacing.page, 120),
          children: [
            Center(
              child: SegmentedButton<bool>(
                key: const Key('photos-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Haftalar')),
                  ButtonSegment(value: true, label: Text('Karşılaştır')),
                ],
                selected: {_compare},
                onSelectionChanged: (s) => setState(() => _compare = s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            if (!supported)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: Text(
                  bodyPhotoUnsupported,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
            if (list.isEmpty)
              BentoCard(
                child: Column(
                  children: [
                    Icon(Icons.photo_camera_back_outlined,
                        size: 36, color: AppColors.accent),
                    const SizedBox(height: AppSpacing.md),
                    Text('Henüz fotoğraf yok.',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Fotoğraflar yalnızca sende kalır; arkadaşlar, raporlar '
                      've AI görmez.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    if (supported) ...[
                      const SizedBox(height: AppSpacing.m),
                      FilledButton(
                        onPressed: () => _capture(PhotoPose.front),
                        child: const Text('İlk fotoğrafı çek'),
                      ),
                    ],
                  ],
                ),
              )
            else if (_compare)
              CompareView(checkins: list, blurred: hidden)
            else
              for (final c in list) ...[
                BentoCard(
                  key: Key('photo-week-${dateOnlyIso(c.date)}'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                            left: AppSpacing.xs, bottom: AppSpacing.s),
                        child: Text(BodyFormat.longDate(c.date),
                            style: theme.textTheme.titleSmall),
                      ),
                      BodyPoseRow(
                        photos: c.photos,
                        blurred: hidden,
                        showLabels: false,
                        onPhotoTap: (p) => _open(p, hidden),
                        onEmptyTap: supported
                            ? (pose) => _capture(pose, date: c.date)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.grid),
              ],
          ],
        ),
      ),
    );
  }
}
