import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `Supabase.initialize` main() içinde çağrıldıktan sonra kullanılabilir.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Oturum değişikliklerini yayınlar; ilk değer mevcut oturumdur.
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client.auth.currentSession;
  // Token yenileme hataları (çevrimdışı vb.) oturum değişikliği değildir;
  // oturum gerçekten bittiğinde gotrue ayrıca signedOut olayı yayınlar.
  // Hata akışı sonlandırırsa sağlayıcı kalıcı olarak ölür, bu yüzden yutulur.
  yield* client.auth.onAuthStateChange
      .handleError((Object _, StackTrace __) {})
      .map((state) => state.session);
});
