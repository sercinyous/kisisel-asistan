import '../../routines/domain/routine.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/onboarding_result.dart';

/// İlk kurulum sonucunu yazar: önce tartı kaydı, sonra seçilen rutinler,
/// EN SON tek `user_settings` kaydı (`onboarded_at` dolu). Ayar satırı yazılana
/// kadar kullanıcı kurulumu bitirmiş sayılmaz; önceki adımlar bir kez
/// başarılı olduktan sonra yeniden denemede tekrarlanmaz (çift tartı ya da
/// çift rutin olmasın).
class OnboardingWriter {
  OnboardingWriter({
    required this.addWeight,
    required this.createRoutine,
    required this.saveSettings,
  });

  final Future<void> Function(double weightKg) addWeight;
  final Future<void> Function(Routine routine) createRoutine;
  final Future<UserSettings> Function(UserSettings settings) saveSettings;

  bool _weightSaved = false;
  final Set<String> _savedRoutineTitles = {};

  /// Sonucu yazar ve kaydedilen ayar satırını döndürür. Hata çağırana iletilir;
  /// aynı [result] ile yeniden çağrılınca kalan adımlardan sürer.
  Future<UserSettings> complete(OnboardingResult result) async {
    if (!_weightSaved) {
      await addWeight(result.weightKg);
      _weightSaved = true;
    }
    for (final routine in result.routines) {
      // Başlık şablon içinde tekildir; yeniden denemede kaydedilen atlanır.
      if (_savedRoutineTitles.contains(routine.title)) continue;
      await createRoutine(routine);
      _savedRoutineTitles.add(routine.title);
    }
    return saveSettings(result.settings);
  }
}
