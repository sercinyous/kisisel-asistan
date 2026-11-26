import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/data/timezone_sync.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSettingsRepository settings;
  late ProviderContainer container;

  setUp(() {
    settings = FakeSettingsRepository(settings: const UserSettings.defaults());
    container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
    ]);
  });
  tearDown(() => container.dispose());

  test('cihaz dilimi farklıysa sunucuya yazılır (ICG2-06)', () async {
    await syncDeviceTimezone(container,
        readDeviceTimezone: () async => 'America/New_York');
    expect(settings.timezone, 'America/New_York');
  });

  test('geçersiz ad yazılmaz; eklenti hatası sessizce yutulur', () async {
    await syncDeviceTimezone(container, readDeviceTimezone: () async => '');
    await syncDeviceTimezone(container,
        readDeviceTimezone: () async => 'GMT+03:00 bozuk');
    await syncDeviceTimezone(container,
        readDeviceTimezone: () async => throw StateError('eklenti yok'));
    expect(settings.timezone, 'Europe/Istanbul');
  });
}
