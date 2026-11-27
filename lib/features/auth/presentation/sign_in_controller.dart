import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/apple_auth.dart';
import '../../../core/services/google_auth.dart';
import '../data/google_identity_client.dart';
import '../data/sign_in_backend.dart';
import '../domain/sign_in_messages.dart';

enum SignInMethod { apple, google, password }

class SignInState {
  const SignInState({this.busy, this.error, this.info});

  /// Süren giriş yöntemi; boşta `null`.
  final SignInMethod? busy;

  /// Son denemenin Türkçe hata metni; vazgeçme ve başarıda `null`.
  final String? error;

  /// Başarılı ama ek adım gereken sonucun bilgi metni (ör. onay e-postası).
  final String? info;

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

/// Giriş ekranının mantığı: Apple, Google ve e-posta/şifre girişi, e-posta kaydı, tek seferde bir
/// deneme, hataların Türkçe metne çevrilmesi. Başarıda oturum Supabase'ten
/// gelir ([authSessionProvider]); ekran değişimini kapı yapar.
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// Giriş/kayıt arasında geçişte eski hata ve bilgi metnini siler.
  void clearMessages() {
    if (state.isBusy) return;
    state = const SignInState();
  }

  /// Başarıda `true`. Vazgeçmede `false`, hata metni gösterilmez.
  Future<bool> signInWithApple() => _run(SignInMethod.apple, () async {
        final credential = await ref.read(appleIdentityClientProvider).signIn();
        await ref.read(signInBackendProvider).signInWithAppleIdToken(
              idToken: credential.idToken,
              rawNonce: credential.rawNonce,
              fullName: credential.fullName,
            );
        return null;
      });

  /// Başarıda `true`.
  Future<bool> signInWithGoogle() => _run(SignInMethod.google, () async {
        final identity = await ref.read(googleIdentityClientProvider).signIn();
        await ref.read(signInBackendProvider).signInWithGoogleIdToken(
              idToken: identity.idToken,
              accessToken: identity.accessToken,
            );
        return null;
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
        return null;
      });

  /// Yeni e-posta hesabı açar. Başarıda `true`; e-posta onayı gerekiyorsa
  /// [SignInState.info] onay metnini taşır.
  Future<bool> signUpWithPassword({
    required String email,
    required String password,
  }) =>
      _run(SignInMethod.password, () async {
        final signedIn =
            await ref.read(signInBackendProvider).signUpWithPassword(
                  email: email.trim(),
                  password: password,
                );
        return signedIn ? null : confirmationSentMessage;
      });

  Future<bool> _run(
    SignInMethod method,
    Future<String?> Function() action,
  ) async {
    if (state.isBusy) return false;
    state = SignInState(busy: method);
    try {
      final info = await action();
      state = SignInState(info: info);
      return true;
    } catch (error) {
      state = SignInState(error: signInErrorMessage(error));
      return false;
    }
  }
}

final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);
