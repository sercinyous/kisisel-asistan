import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bir temanın tüm renk rolleri. İki sabit örneği vardır: [dark] ve [light].
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.ops,
    required this.fitness,
    required this.nutrition,
    required this.warning,
    required this.danger,
    required this.onAccent,
    required this.onPrimary,
    required this.onSecondary,
    required this.onError,
    required this.controlOutline,
    required this.controlOutlineSoft,
    required this.controlContent,
    required this.controlFill,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.scrim,
    required this.shadow,
    required this.glass,
    required this.glassBorder,
    required this.navSelected,
  });

  final Brightness brightness;

  /// Sayfa zemini.
  final Color background;

  /// Kart zemini.
  final Color surface;

  /// Kart üstü katman: giriş alanı, çubuk izi, seçili bölme.
  final Color surfaceHigh;

  /// İnce kenarlık ve ayraç.
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color accent; // ana vurgu
  final Color ops; // operasyon
  final Color fitness; // spor
  final Color nutrition; // beslenme
  final Color warning;
  final Color danger;

  /// Vurgu rengiyle dolu zemin üstündeki işaret/ikon.
  final Color onAccent;

  /// Dolu buton yazıları (ColorScheme.onPrimary / onSecondary / onError).
  final Color onPrimary;
  final Color onSecondary;
  final Color onError;

  // Material kontrollerinin ColorScheme üzerinden aldığı roller. Koyu
  // değerler, bu roller verilmeden önce Material'in türettiği renklerdir.

  /// Anahtar topuzu ve bölmeli buton kenarı (ColorScheme.outline).
  final Color controlOutline;

  /// Çip kenarlığı (ColorScheme.outlineVariant).
  final Color controlOutlineSoft;

  /// Etiket, ikon ve onay kutusu kenarı (ColorScheme.onSurfaceVariant).
  final Color controlContent;

  /// Kapalı anahtar izi ve saat kadranı (ColorScheme.surfaceContainerHighest).
  final Color controlFill;

  /// Sayfanın üstünde yüzen balonlar: bildirim çubuğu, grafik ipucu.
  /// Açık temada koyu zemin + beyaz yazı (ters yüzey).
  final Color inverseSurface;
  final Color onInverseSurface;

  /// Alt sayfaların arkasındaki karartma.
  final Color scrim;

  /// Yüzen öğelerin gölgesi.
  final Color shadow;

  /// Alt barın yarı saydam cam dolgusu ve kenarlığı.
  final Color glass;
  final Color glassBorder;

  /// Alt barda seçili sekmenin arkasındaki kapsül.
  final Color navSelected;

  bool get isDark => brightness == Brightness.dark;

  /// Durum çubuğu ikonları: koyu temada açık, açık temada koyu.
  SystemUiOverlayStyle get overlayStyle =>
      (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent);

  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Saf OLED siyah (varsayılan).
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF0E0E10),
    surfaceHigh: Color(0xFF18181B),
    border: Color(0xFF222226),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFFA1A1AA),
    textMuted: Color(0xFF71717A),
    accent: Color(0xFF5EEAD4), // mint
    ops: Color(0xFF7AA7FF),
    fitness: Color(0xFFFF8A65),
    nutrition: Color(0xFFB9F27C),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFF6B6B),
    onAccent: Color(0xFF000000),
    onPrimary: Color(0xFF04201B),
    onSecondary: Color(0xFF07142E),
    onError: Color(0xFF2B0606),
    controlOutline: Color(0xFF222226),
    controlOutlineSoft: Color(0xFFFFFFFF),
    controlContent: Color(0xFFF2F4F8),
    controlFill: Color(0xFF0E0E10),
    inverseSurface: Color(0xFF18181B),
    onInverseSurface: Color(0xFFF2F4F8),
    scrim: Color.from(alpha: 0.6, red: 0, green: 0, blue: 0),
    shadow: Color.from(alpha: 0.35, red: 0, green: 0, blue: 0),
    // surfaceHigh %72
    glass: Color.from(
      alpha: 0.72,
      red: 0x18 / 255,
      green: 0x18 / 255,
      blue: 0x1B / 255,
    ),
    // textPrimary %14 ve %16
    glassBorder: Color.from(
      alpha: 0.14,
      red: 0xF2 / 255,
      green: 0xF4 / 255,
      blue: 0xF8 / 255,
    ),
    navSelected: Color.from(
      alpha: 0.16,
      red: 0xF2 / 255,
      green: 0xF4 / 255,
      blue: 0xF8 / 255,
    ),
  );

  /// Beyaz tema: beyaz sayfa, açık gri kartlar, beyazda okunan koyu vurgular.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F6),
    surfaceHigh: Color(0xFFE7E7EC),
    border: Color(0xFFE0E0E6),
    textPrimary: Color(0xFF0B0B0F),
    textSecondary: Color(0xFF4E4E57),
    textMuted: Color(0xFF696974),
    accent: Color(0xFF0E736B), // koyu turkuaz
    ops: Color(0xFF1D5BD6),
    fitness: Color(0xFFB83D00),
    nutrition: Color(0xFF41740E),
    warning: Color(0xFF985700),
    danger: Color(0xFFC81E28),
    onAccent: Color(0xFFFFFFFF),
    onPrimary: Color(0xFFFFFFFF),
    onSecondary: Color(0xFFFFFFFF),
    onError: Color(0xFFFFFFFF),
    controlOutline: Color(0xFF8A8A96),
    controlOutlineSoft: Color(0xFFC6C6CE),
    controlContent: Color(0xFF4E4E57),
    controlFill: Color(0xFFE7E7EC),
    inverseSurface: Color(0xFF1F1F24),
    onInverseSurface: Color(0xFFFFFFFF),
    scrim: Color.from(alpha: 0.32, red: 0, green: 0, blue: 0),
    shadow: Color.from(alpha: 0.12, red: 0, green: 0, blue: 0),
    glass: Color.from(alpha: 0.78, red: 1, green: 1, blue: 1),
    glassBorder: Color.from(alpha: 0.10, red: 0, green: 0, blue: 0),
    navSelected: Color.from(alpha: 0.08, red: 0, green: 0, blue: 0),
  );
}

