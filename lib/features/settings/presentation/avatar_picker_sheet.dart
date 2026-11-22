import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/avatar/avatar_image.dart';
import '../../../core/avatar/avatar_photo_store.dart';
import '../../../core/avatar/avatar_spec.dart';
import '../../../core/services/error_reporter.dart';
import '../../../core/theme/app_theme.dart';
import 'my_avatar.dart';
import 'settings_providers.dart';

/// Kullanıcıya gösterilecek avatar hatası.
class AvatarActionError implements Exception {
  const AvatarActionError(this.message);

  final String message;

  static const unreadable = AvatarActionError('Bu fotoğraf okunamadı.');
  static const saveFailed =
      AvatarActionError('Fotoğraf yüklendi ama kaydedilemedi. Tekrar dene.');

  @override
  String toString() => 'AvatarActionError($message)';
}

/// Hata için gösterilecek metin; bilinmeyen hatada [fallback].
String avatarErrorMessage(Object error, String fallback) => switch (error) {
      AvatarActionError(:final message) => message,
      AvatarPermissionDenied(:final message) => message,
      _ => fallback,
    };

/// Avatar değişiklikleri: maskot, renk, fotoğraf, kaldır. Hepsi
/// `user_settings` avatar sütunlarına yazar; fotoğraf önce Storage'a yüklenir.
/// Tür fotoğraftan başka bir şeye geçince Storage'daki dosya silinir.
class AvatarActions {
  const AvatarActions(this.ref);

  final WidgetRef ref;

  AvatarChoice get _current =>
      ref.read(settingsOrDefaultProvider).avatar;

  Future<void> _save(AvatarChoice avatar) =>
      ref.read(userSettingsProvider.notifier).saveAvatar(avatar);

  /// Önceki seçim fotoğrafsa ve yenisi değilse dosyayı siler: bir kez
  /// yineler, yine olmazsa hatayı raporlar (seçim yine de geçerli kalır).
  Future<void> _dropPhotoIfLeft(AvatarChoice previous, AvatarChoice next) async {
    if (previous.kind != AvatarKind.photo || next.kind == AvatarKind.photo) {
      return;
    }
    final store = ref.read(avatarPhotoStoreProvider);
    try {
      await store.remove();
    } catch (_) {
      try {
        await store.remove();
      } catch (error, stack) {
        ref.read(reportErrorProvider)(error, stack);
      }
    }
  }

  Future<void> _change(AvatarChoice next) async {
    final previous = _current;
    await _save(next);
    await _dropPhotoIfLeft(previous, next);
  }

  Future<void> chooseMascot(String id) => _change(_current.withMascot(id));

  Future<void> chooseColor(AvatarColorRole role) =>
      _save(_current.withColor(role));

  /// Fotoğraf seçer/çeker, kare kırpıp 512 piksel JPEG yükler. Vazgeçilirse
  /// false döner. İzin yoksa [AvatarPermissionDenied], görüntü çözülemezse
  /// [AvatarActionError.unreadable]; yükleme olup kayıt (bir yinelemeyle)
  /// olmazsa [AvatarActionError.saveFailed].
  Future<bool> pickPhoto(AvatarPhotoSource source) async {
    final bytes = await ref.read(avatarImagePickerProvider)(source);
    if (bytes == null) return false;
    final Uint8List jpeg;
    try {
      jpeg = await prepareAvatarJpeg(bytes);
    } catch (_) {
      throw AvatarActionError.unreadable;
    }
    await ref.read(avatarPhotoStoreProvider).upload(jpeg);
    final next = _current.withPhoto();
    try {
      await _save(next);
    } catch (_) {
      try {
        await _save(next);
      } catch (error, stack) {
        // Dosya eski sürüm anahtarıyla değişti: önbellekteki adresler atılır.
        ref.invalidate(avatarPhotoUrlProvider);
        ref.read(reportErrorProvider)(error, stack);
        throw AvatarActionError.saveFailed;
      }
    }
    return true;
  }

