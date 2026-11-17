import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../onboarding/presentation/onboarding_gate.dart';
import 'sign_in_screen.dart';

/// Oturum varsa ilk kurulum kapısını (bitmişse ana kabuk), yoksa giriş ekranını
/// gösterir.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return session.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
