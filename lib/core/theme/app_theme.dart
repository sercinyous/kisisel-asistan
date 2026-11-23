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
    required this.sleep,
    required this.water,
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
    required this.selection,
    required this.track,
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
  final Color sleep; // uyku
  final Color water; // su
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

  /// Seçili bölme, çip ve hayalet buton dolgusu (yarı saydam, önizlemedeki --sel).
  final Color selection;

  /// İlerleme çubuğu/halkası izi ve boş gün noktası (opak).
  final Color track;

  bool get isDark => brightness == Brightness.dark;

  /// Durum çubuğu ikonları: koyu temada açık, açık temada koyu.
  SystemUiOverlayStyle get overlayStyle =>
      (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent);

  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Saf OLED siyah (varsayılan). Değerler tasarım önizlemesiyle
  /// (Sağlık v2) ile aynıdır: kart #121214, çizgi #222226, pastel vurgular.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF121214), // --card
    surfaceHigh: Color(0xFF1E1E22),
    border: Color(0xFF222226), // --card-line
    textPrimary: Color(0xFFF4F4F6), // --ink
    textSecondary: Color(0xFF8E8E96), // --sub
    textMuted: Color(0xFF85858E), // AA 4.5+ kartta
    accent: Color(0xFF7EE0C3), // --mint
    ops: Color(0xFF8CC8FF), // --sky
    fitness: Color(0xFFFFB59A), // --peach
    nutrition: Color(0xFF7EE0C3), // --mint (kalori halkası)
    sleep: Color(0xFFB9A7FF), // --lav
    water: Color(0xFF8CC8FF), // --sky
    warning: Color(0xFFFFB59A), // --peach
    danger: Color(0xFFFF8FA3), // --rose
    onAccent: Color(0xFF0A0A0A), // --onacc
    onPrimary: Color(0xFF0A0A0A),
    onSecondary: Color(0xFF0A0A0A),
    onError: Color(0xFF0A0A0A),
    controlOutline: Color(0xFF222226),
    controlOutlineSoft: Color(0xFF2E2E34),
    controlContent: Color(0xFFF4F4F6),
    controlFill: Color(0xFF26262B), // --track
    inverseSurface: Color(0xFF26262B),
    onInverseSurface: Color(0xFFF4F4F6),
    scrim: Color.from(alpha: 0.6, red: 0, green: 0, blue: 0),
    shadow: Color.from(alpha: 0.35, red: 0, green: 0, blue: 0),
    // --glass rgba(40,40,46,.62)
    glass: Color.from(
      alpha: 0.62,
      red: 40 / 255,
      green: 40 / 255,
      blue: 46 / 255,
    ),
    glassBorder: Color.from(alpha: 0.12, red: 1, green: 1, blue: 1),
    navSelected: Color.from(alpha: 0.14, red: 1, green: 1, blue: 1),
    selection: Color.from(alpha: 0.14, red: 1, green: 1, blue: 1), // --sel
    track: Color(0xFF26262B), // --track
  );

  /// Beyaz tema: önizlemenin açık bloğu. Vurgular beyaz zeminde AA (4.5)
  /// kontrastı tutacak kadar koyulaştırılmıştır.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF), // --phone
    surface: Color(0xFFF6F6F8), // --card
    surfaceHigh: Color(0xFFEDEDF1),
    border: Color(0xFFE4E4EA), // --card-line
    textPrimary: Color(0xFF141418), // --ink
    textSecondary: Color(0xFF5F5F68), // --sub (AA için bir ton koyu)
    textMuted: Color(0xFF6A6A73), // AA 4.5+ yüzeylerde
    accent: Color(0xFF147A60), // --mint #1f9e7d, AA
    ops: Color(0xFF2468AE), // --sky #2f7fcf, AA
    fitness: Color(0xFFB04E26), // --peach #d9693f, AA
    nutrition: Color(0xFF147A60), // --mint, AA
    sleep: Color(0xFF6E57D8), // --lav
    water: Color(0xFF2468AE), // --sky
    warning: Color(0xFFB04E26), // --peach, AA
    danger: Color(0xFFC0304E), // --rose #cf3f5c, AA
    onAccent: Color(0xFFFFFFFF), // --onacc
    onPrimary: Color(0xFFFFFFFF),
    onSecondary: Color(0xFFFFFFFF),
    onError: Color(0xFFFFFFFF),
    controlOutline: Color(0xFF8A8A96),
    controlOutlineSoft: Color(0xFFD4D4DC),
    controlContent: Color(0xFF4E4E57),
    controlFill: Color(0xFFE2E2E8), // --track
    inverseSurface: Color(0xFF1F1F24),
    onInverseSurface: Color(0xFFFFFFFF),
    scrim: Color.from(alpha: 0.32, red: 0, green: 0, blue: 0),
    shadow: Color.from(alpha: 0.10, red: 0, green: 0, blue: 0),
    glass: Color.from(alpha: 0.72, red: 1, green: 1, blue: 1), // --glass
    glassBorder: Color.from(alpha: 0.08, red: 0, green: 0, blue: 0),
    navSelected: Color.from(alpha: 0.07, red: 0, green: 0, blue: 0),
    selection: Color.from(alpha: 0.07, red: 0, green: 0, blue: 0), // --sel
    track: Color(0xFFD8D8E0), // --track (yüzeyde seçilebilir)
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
  static Color get sleep => palette.sleep; // uyku
  static Color get water => palette.water; // su
  static Color get protein => palette.sleep; // protein çubuğu (lavanta)
  static Color get positive => palette.accent; // iyi yönde değişim (mint)
  static Color get negative => palette.fitness; // kötü yönde değişim (şeftali)
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
  static Color get selection => palette.selection;
  static Color get track => palette.track;

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