  /// Baş harflere döner; fotoğraf varsa Storage'dan da silinir.
  Future<void> remove() => _change(_current.cleared());
}

/// Avatar seçim sayfası (alt sayfa).
Future<void> showAvatarPickerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const AvatarPickerSheet(),
    );

class AvatarPickerSheet extends ConsumerStatefulWidget {
  const AvatarPickerSheet({super.key});

  @override
  ConsumerState<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends ConsumerState<AvatarPickerSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(avatarErrorMessage(error, failure))),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatar = ref.watch(settingsOrDefaultProvider).avatar;
    final photoSupported = ref.watch(avatarPhotoSupportedProvider);
    final actions = AvatarActions(ref);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MyAvatar(size: 56),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('Profil resmi', style: theme.textTheme.titleLarge),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (photoSupported) ...[
              _ActionTile(
                key: const Key('avatar-camera'),
                icon: Icons.photo_camera_rounded,
                label: 'Fotoğraf çek',
                onTap: _busy
                    ? null
                    : () => _run(
                          () => actions.pickPhoto(AvatarPhotoSource.camera),
                          'Fotoğraf yüklenemedi. Tekrar dene.',
                        ),
              ),
              _ActionTile(
                key: const Key('avatar-gallery'),
                icon: Icons.photo_library_rounded,
                label: 'Galeriden seç',
                onTap: _busy
                    ? null
                    : () => _run(
                          () => actions.pickPhoto(AvatarPhotoSource.gallery),
                          'Fotoğraf yüklenemedi. Tekrar dene.',
                        ),
              ),
            ],
            if (avatar.kind != AvatarKind.initials)
              _ActionTile(
                key: const Key('avatar-remove'),
                icon: Icons.person_off_rounded,
                label: 'Kaldır',
                color: AppColors.danger,
                onTap: _busy
                    ? null
                    : () => _run(actions.remove, 'Kaldırılamadı. Tekrar dene.'),
              ),
            const SizedBox(height: AppSpacing.md),
            Text('Maskot seç', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            MascotGrid(
              selectedId:
                  avatar.kind == AvatarKind.mascot ? avatar.mascotId : null,
              onSelect: _busy
                  ? null
                  : (id) => _run(
                        () => actions.chooseMascot(id),
                        'Kaydedilemedi. Tekrar dene.',
                      ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Baş harf rengi', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final role in AvatarColorRole.values)
                  _ColorDot(
                    role: role,
                    selected: (avatar.color ?? AvatarColorRole.accent) == role,
                    onTap: _busy
                        ? null
                        : () => _run(
                              () => actions.chooseColor(role),
                              'Kaydedilemedi. Tekrar dene.',
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color ?? AppColors.accent),
        title: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.role, required this.selected, this.onTap});

  final AvatarColorRole role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${role.label} rengi',
        child: InkWell(
          key: Key('avatar-color-${role.dbValue}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: role.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.textPrimary : AppColors.border,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      );
}

/// 16 maskotun ızgarası (adlarıyla). Seçili olan halkayla işaretlenir.
class MascotGrid extends StatelessWidget {
  const MascotGrid({super.key, required this.selectedId, required this.onSelect});

  final String? selectedId;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mascots.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.s,
        crossAxisSpacing: AppSpacing.s,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, i) {
        final m = mascots[i];
        final selected = m.id == selectedId;
        return Tooltip(
          message: m.trait,
          child: Semantics(
            button: true,
            selected: selected,
            label: '${m.name}: ${m.trait}',
            excludeSemantics: true,
            child: InkWell(
              key: Key('mascot-${m.id}'),
              borderRadius: BorderRadius.circular(AppRadii.chip),
              onTap: onSelect == null ? null : () => onSelect!(m.id),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: AppColors.accent, width: 3)
                            : null,
                      ),
                      child: ClipOval(child: SvgPicture.asset(m.assetPath)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? AppColors.accent : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
