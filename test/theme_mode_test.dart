import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/theme/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _brokenStore() async =>
    throw StateError('depo kullanılamıyor');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AppColors.palette = AppPalette.dark;
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  group('AppThemeMode', () {
    test('parse: bilinen adlar, yoksa koyu', () {
      expect(AppThemeMode.parse('system'), AppThemeMode.system);
      expect(AppThemeMode.parse('light'), AppThemeMode.light);
      expect(AppThemeMode.parse('dark'), AppThemeMode.dark);
      expect(AppThemeMode.parse(null), AppThemeMode.dark);
      expect(AppThemeMode.parse(''), AppThemeMode.dark);
      expect(AppThemeMode.parse('mavi'), AppThemeMode.dark);
    });

    test('resolve: sistem cihazı izler, diğerleri sabittir', () {
      for (final platform in Brightness.values) {
        expect(AppThemeMode.system.resolve(platform), platform);
        expect(AppThemeMode.light.resolve(platform), Brightness.light);
        expect(AppThemeMode.dark.resolve(platform), Brightness.dark);
      }
    });

    test('etiketler Türkçe', () {
      expect(
        [for (final mode in AppThemeMode.values) mode.label],
        ['Sistem', 'Açık', 'Koyu'],
      );
    });
  });

  group('ThemeModeStore', () {
    test('kayıt yokken koyu döner', () async {
      expect(await const ThemeModeStore().load(), AppThemeMode.dark);
    });

    test('kaydedilen tercih geri okunur', () async {
      const store = ThemeModeStore();
      await store.save(AppThemeMode.light);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeModeStore.key), 'light');
      expect(await store.load(), AppThemeMode.light);

      await store.save(AppThemeMode.system);
      expect(await store.load(), AppThemeMode.system);
    });

    test('tanınmayan ya da yanlış türde kayıt koyuya düşer', () async {
      SharedPreferences.setMockInitialValues({ThemeModeStore.key: 'mor'});
      expect(await const ThemeModeStore().load(), AppThemeMode.dark);

      SharedPreferences.setMockInitialValues({ThemeModeStore.key: 3});
      expect(await const ThemeModeStore().load(), AppThemeMode.dark);
    });

    test('depo hata verirse okuma koyu döner, yazma hata fırlatmaz', () async {
      const store = ThemeModeStore(open: _brokenStore);
      expect(await store.load(), AppThemeMode.dark);
      await expectLater(store.save(AppThemeMode.light), completes);
    });

    testWidgets('depo yanıt vermezse açılış kilitlenmez', (tester) async {
      final store = ThemeModeStore(
        open: () => Completer<SharedPreferences>().future,
      );
      AppThemeMode? loaded;
      var saved = false;
      unawaited(store.load().then((mode) => loaded = mode));
      unawaited(store.save(AppThemeMode.light).then((_) => saved = true));

      await tester.pump(
        ThemeModeStore.timeout - const Duration(milliseconds: 1),
      );
      expect(loaded, isNull);
      await tester.pump(const Duration(milliseconds: 2));
      expect(loaded, AppThemeMode.dark);
      expect(saved, isTrue);
    });
  });

  group('themeModeProvider', () {
    test('varsayılan koyu', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), AppThemeMode.dark);
    });

    test('açılışta okunan tercihle başlar', () {
      final container = ProviderContainer(
        overrides: [
          initialThemeModeProvider.overrideWithValue(AppThemeMode.light),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), AppThemeMode.light);
    });

    test('select hemen uygular ve cihaza yazar', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = <AppThemeMode>[];
      container.listen(themeModeProvider, (_, next) => seen.add(next));

      final write = container
          .read(themeModeProvider.notifier)
          .select(AppThemeMode.light);
      expect(container.read(themeModeProvider), AppThemeMode.light,
          reason: 'yazma beklenmeden uygulanır');
      await write;

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeModeStore.key), 'light');
      expect(seen, [AppThemeMode.light]);

      // Aynı tercih yeniden seçilirse dinleyiciler boşuna uyarılmaz.
      await container
          .read(themeModeProvider.notifier)
          .select(AppThemeMode.light);
      expect(seen, [AppThemeMode.light]);
    });

    test('depo bozukken de tercih bu oturumda değişir', () async {
      final container = ProviderContainer(
        overrides: [
          themeModeStoreProvider
              .overrideWithValue(const ThemeModeStore(open: _brokenStore)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(themeModeProvider.notifier)
          .select(AppThemeMode.system);
      expect(container.read(themeModeProvider), AppThemeMode.system);
    });
  });

  group('loadInitialThemeMode', () {
    test('saklanan açık tercih paleti ilk kareden önce etkinleştirir',
        () async {
      SharedPreferences.setMockInitialValues({ThemeModeStore.key: 'light'});

      expect(await loadInitialThemeMode(), AppThemeMode.light);
      expect(AppColors.palette, same(AppPalette.light));
    });

    test('sistem tercihi cihazın parlaklığına göre çözülür', () async {
      SharedPreferences.setMockInitialValues({ThemeModeStore.key: 'system'});

      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      expect(await loadInitialThemeMode(), AppThemeMode.system);
      expect(AppColors.palette, same(AppPalette.light));

      binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      expect(await loadInitialThemeMode(), AppThemeMode.system);
      expect(AppColors.palette, same(AppPalette.dark));
    });

    test('depo bozuksa koyu temayla açılır', () async {
      AppColors.palette = AppPalette.light;

      final mode = await loadInitialThemeMode(
        store: const ThemeModeStore(open: _brokenStore),
      );
      expect(mode, AppThemeMode.dark);
      expect(AppColors.palette, same(AppPalette.dark));
    });
  });
}
