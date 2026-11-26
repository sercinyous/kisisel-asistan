import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer make(FakeNotificationService fake, UserSettings s) {
    final c = ProviderContainer(overrides: [
      authSessionProvider.overrideWith(
        (ref) => Stream.value(
          Session(
            accessToken: 't',
            tokenType: 'bearer',
            user: const User(
              id: 'u',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01T00:00:00Z',
            ),
          ),
        ),
      ),
      notificationServiceProvider.overrideWithValue(fake),
      settingsRepositoryProvider
          .overrideWithValue(FakeSettingsRepository()..settings = s),
      healthNudgeStateProvider.overrideWith(
        (ref) async => const HealthNudgeState(mealsLoggedToday: false),
      ),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('önce eski sağlık anahtarlarını siler, sonra planı yazar', () async {
    final fake = FakeNotificationService();
    final c = make(
      fake,
      const UserSettings.defaults().copyWith(quietHoursEnabled: false),
    );
    await c.read(healthNudgeSyncProvider.future);

    expect(fake.cancelled, hasLength(8 * HealthNudgeKind.values.length));
    expect(fake.cancelled.every((k) => k.startsWith('health:')), isTrue);
    expect(fake.scheduled, isNotEmpty);
    expect(fake.scheduled.every((r) => r.taskId.startsWith('health:')), isTrue);
    final perDay = <String, int>{};
    for (final r in fake.scheduled) {
      final day = r.taskId.split(':').last;
      perDay[day] = (perDay[day] ?? 0) + 1;
    }
    expect(perDay.values.every((n) => n <= maxHealthNudgesPerDay), isTrue);
    expect(fake.permissionRequests, 0, reason: 'izin penceresi açmaz');
  });

  test('izin yoksa ya da bildirimler kapalıysa yalnızca siler', () async {
    final noPermission = FakeNotificationService(permissionGranted: false);
    await make(noPermission, const UserSettings.defaults())
        .read(healthNudgeSyncProvider.future);
    expect(noPermission.scheduled, isEmpty);
    expect(noPermission.cancelled, isNotEmpty);

    final off = FakeNotificationService();
    await make(
      off,
      const UserSettings.defaults().copyWith(notificationsEnabled: false),
    ).read(healthNudgeSyncProvider.future);
    expect(off.scheduled, isEmpty);
  });

  test('kapatılan tür cihazda saklanır ve planlanmaz', () async {
    final fake = FakeNotificationService();
    final c = make(
      fake,
      const UserSettings.defaults()
          .copyWith(quietHoursEnabled: false, checkinReminder: false),
    );
    await c.read(healthNudgePrefsProvider.future);
    await c
        .read(healthNudgePrefsProvider.notifier)
        .setEnabled(HealthNudgeKind.meals, false);
    await c.read(healthNudgeSyncProvider.future);
    expect(fake.scheduled.where((r) => r.taskId.contains('meals')), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HealthNudgePrefs.prefsKey), ['meals']);
  });
}
