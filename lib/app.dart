import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_scope.dart';
import 'core/theme/theme_mode.dart';
import 'features/auth/presentation/auth_gate.dart';

class KisiselAsistanApp extends ConsumerWidget {
  const KisiselAsistanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppThemeScope(
      mode: ref.watch(themeModeProvider),
      builder: _app,
    );
  }

  Widget _app(BuildContext context, ThemeData theme) {
    return MaterialApp(
      title: 'Ritim',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // AppColors anında değişir; tema da aynı karede geçsin.
      themeAnimationDuration: Duration.zero,
      // Tarih/saat seçiciler ve sistem metinleri Türkçe olsun.
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AuthGate(),
    );
  }
}

/// Zorunlu --dart-define anahtarları eksikse gösterilir.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({
    super.key,
    required this.missingKeys,
    this.themeMode = AppThemeMode.fallback,
  });

  final List<String> missingKeys;

  /// Cihazda saklanan görünüm tercihi (bu ekran ProviderScope'suz açılır).
  final AppThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(mode: themeMode, builder: _app);
  }

  Widget _app(BuildContext context, ThemeData theme) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.settings_suggest_rounded,
                    size: 40, color: AppColors.warning),
                const SizedBox(height: 16),
                const Text(
                  'Yapılandırma eksik',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Şu anahtarlar derlemeye verilmemiş:\n'
                  '${missingKeys.join('\n')}\n\n'
                  'Derlemeyi --dart-define-from-file=dart_defines.json ile yap.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
