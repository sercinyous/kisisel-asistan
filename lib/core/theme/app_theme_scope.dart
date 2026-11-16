import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'theme_mode.dart';

/// Uygulamanın kökünde durur: görünüm tercihini ve cihazın açık/koyu ayarını
/// etkin palete çevirir, [builder]'a o paletin [ThemeData]'sını verir.
///
/// Palet değişince alt ağaçtaki **her** öğe yeniden kurulur ve boyanır;
/// `const` kurulmuş ve `Theme.of` çağırmayan bileşenler de yeni renkleri alır.
/// Öğeler yerinde kaldığı için gezinme yığını, kaydırma konumu ve form
/// durumu korunur.
class AppThemeScope extends StatefulWidget {
  const AppThemeScope({super.key, required this.mode, required this.builder});

  final AppThemeMode mode;
  final Widget Function(BuildContext context, ThemeData theme) builder;

  @override
  State<AppThemeScope> createState() => _AppThemeScopeState();
}

class _AppThemeScopeState extends State<AppThemeScope> {
  /// [root] altındaki tüm öğeleri yeniden kurulacak ve boyanacak diye işaretler.
  static void _refreshSubtree(Element root) {
    void visit(Element element) {
      element.markNeedsBuild();
      if (element is RenderObjectElement) {
        element.renderObject.markNeedsPaint();
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    // Cihaz ayarı değişince MediaQuery bu build'i yeniden çalıştırır.
    final platform = MediaQuery.maybePlatformBrightnessOf(context) ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final palette = AppPalette.of(widget.mode.resolve(platform));

    if (!identical(AppColors.palette, palette)) {
      AppColors.palette = palette;
      // Çerçeve üstten alta kurduğu için, kurulmakta olan bir öğenin
      // torunlarını bu aşamada işaretlemek güvenlidir: hepsi aynı karede
      // yeni paletle kurulur, ekranda karışık renkli kare oluşmaz.
      _refreshSubtree(context as Element);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.overlayStyle,
      child: widget.builder(context, AppTheme.of(palette)),
    );
  }
}
