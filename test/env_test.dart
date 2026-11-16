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
}
