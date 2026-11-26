import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/secure_session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Mem implements SecureKeyValue {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  const key = 'sb-proje-auth-token';

  test('anahtar supabase_flutter varsayılanıyla aynı', () {
    expect(SecureSessionStorage.keyFor('https://proje.supabase.co'), key);
  });

  test('eski oturum Anahtar Zinciri\'ne taşınır, eski kayıt silinir',
      () async {
    SharedPreferences.setMockInitialValues({key: '{"oturum":1}'});
    final mem = _Mem();
    final storage = SecureSessionStorage(persistSessionKey: key, store: mem);
    await storage.initialize();

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), '{"oturum":1}');
    expect(mem.data[key], '{"oturum":1}');
    expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
  });

  test('Anahtar Zinciri\'ndeki yeni oturum eskisiyle ezilmez', () async {
    SharedPreferences.setMockInitialValues({key: 'eski'});
    final mem = _Mem()..data[key] = 'yeni';
    final storage = SecureSessionStorage(persistSessionKey: key, store: mem);
    await storage.initialize();
    expect(await storage.accessToken(), 'yeni');
    expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
  });

  test('kaydet ve sil', () async {
    SharedPreferences.setMockInitialValues({});
    final mem = _Mem();
    final storage = SecureSessionStorage(persistSessionKey: key, store: mem);
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
    await storage.persistSession('s');
    expect(mem.data[key], 's');
    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(mem.data, isEmpty);
  });
}
