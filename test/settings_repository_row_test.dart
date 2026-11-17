import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

void main() {
  group('SettingsRepository.parseRow', () {
    test('onboarded_at boş (sütun var): kılavuz gösterilir', () {
      final s = SettingsRepository.parseRow(const {
        'user_id': 'u1',
        'onboarded_at': null,
        'updated_at': '2026-11-16T10:00:00+00:00',
      });
      expect(s.onboardedAt, isNull);
      expect(s.isOnboarded, isFalse);
    });

    test('onboarded_at dolu: kurulum bitmiş', () {
      final s = SettingsRepository.parseRow(const {
        'onboarded_at': '2026-11-17T09:30:00+00:00',
      });
      expect(s.isOnboarded, isTrue);
      expect(s.onboardedAt!.toUtc(), DateTime.utc(2026, 11, 17, 9, 30));
    });

    test('Faz 4B öncesi şema (sütun yok): mevcut hesap kılavuza zorlanmaz', () {
      final s = SettingsRepository.parseRow(const {
        'user_id': 'u1',
        'daily_calories': 2200,
        'updated_at': '2026-11-16T10:00:00+00:00',
      });
      expect(s.isOnboarded, isTrue);
      expect(s.onboardedAt!.toUtc(), DateTime.utc(2026, 11, 16, 10));
      expect(s.dailyCalories, 2200);
    });

    test('sütun yok ve updated_at da yok: yine bitmiş sayılır', () {
      expect(SettingsRepository.parseRow(const {}).isOnboarded, isTrue);
    });
  });
}
