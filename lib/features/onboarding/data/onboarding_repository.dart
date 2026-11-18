import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/onboarding_result.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SupabaseOnboardingRepository(ref.watch(supabaseClientProvider));
});

/// `complete_onboarding` RPC'sinin gövdesi: tartı, rutinler ve ayar satırı.
Map<String, dynamic> onboardingPayload(OnboardingResult result) => {
      'weight_kg': result.weightKg,
      'routines': [for (final r in result.routines) r.toInsertMap()],
      'settings': result.settings.toMap(),
      if (result.timezone != null) 'timezone': result.timezone,
    };

/// İlk kurulumu sunucuda TEK transaction'da yazar. Aynı [opKey] ile tekrar
/// çağrı (yanıtı kaybolmuş ya da uygulama yeniden açılmış olsa da) ikinci kez
/// yazmaz; ilk başarılı çağrının ayar satırını döndürür.
abstract class OnboardingRepository {
  Future<UserSettings> complete(Map<String, dynamic> payload, String opKey);
}

class SupabaseOnboardingRepository implements OnboardingRepository {
  const SupabaseOnboardingRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserSettings> complete(
    Map<String, dynamic> payload,
    String opKey,
  ) async {
    final Object? response = await _client.rpc<Object?>(
      'complete_onboarding',
      params: {'payload': payload, 'op_key': opKey},
    );
    final settings = response is Map ? response['settings'] : null;
    if (settings is! Map) {
      throw StateError('complete_onboarding beklenmeyen yanıt döndürdü.');
    }
    return SettingsRepository.parseRow(Map<String, dynamic>.from(settings));
  }
}
