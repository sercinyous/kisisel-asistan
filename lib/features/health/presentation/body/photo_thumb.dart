import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/body_providers.dart';

/// İmzalı adresten okunan ilerleme fotoğrafı. [blurred] açıkken bulanık
/// gösterilir; ilk dokunuş fotoğrafı açar, sonraki dokunuş [onTap]'e gider.
class BodyPhotoImage extends ConsumerStatefulWidget {
  const BodyPhotoImage({
    super.key,
    required this.photo,
    this.blurred = false,
    this.onTap,
    this.radius = AppRadii.inner,
  });

  final ProgressPhoto photo;
  final bool blurred;
  final VoidCallback? onTap;
  final double radius;

  @override
  ConsumerState<BodyPhotoImage> createState() => _BodyPhotoImageState();
}

class _BodyPhotoImageState extends ConsumerState<BodyPhotoImage> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(photoUrlProvider(widget.photo.storagePath));
    final hidden = widget.blurred && !_revealed;
    Widget image = url.when(
      skipLoadingOnRefresh: true,
      loading: () => BodyPhotoPlaceholder(
        icon: Icons.hourglass_empty_rounded,
        radius: widget.radius,
      ),
      error: (_, __) => BodyPhotoPlaceholder(
        icon: Icons.broken_image_outlined,
        radius: widget.radius,
      ),
      data: (link) => link == null
          ? BodyPhotoPlaceholder(
              icon: Icons.image_not_supported_outlined,
              radius: widget.radius,
            )
          : Image.network(
              link,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => BodyPhotoPlaceholder(
                icon: Icons.broken_image_outlined,
                radius: widget.radius,
              ),
            ),
    );
    if (hidden) {
      image = Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: image,
          ),
          ColoredBox(color: AppColors.scrim.withValues(alpha: 0.25)),
          Center(
            child: Icon(
              Icons.visibility_off_outlined,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      label: hidden
          ? '${widget.photo.pose.label} fotoğrafı gizli, göstermek için dokun'
          : '${widget.photo.pose.label} fotoğrafı',
      child: GestureDetector(
        key: Key('body-photo-${widget.photo.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: hidden ? () => setState(() => _revealed = true) : widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: SizedBox.expand(child: image),
        ),
      ),
    );
  }
}

/// Fotoğraf yokken ya da yüklenirken boş kutu.
class BodyPhotoPlaceholder extends StatelessWidget {
  const BodyPhotoPlaceholder({
    super.key,
    this.icon = Icons.add_a_photo_outlined,
    this.label,
    this.radius = AppRadii.inner,
    this.onTap,
  });

  final IconData icon;
  final String? label;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textMuted, size: 22),
              if (label != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label!,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Üç poz yan yana (ön/yan/arka), 3:4 oranında.
class BodyPoseRow extends StatelessWidget {
  const BodyPoseRow({
    super.key,
    required this.photos,
    required this.blurred,
    this.onPhotoTap,
    this.onEmptyTap,
    this.showLabels = true,
  });

  final Map<PhotoPose, ProgressPhoto> photos;
  final bool blurred;
  final void Function(ProgressPhoto photo)? onPhotoTap;
  final void Function(PhotoPose pose)? onEmptyTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, pose) in PhotoPose.values.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: photos[pose] == null
                      ? BodyPhotoPlaceholder(
                          label: pose.label,
                          onTap: onEmptyTap == null
                              ? null
                              : () => onEmptyTap!(pose),
                        )
                      : BodyPhotoImage(
                          photo: photos[pose]!,
                          blurred: blurred,
                          onTap: onPhotoTap == null
                              ? null
                              : () => onPhotoTap!(photos[pose]!),
                        ),
                ),
                if (showLabels) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    pose.label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
