import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/google_auth.dart';
import '../data/google_identity_client.dart';
import '../data/sign_in_backend.dart';
import '../domain/sign_in_messages.dart';

enum SignInMethod { google, password }

class SignInState {
  const SignInState({this.busy, this.error});

  /// Süren giriş yöntemi; boşta `null`.
  final SignInMethod? busy;

  /// Son denemenin Türkçe hata metni; vazgeçme ve başarıda `null`.
  final String? error;

  bool get isBusy => busy != null;
}

final googleIdentityClientProvider = Provider<GoogleIdentityClient>(
  (ref) => GoogleSignInIdentityClient(ref.watch(googleSignInHostProvider)),
);

/// Google ile giriş bu derlemede sunulur mu? iOS ve Web istemci kimliklerinin
/// ikisi de gerekir; tarayıcı demosunda gizlidir.
final googleLoginAvailableProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      ref.watch(googleClientIdProvider).isNotEmpty &&
      ref.watch(googleServerClientIdProvider).isNotEmpty,
);

/// Giriş ekranının mantığı: Google ve e-posta/şifre girişi, tek seferde bir
/// deneme, hataların Türkçe metne çevrilmesi. Başarıda oturum Supabase'ten
/// gelir ([authSessionProvider]); ekran değişimini kapı yapar.
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// Başarıda `true`.
  Future<bool> signInWithGoogle() => _run(SignInMethod.google, () async {
        final identity = await ref.read(googleIdentityClientProvider).signIn();
        await ref.read(signInBackendProvider).signInWithGoogleIdToken(
              idToken: identity.idToken,
              accessToken: identity.accessToken,
            );
      });

  /// Başarıda `true`.
  Future<bool> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _run(SignInMethod.password, () async {
        await ref.read(signInBackendProvider).signInWithPassword(
              email: email.trim(),
              password: password,
            );
      });

  Future<bool> _run(SignInMethod method, Future<void> Function() action) async {
    if (state.isBusy) return false;
    state = SignInState(busy: method);
    try {
      await action();
      state = const SignInState();
      return true;
    } catch (error) {
      state = SignInState(error: signInErrorMessage(error));
      return false;
    }
  }
}

final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);
