import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'friends_providers.dart';
import 'friends_screen.dart';

/// Kokpit başlığındaki kişi ikonu + bekleyen davet rozeti. Uygulama açılınca
/// ve öne gelince davet sayısı yenilenir.
class FriendsButton extends ConsumerStatefulWidget {
  const FriendsButton({super.key});

  @override
  ConsumerState<FriendsButton> createState() => _FriendsButtonState();
}

class _FriendsButtonState extends ConsumerState<FriendsButton>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(pendingFriendRequestCountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(pendingFriendRequestCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: count > 0 ? 'Arkadaşlar ($count davet)' : 'Arkadaşlar',
      color: AppColors.textSecondary,
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FriendsScreen()),
        );
        ref.invalidate(pendingFriendRequestCountProvider);
      },
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppColors.danger,
        textColor: AppColors.onAccent,
        child: const Icon(Icons.people_outline_rounded),
      ),
    );
  }
}
