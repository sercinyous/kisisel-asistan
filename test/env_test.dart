import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/config/env.dart';

void main() {
  group('normalizeSupabaseUrl', () {
    const origin = 'https://abcd1234.supabase.co';

    test('doğru adres olduğu gibi kalır', () {
      expect(normalizeSupabaseUrl(origin), origin);
    });

    test('panelde gösterilen yol ve sondaki eğik çizgi atılır', () {
      for (final raw in [
        '$origin/',
        '$origin/rest/v1',
        '$origin/rest/v1/',
        '$origin/auth/v1/',
        '  $origin/rest/v1/?apikey=x  ',
      ]) {
        expect(normalizeSupabaseUrl(raw), origin, reason: raw);
      }
    });

    test('şemasız yazılan adrese https eklenir', () {
      expect(normalizeSupabaseUrl('abcd1234.supabase.co/rest/v1'), origin);
    });

    test('özel alan adı ve port korunur', () {
      expect(
        normalizeSupabaseUrl('https://api.ornek.com:8443/rest/v1/'),
        'https://api.ornek.com:8443',
      );
      expect(
        normalizeSupabaseUrl('http://127.0.0.1:54321/'),
        'http://127.0.0.1:54321',
      );
    });

    test('boş girdi boş kalır', () {
      expect(normalizeSupabaseUrl(''), '');
      expect(normalizeSupabaseUrl('   '), '');
    });
  });

  group('Google iOS istemci kimliği', () {
    const id = '123456789012-abcdefghij0123456789klmnopqrstuv.apps.googleusercontent.com';

    test('geçerli kimlik kırpılarak kabul edilir', () {
      expect(normalizeGoogleClientId(id), id);
      expect(normalizeGoogleClientId('  $id\n'), id);
    });

    test('boş ya da biçimi bozuk kimlik boş metne döner', () {
      for (final raw in [
        '',
        '   ',
        'abc.apps.googleusercontent.com',
        '123456789012-abc',
        '123456789012-ABC.apps.googleusercontent.com',
        'https://$id',
      ]) {
        expect(normalizeGoogleClientId(raw), '', reason: raw);
      }
    });

    test('ters kimlik URL şeması olarak üretilir', () {
      expect(
        reversedGoogleClientId(id),
        'com.googleusercontent.apps.123456789012-abcdefghij0123456789klmnopqrstuv',
      );
      expect(reversedGoogleClientId('geçersiz'), '');
    });

    test('derlemede verilmediğinde Google kapalıdır', () {
      expect(Env.googleIosClientId, '');
      expect(Env.missingKeys, isNot(contains('GOOGLE_IOS_CLIENT_ID')));
    });
  });
}
