import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/settings/data/account_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('cihaz temizliği yalnızca o kullanıcının anahtarlarını siler', () async {
    SharedPreferences.setMockInitialValues({
      'health_source:u1': 'googleHealth',
      'apple_health_consent:u1': true,
      'onboarding_op_key:u1': 'k',
      'health_source:u2': 'appleHealth',
      'recent_food_ids': <String>['a'],
      'theme_mode': 'dark',
    });
    final repo = AccountRepository(SupabaseClient('http://localhost', 'anon'));
    await repo.clearLocalData('u1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'health_source:u2', 'theme_mode'});
  });
}
