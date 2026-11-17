// Bağımsız inceleme #5: yarım kalan ilk kurulum uygulama yeniden açıldıktan
// sonra tekrarlanınca tartı/rutin çiftlenmemeli (sunucuda tek transaction +
// cihazda saklanan işlem anahtarı).
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_op_key_store.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_repository.dart';
import 'package:kisisel_asistan/features/onboarding/data/onboarding_writer.dart';
import 'package:kisisel_asistan/features/onboarding/domain/onboarding_result.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `complete_onboarding`'in sunucu davranışı: tek transaction, anahtar başına
/// bir kez. [failBeforeCommit] işlemi geri alır; [loseResponseAfterCommit]
/// yazar ama yanıt istemciye ulaşmaz.
class _Server implements OnboardingRepository {
  int weightRows = 0;
  final Map<String, UserSettings> done = {};
  bool failBeforeCommit = false;
  bool loseResponseAfterCommit = false;

  @override
  Future<UserSettings> complete(
    Map<String, dynamic> payload,
    String opKey,
  ) async {
    final replay = done[opKey];
    if (replay != null) return replay;
    if (failBeforeCommit) {
      failBeforeCommit = false;
      throw StateError('network failure');
    }
    weightRows++;
    final saved = UserSettings.fromMap(
      Map<String, dynamic>.from(payload['settings'] as Map),
    );
    done[opKey] = saved;
    if (loseResponseAfterCommit) {
      loseResponseAfterCommit = false;
      throw StateError('response lost');
    }
    return saved;
  }
}

void main() {
  const result = OnboardingResult(
    settings: UserSettings.defaults(),
    routines: [],
    weightKg: 80,
  );

  // Her "uygulama açılışı" yeni writer ve yeni anahtar deposu nesnesi kurar;
  // yalnızca SharedPreferences (cihaz) ortaktır.
  OnboardingWriter freshApp(_Server server) => OnboardingWriter(
        repository: server,
        keys: OnboardingOpKeyStore(scope: 'user-1'),
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('writer yeniden kurulsa da (uygulama yeniden açıldı) başarısız ilk '
      'denemeden sonra tek tartı yazılır', () async {
    final server = _Server()..failBeforeCommit = true;
    await expectLater(freshApp(server).complete(result), throwsStateError);
    await freshApp(server).complete(result);
    expect(server.weightRows, 1);
  });

  test('sunucu yazıp yanıt kaybolursa yeniden açılışta aynı anahtar '
      'gönderilir ve tartı çiftlenmez', () async {
    final server = _Server()..loseResponseAfterCommit = true;
    await expectLater(freshApp(server).complete(result), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('onboarding_op_key:user-1'), isNotNull,
        reason: 'anahtar başarıya dek cihazda kalır');

    final saved = await freshApp(server).complete(result);
    expect(server.weightRows, 1);
    expect(saved.startWeightKg, result.settings.startWeightKg);
    expect(prefs.getString('onboarding_op_key:user-1'), isNull,
        reason: 'başarıdan sonra anahtar silinir');
  });

  test('anahtar kullanıcıya bağlıdır: başka hesap aynı anahtarı almaz',
      () async {
    final a = await OnboardingOpKeyStore(scope: 'a').obtain();
    final b = await OnboardingOpKeyStore(scope: 'b').obtain();
    expect(a, isNot(b));
    expect(await OnboardingOpKeyStore(scope: 'a').obtain(), a);
  });
}
