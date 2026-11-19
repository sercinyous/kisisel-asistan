import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Görünüm tercihi. Cihazda saklanır; Supabase'e yazılmaz.
enum AppThemeMode {
  system('Sistem'),
  light('Açık'),
  dark('Koyu');

  const AppThemeMode(this.label);

  final String label;

  /// Kayıt yoksa ya da okunamazsa kullanılan tercih.
  static const AppThemeMode fallback = AppThemeMode.dark;

  /// Saklanan metni tercihe çevirir; tanınmayan değer [fallback] olur.
  static AppThemeMode parse(String? raw) {
    for (final mode in values) {
      if (mode.name == raw) return mode;
    }
    return fallback;
  }

  /// Etkin parlaklık; [system] cihazın ayarını izler.
  Brightness resolve(Brightness platform) => switch (this) {
        AppThemeMode.system => platform,
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };
}

/// Tercihi cihazda saklar. Depo hata verir ya da yanıt vermezse (ör. tarayıcı
/// korumalı alanı) okuma [AppThemeMode.fallback] döner, yazma sessizce atlanır.
class ThemeModeStore {
  const ThemeModeStore({this.open = SharedPreferences.getInstance});

  static const String key = 'theme_mode';

  /// Açılışı kilitlememesi için depoya en fazla bu kadar beklenir.
  static const Duration timeout = Duration(seconds: 2);

  /// Depoyu açar; testlerde hatalı depo denemek için değiştirilebilir.
  final Future<SharedPreferences> Function() open;

  Future<AppThemeMode> load() async {
    try {
      final prefs = await open().timeout(timeout);
      return AppThemeMode.parse(prefs.getString(key));
    } catch (_) {
      return AppThemeMode.fallback;
    }
  }

  Future<void> save(AppThemeMode mode) async {
    try {
      final prefs = await open().timeout(timeout);
      await prefs.setString(key, mode.name).timeout(timeout);
    } catch (_) {
      // Yazılamazsa tercih yalnızca bu oturumda geçerli kalır.
    }
  }
}

final themeModeStoreProvider =
    Provider<ThemeModeStore>((ref) => const ThemeModeStore());

/// Açılış tercihi. `main()` içinde [loadInitialThemeMode] sonucuyla ezilir.
final initialThemeModeProvider =
    Provider<AppThemeMode>((ref) => AppThemeMode.fallback);

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => ref.watch(initialThemeModeProvider);

  /// Hemen uygulanır, ardından cihaza yazılır.
  Future<void> select(AppThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await ref.read(themeModeStoreProvider).save(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, AppThemeMode>(
  ThemeModeController.new,
);

/// `runApp` öncesinde çağrılır: saklanan tercihi okur ve paleti etkinleştirir,
/// böylece ilk kare doğru temayla çizilir (koyudan açığa sıçrama olmaz).
Future<AppThemeMode> loadInitialThemeMode({
  ThemeModeStore store = const ThemeModeStore(),
}) async {
  final mode = await store.load();
  AppColors.palette = AppPalette.of(
    mode.resolve(WidgetsBinding.instance.platformDispatcher.platformBrightness),
  );
  return mode;
}
