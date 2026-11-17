import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';

/// Supabase Auth'a giriş çağrıları. Testler sahtesini verir.
abstract interface class SignInBackend {
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// Google kimlik belirteciyle giriş; ilk girişte hesap açılır ve kayıt kapısı
  /// davetsiz e-postayı reddeder ([AuthException]).
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  });
}

class SupabaseSignInBackend implements SignInBackend {
  SupabaseSignInBackend(this._auth);

  final GoTrueClient _auth;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }
}

final signInBackendProvider = Provider<SignInBackend>(
  (ref) => SupabaseSignInBackend(ref.watch(supabaseClientProvider).auth),
);
