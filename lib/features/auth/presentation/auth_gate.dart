import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../../../core/services/notification_sync.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/widgets/ritim_top/ritim_top.dart';
import '../../health/presentation/food_picker_sheet.dart';
import '../../health/presentation/providers/body_providers.dart';
import '../../onboarding/presentation/onboarding_gate.dart';
import '../../settings/data/account_repository.dart';
import '../../stories/presentation/stories_providers.dart';
import 'sign_in_screen.dart';

/// Oturum kullanıcıdan boşa döndüyse gezgini ilk sayfaya indirir.
/// Çıkış algılandıysa `true` döner.
bool popToRootOnSignOut(
  BuildContext context,
  AsyncValue<Session?>? previous,
  AsyncValue<Session?> next,
) {
  final hadUser = previous?.valueOrNull?.user.id != null;
  final hasUser = next.valueOrNull?.user.id != null;
  if (hadUser && !hasUser && next.hasValue) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    return true;
  }
  return false;
}

/// Kullanıcı soneki olmayan cihaz tercihlerini siler ve bellekteki
/// kopyalarını tazeler; sonraki hesap önceki kişinin tercihlerini görmez.
Future<void> _forgetDevicePrefs(WidgetRef ref) async {
  await ref.read(accountRepositoryProvider).clearSharedPersonalKeys();
  ref
    ..invalidate(recentFoodsProvider)
    ..invalidate(storySeenProvider)
    ..invalidate(checkinDismissedProvider)
    ..invalidate(healthNudgePrefsProvider);
}

/// Oturum varsa ilk kurulum kapısını (bitmişse ana kabuk), yoksa giriş ekranını
/// gösterir.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Çıkışta ya da hesap değişiminde bekleyen bildirimleri siler.
    ref.watch(notificationSessionGuardProvider);
    // Oturum hangi yoldan biterse bitsin (başka cihazdan silme, token iptali)
    // üstte açık kalan sayfalar kapatılır; altta giriş ekranı görünür.
    ref.listen<AsyncValue<Session?>>(
      authSessionProvider,
      (previous, next) {
        if (popToRootOnSignOut(context, previous, next)) {
          unawaited(_forgetDevicePrefs(ref));
        }
      },
    );
    final session = ref.watch(authSessionProvider);
    return session.when(
      loading: () => const Scaffold(
        body: Center(child: RitimTop(size: 72)),
      ),
      error: (_, __) =>
          ref.read(supabaseClientProvider).auth.currentSession == null
              ? const SignInScreen()
              : const OnboardingGate(),
      data: (value) =>
          value == null ? const SignInScreen() : const OnboardingGate(),
    );
  }
}
