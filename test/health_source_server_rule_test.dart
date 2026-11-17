import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/google_auth.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart';

// Sunucu (report_period_metrics, friend_leaderboard) ile grafik aynı kaynak
// kuralını kullanır: kaynağı boş satır Apple Health sayılır, yalnızca seçili
// kaynağın satırı okunur (supabase/tests/friend_scope_test.sql ile eş).
void main() {
  group('kaynak kuralı', () {
    test('boş kaynak Apple sayılır', () {
      expect(HealthRepository.rowMatchesSource(null, HealthSourceKind.appleHealth),
          isTrue);
      expect(HealthRepository.rowMatchesSource(null, HealthSourceKind.googleHealth),
          isFalse);
      expect(
          HealthRepository.rowMatchesSource(
              'googleHealth', HealthSourceKind.googleHealth),
          isTrue);
      expect(
          HealthRepository.rowMatchesSource(
              'googleHealth', HealthSourceKind.appleHealth),
          isFalse);
      expect(HealthRepository.sourceFilter(HealthSourceKind.appleHealth),
          'source.eq.appleHealth,source.is.null');
      expect(HealthRepository.sourceFilter(HealthSourceKind.googleHealth),
          'source.eq.googleHealth');
    });
  });

  group('grafik sağlayıcısı sunucuyla aynı kuralı kullanır', () {
    ProviderContainer make(FakeHealthRepository health, HealthSourceKind kind) {
      final c = ProviderContainer(overrides: [
        healthRepositoryProvider.overrideWithValue(health),
        googleClientIdProvider.overrideWithValue('123-abc.apps.googleusercontent.com'),
        initialHealthSourceProvider.overrideWithValue(kind),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    FakeHealthRepository appleDay() {
      final today = AppDates.startOfDay(DateTime.now());
      // Kaynağı boş (eski HealthKit) satır: Apple Health verisi.
      return FakeHealthRepository(
        metrics: [DailyHealthMetric(day: today, steps: 9000, sleepMinutes: 480)],
      );
    }

    test('Apple verisi var, Google seçili ve Google verisi yok: adım 0',
        () async {
      final c = make(appleDay(), HealthSourceKind.googleHealth);
      final week = await c.read(weekStepsProvider.future);
      expect(week.last.steps, 0);
      expect(averageSteps(week), isNull);
    });

    test('Apple seçili: kaynağı boş satır sayılır', () async {
      final c = make(appleDay(), HealthSourceKind.appleHealth);
      final week = await c.read(weekStepsProvider.future);
      expect(week.last.steps, 9000);
    });

    test('seçili kaynak sunucuya yazılır', () async {
      final health = appleDay();
      final c = make(health, HealthSourceKind.googleHealth);
      pushHealthSourceToServer(c);
      await Future<void>.delayed(Duration.zero);
      expect(health.savedHealthSource, HealthSourceKind.googleHealth);
    });
  });
}
