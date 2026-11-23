import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/widgets/ritim_avatar.dart';
import 'settings_providers.dart';

/// Oturumdaki kişinin avatarı (ayarlardan ve oturumdan).
class MyAvatar extends ConsumerWidget {
  const MyAvatar({super.key, this.size = 40, this.name});

  final double size;

  /// Doluysa ayarlardaki ad yerine baş harfler bundan çıkar (ilk kurulum).
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsOrDefaultProvider);
    final user =
        ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user));
    return RitimAvatar(
      choice: settings.avatar,
      name: (name ?? '').trim().isNotEmpty ? name : settings.displayName,
      email: user?.email,
      userId: user?.id,
      size: size,
    );
  }
}