/// Ortak yarıçaplar (tasarım önizlemesi: kart 18, iç öğe 12, kapsül 999).
abstract final class AppRadii {
  static const double card = 18;
  static const double inner = 12;
  static const double chip = 12;

  /// Bölmeli kontroldeki seçili parça (dış 12 − 3 iç boşluk).
  static const double segment = 9;

  /// İlerleme çubuğu uçları.
  static const double bar = 4;

  /// Tam yuvarlak kapsül (buton, rozet).
  static const double pill = 999;
}

/// Bento ızgarası boşlukları (önizlemenin sık yoğunluğu).
abstract final class AppSpacing {
  static const double page = 12;
  static const double grid = 8;
  static const double cardPadding = 12;

  // Boşluk ölçeği: 4 / 8 / 16 / 24 / 32.
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;

  // Ara değerler.
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double section = 14;
}

/// Önizlemenin yazı ölçeği (SF Pro / sistem fontu). Boyutlar ve kalınlıklar
/// tek yerden; renkler temadan gelir.
abstract final class AppType {
  static const double value = 16; // metrik değeri 700
  static const double screenTitle = 22; // .title 700
  static const double cardTitle = 12.5; // .h 600
  static const double body = 12.5;
  static const double chipValue = 13; // .chip b
  static const double chip = 11.5; // .chip, .btn
  static const double caption = 11; // .s
  static const double badge = 10.5; // .badge
  static const double micro = 9.5; // .days
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

    TextStyle? t(TextStyle? s, double size, FontWeight w,
            {Color? color, double ls = 0, double? height}) =>
        s?.copyWith(
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          height: height,
          color: color ?? p.textPrimary,
        );

    final bt = base.textTheme;
    final textTheme = bt
        .apply(bodyColor: p.textPrimary, displayColor: p.textPrimary)
        .copyWith(
          displaySmall: t(bt.displaySmall, 28, FontWeight.w700, ls: -0.8),
          headlineLarge: t(bt.headlineLarge, 26, FontWeight.w700, ls: -0.6),
          headlineMedium: t(bt.headlineMedium, 22, FontWeight.w700, ls: -0.5),
          headlineSmall: t(bt.headlineSmall, 22, FontWeight.w700, ls: -0.44),
          titleLarge: t(bt.titleLarge, 17, FontWeight.w700, ls: -0.2),
          titleMedium: t(bt.titleMedium, 14, FontWeight.w600),
          titleSmall: t(bt.titleSmall, AppType.cardTitle, FontWeight.w600),
          bodyLarge: t(bt.bodyLarge, 13.5, FontWeight.w400, height: 1.4),
          bodyMedium:
              t(bt.bodyMedium, AppType.body, FontWeight.w400, height: 1.4),
          bodySmall: t(bt.bodySmall, AppType.caption, FontWeight.w400,
              color: p.textSecondary, height: 1.35),
          labelLarge: t(bt.labelLarge, AppType.body, FontWeight.w600),
          labelMedium: t(bt.labelMedium, AppType.chip, FontWeight.w500,
              color: p.textSecondary),
          labelSmall: t(bt.labelSmall, AppType.badge, FontWeight.w500,
              color: p.textSecondary),
        );

    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.pill),
    );
    final innerRadius = BorderRadius.circular(AppRadii.inner);
    const buttonText = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

    return base.copyWith(
      textTheme: textTheme,
      iconTheme: IconThemeData(color: p.textPrimary, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: p.textPrimary, size: 22),
        systemOverlayStyle: p.overlayStyle,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: p.border),
        ),
      ),
      // Alt sayfa zemini çağrı anında değil temadan okunur; sayfa açıkken
      // tema değişirse zemin de değişir.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        dragHandleColor: p.track,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: innerRadius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        hintStyle: TextStyle(color: p.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: innerRadius,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: innerRadius,
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: innerRadius,
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          shape: pillShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          foregroundColor: p.textPrimary,
          backgroundColor: p.selection,
          side: BorderSide.none,
          shape: pillShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          shape: pillShape,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          // Bölücü çizgi yok: seçim yalnızca yarı saydam dolguyla belirtilir.
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: innerRadius),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.selection : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? p.textPrimary
                : p.textSecondary,
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.selection,
        selectedColor: p.accent.withValues(alpha: 0.18),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        labelStyle: TextStyle(
          fontSize: AppType.chip,
          fontWeight: FontWeight.w500,
          color: p.textPrimary,
        ),
        checkmarkColor: p.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.track,
        circularTrackColor: p.track,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(AppRadii.bar),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.track,
        thumbColor: p.textPrimary,
        overlayColor: p.selection,
        trackHeight: 6,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? p.onAccent : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.track,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: p.textSecondary, width: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inverseSurface,
        contentTextStyle: TextStyle(color: p.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: innerRadius),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.inverseSurface,
          borderRadius: innerRadius,
        ),
        textStyle: TextStyle(color: p.onInverseSurface, fontSize: 12),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        shape: const CircleBorder(),
      ),
    );
  }
}
