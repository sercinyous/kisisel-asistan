import 'package:flutter/widgets.dart';

import 'hesap_screen.dart';

export 'settings_widgets.dart' show SettingsLimits;

/// Eski giriş noktası: Ayarlar artık Hesap menüsüdür. Var olan gezinmeler
/// bozulmasın diye aynı menüyü açar.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const HesapScreen();
}
