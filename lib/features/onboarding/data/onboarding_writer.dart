import '../../settings/domain/user_settings.dart';
import '../domain/onboarding_result.dart';
import 'onboarding_op_key_store.dart';
import 'onboarding_repository.dart';

/// İlk kurulum sonucunu tek sunucu çağrısıyla yazar (tartı, rutinler ve
/// `onboarded_at` dolu ayar satırı aynı transaction'da). İşlem anahtarı
/// başarıya dek cihazda saklanır: yarıda kalan deneme, uygulama yeniden
/// açılsa ya da sunucu yazıp yanıt kaybolsa bile çift kayıt üretmez.
class OnboardingWriter {
  OnboardingWriter({required this.repository, required this.keys});

  final OnboardingRepository repository;
  final OnboardingOpKeyStore keys;

  /// Sonucu yazar ve kaydedilen ayar satırını döndürür. Hata çağırana iletilir;
  /// yeniden çağrı aynı anahtarı kullanır.
  Future<UserSettings> complete(OnboardingResult result) async {
    final opKey = await keys.obtain();
    final saved = await repository.complete(onboardingPayload(result), opKey);
    await keys.clear();
    return saved;
  }
}