/// Etkin paletin renkleri. Değerler tema ile değiştiği için `const` içinde
/// kullanılamaz; her build'de yeniden okunur.
abstract final class AppColors {
  /// Etkin palet. Yalnızca tema kapsamı (AppThemeScope) ve açılış kodu
  /// değiştirir; bileşenler doğrudan atamaz.
  static AppPalette palette = AppPalette.dark;

  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceHigh => palette.surfaceHigh;
  static Color get border => palette.border;

  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textMuted => palette.textMuted;

  static Color get accent => palette.accent; // ana vurgu
  static Color get ops => palette.ops; // operasyon
  static Color get fitness => palette.fitness; // spor
  static Color get nutrition => palette.nutrition; // beslenme
  static Color get warning => palette.warning;
  static Color get danger => palette.danger;

  static Color get onAccent => palette.onAccent;
  static Color get inverseSurface => palette.inverseSurface;
  static Color get onInverseSurface => palette.onInverseSurface;
  static Color get scrim => palette.scrim;
  static Color get shadow => palette.shadow;
  static Color get glass => palette.glass;
  static Color get glassBorder => palette.glassBorder;
  static Color get navSelected => palette.navSelected;

  static Color forRoutineCategory(String category) => switch (category) {
        'operasyon' => ops,
        'spor' => fitness,
        'beslenme' => nutrition,
        'finans' => warning,
        _ => accent,
      };

  static Color forTaskCategory(String category) => switch (category) {
        'İş' => ops,
        'Ekip' => accent,
        'Finans' => warning,
        _ => fitness,
      };

  static Color forPriority(String priority) => switch (priority) {
        'high' => danger,
        'medium' => warning,
        _ => textMuted,
      };
}

/// Bento ızgarası ve kartlar için ortak yarıçaplar.
abstract final class AppRadii {
  static const double card = 24;
  static const double inner = 16;
  static const double chip = 12;
}

/// Bento ızgarası boşlukları.
abstract final class AppSpacing {
  static const double page = 16;
  static const double grid = 10;
  static const double cardPadding = 16;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 32;
  static const double section = 18;
}

abstract final class AppTheme {
  static final ThemeData dark = _build(AppPalette.dark);
  static final ThemeData light = _build(AppPalette.light);

  static ThemeData of(AppPalette palette) => palette.isDark ? dark : light;

  /// İki tema da aynı tipografi, yarıçap ve bileşen temalarını kullanır;
  /// yalnızca palet değişir.
  static ThemeData _build(AppPalette p) {
    final scheme = (p.isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: p.accent,
      onPrimary: p.onPrimary,
      secondary: p.ops,
      onSecondary: p.onSecondary,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: p.danger,
      onError: p.onError,
      outline: p.controlOutline,
      outlineVariant: p.controlOutlineSoft,
      onSurfaceVariant: p.controlContent,
      surfaceContainerHighest: p.controlFill,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: p.textPrimary,
          displayColor: p.textPrimary,
        )
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: p.textPrimary,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: p.textPrimary,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            height: 1.4,
            color: p.textPrimary,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            height: 1.4,
            color: p.textPrimary,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            color: p.textSecondary,
            letterSpacing: 0.2,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: p.overlayStyle,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.border),
        ),
      ),
      // Alt sayfa zemini çağrı anında değil temadan okunur; sayfa açıkken
      // tema değişirse zemin de değişir.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        hintStyle: TextStyle(color: p.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inverseSurface,
        contentTextStyle: TextStyle(color: p.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onPrimary,
        elevation: 6,
        shape: const CircleBorder(),
      ),
    );
  }
}
