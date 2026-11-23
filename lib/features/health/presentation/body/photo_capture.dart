import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/avatar/avatar_photo_store.dart'
    show AvatarImagePicker, AvatarPermissionDenied, AvatarPhotoSource;
import '../../../../core/theme/app_theme.dart';
import '../../../operations/presentation/operations_widgets.dart'
    show showOpsSheet;
import '../providers/body_providers.dart';
import 'body_format.dart';
import 'photo_thumb.dart';

/// İlerleme fotoğrafı seçici: arka kamera ya da galeri; vazgeçilirse null.
/// Küçültme ve EXIF silme yüklemede ([BodyRepository.uploadPhoto]) yapılır.
final bodyImagePickerProvider = Provider<AvatarImagePicker>(
  (ref) => (source) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source == AvatarPhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' || e.code == 'photo_access_denied') {
        throw AvatarPermissionDenied(source);
      }
      rethrow;
    }
    return file?.readAsBytes();
  },
);

const String bodyPhotoUnsupported =
    'Fotoğraflar yalnızca iPhone uygulamasında çekilebilir.';

/// Bir poz için çekim: önceki aynı poz yarı saydam kılavuz olarak gösterilir,
/// çekilen kare onun üstüne bindirilir; "Kaydet" yükler.
class PhotoCaptureSheet extends ConsumerStatefulWidget {
  const PhotoCaptureSheet({
    super.key,
    required this.date,
    required this.pose,
    this.previous,
  });

  final DateTime date;
  final PhotoPose pose;

  /// Aynı pozun bir önceki fotoğrafı (kılavuz).
  final ProgressPhoto? previous;

  /// Kaydedildiyse `true`.
  static Future<bool> show(
    BuildContext context, {
    required DateTime date,
    required PhotoPose pose,
    ProgressPhoto? previous,
  }) =>
      showOpsSheet(
        context,
        PhotoCaptureSheet(date: date, pose: pose, previous: previous),
      );

  @override
  ConsumerState<PhotoCaptureSheet> createState() => _PhotoCaptureSheetState();
}

class _PhotoCaptureSheetState extends ConsumerState<PhotoCaptureSheet> {
  Uint8List? _bytes;
  bool _saving = false;
  String? _error;

  Future<void> _pick(AvatarPhotoSource source) async {
    setState(() => _error = null);
    try {
      final bytes = await ref.read(bodyImagePickerProvider)(source);
      if (!mounted || bytes == null) return;
      setState(() => _bytes = bytes);
    } on AvatarPermissionDenied catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Fotoğraf alınamadı. Tekrar dene.');
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final ProgressPhoto photo;
    try {
      photo = await ref.read(bodyRepositoryProvider).uploadPhoto(
            takenOn: widget.date,
            pose: widget.pose,
            imageBytes: bytes,
          );
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Yüklenemedi. Bağlantını kontrol edip tekrar dene.';
      });
      return;
    }
    invalidatePhotoPath(ref, photo.storagePath);
    if (navigator.canPop()) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = ref.watch(bodyRepositoryProvider).photosSupported;
    final bytes = _bytes;
    final previous = widget.previous;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 0, AppSpacing.page, AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.pose.label} fotoğrafı',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              previous == null
                  ? 'Aynı ışıkta, aynı mesafeden; telefon göğüs hizasında.'
                  : 'Kılavuz: ${BodyFormat.shortDate(previous.takenOn)} '
                      'fotoğrafı. Aynı duruş ve mesafeyi yakala.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.m),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (bytes != null)
                          Image.memory(bytes, fit: BoxFit.cover)
                        else
                          const BodyPhotoPlaceholder(
                            icon: Icons.accessibility_new_rounded,
                            radius: AppRadii.card,
                          ),
                        if (previous != null)
                          IgnorePointer(
                            child: Opacity(
                              key: const Key('capture-ghost'),
                              opacity: bytes == null ? 0.45 : 0.3,
                              child: BodyPhotoImage(
                                photo: previous,
                                radius: AppRadii.card,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            if (!supported)
              Text(
                bodyPhotoUnsupported,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              )
            else if (bytes == null) ...[
              FilledButton.icon(
                key: const Key('capture-camera'),
                onPressed: () => _pick(AvatarPhotoSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Kamerayı aç'),
              ),
              const SizedBox(height: AppSpacing.s),
              OutlinedButton.icon(
                key: const Key('capture-gallery'),
                onPressed: () => _pick(AvatarPhotoSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeriden seç'),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => setState(() => _bytes = null),
                      child: const Text('Yeniden çek'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: FilledButton(
                      key: const Key('capture-save'),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onAccent,
                              ),
                            )
                          : const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// [photos] içinden [before]'dan önceki son [pose] fotoğrafı (kılavuz).
ProgressPhoto? previousPosePhoto(
  List<ProgressPhoto> photos,
  PhotoPose pose,
  DateTime before,
) {
  ProgressPhoto? best;
  for (final p in photos) {
    if (p.pose != pose || !p.takenOn.isBefore(before)) continue;
    if (best == null || p.takenOn.isAfter(best.takenOn)) best = p;
  }
  return best;
}
