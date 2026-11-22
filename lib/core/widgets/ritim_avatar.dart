import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../avatar/avatar_photo_store.dart';
import '../avatar/avatar_spec.dart';
import '../theme/app_theme.dart';

/// Profil avatarı: baş harfler, maskot ya da fotoğraf; her boyutta yuvarlak.
/// Fotoğraf imzalı adresle okunur ([avatarPhotoUrlProvider]); yüklenemezse
/// ya da [userId] yoksa baş harfler görünür. Baş harf türünde [fallbackUrl]
/// (ör. Google profil resmi) varsa o gösterilir.
class RitimAvatar extends ConsumerWidget {
  const RitimAvatar({
    super.key,
    required this.choice,
    required this.name,
    this.email,
    this.userId,
    this.size = 40,
    this.fallbackUrl,
    this.semanticLabel,
  });

  final AvatarChoice choice;
  final String? name;
  final String? email;
  final String? userId;
  final double size;
  final String? fallbackUrl;

  /// Boşsa addan ve türden üretilir.
  final String? semanticLabel;

  String _label() {
    if (semanticLabel != null) return semanticLabel!;
    final who = (name ?? '').trim().isNotEmpty ? name!.trim() : 'Profil';
    return switch (choice.kind) {
      AvatarKind.mascot => '$who, avatar: ${choice.mascot?.name ?? 'maskot'}',
      AvatarKind.photo => '$who, profil fotoğrafı',
      AvatarKind.initials => '$who, avatar: baş harfler',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child = switch (choice.kind) {
      AvatarKind.mascot when choice.mascot != null => SvgPicture.asset(
          choice.mascot!.assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      AvatarKind.photo when userId != null => _photo(ref),
      _ => fallbackUrl == null ? _initials(context) : _network(context, fallbackUrl!),
    };
    return Semantics(
      label: _label(),
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(child: child),
      ),
    );
  }

  Widget _photo(WidgetRef ref) {
    final url = ref
        .watch(avatarPhotoUrlProvider((userId!, choice.version)))
        .valueOrNull;
    return Builder(
      builder: (context) =>
          url == null ? _initials(context) : _network(context, url),
    );
  }

  Widget _network(BuildContext context, String url) => Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) =>
            frame == null && !sync ? _initials(context) : child,
        errorBuilder: (context, _, __) => _initials(context),
      );

  Widget _initials(BuildContext context) {
    final background = (choice.color ?? AvatarColorRole.accent).color;
    return ColoredBox(
      color: background,
      child: Center(
        child: Text(
          initialsFor(name, email: email),
          maxLines: 1,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.onAccent,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
                height: 1,
              ),
        ),
      ),
    );
  }
}
