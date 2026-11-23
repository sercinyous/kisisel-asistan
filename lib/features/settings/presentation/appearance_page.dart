import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode.dart';
import 'settings_widgets.dart';

/// Hesap › Görünüm: Sistem / Açık / Koyu. Cihaza özgüdür; seçilir seçilmez
/// uygulanır, Supabase'e yazılmaz.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Görünüm')),
      body: ListView(
        padding: settingsListPadding,
        children: const [AppearanceCard()],
      ),
    );
  }
}

/// Tema seçici kartı.
class AppearanceCard extends ConsumerWidget {
  const AppearanceCard({super.key});

  static IconData _icon(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => Icons.brightness_auto_outlined,
        AppThemeMode.light => Icons.light_mode_outlined,
        AppThemeMode.dark => Icons.dark_mode_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SettingsSection(
      icon: Icons.palette_outlined,
      title: 'Tema',
      color: AppColors.warning,
      children: [
        SegmentedButton<AppThemeMode>(
          key: const Key('settings-theme-mode'),
          showSelectedIcon: false,
          segments: [
            for (final option in AppThemeMode.values)
              ButtonSegment(
                value: option,
                label: Text(option.label),
                icon: Icon(_icon(option)),
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              ref.read(themeModeProvider.notifier).select(selection.first),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textSecondary,
            selectedBackgroundColor: AppColors.selection,
            selectedForegroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.segment),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const SettingsHint('Sistem, iPhone\'un açık/koyu ayarını izler.'),
      ],
    );
  }
}
