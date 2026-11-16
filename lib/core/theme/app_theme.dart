import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF0E0E10);
  static const Color surfaceHigh = Color(0xFF18181B);
  static const Color border = Color(0xFF222226);

  static const Color textPrimary = Color(0xFFF2F4F8);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);

  static const Color accent = Color(0xFF5EEAD4); // ana vurgu (mint)
  static const Color ops = Color(0xFF7AA7FF); // operasyon
  static const Color fitness = Color(0xFFFF8A65); // spor
  static const Color nutrition = Color(0xFFB9F27C); // beslenme
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF6B6B);

  static Color forRoutineCategory(String category) => switch (category) {
        'operasyon' => ops,
        'spor' => fitness,
        'beslenme' => nutrition,
        'finans' => warning,
        _ => accent,
      };

  static Color forTaskCategory(String category) => switch (category) {
        'Pusholder' => ops,
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
}

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF04201B),
      secondary: AppColors.ops,
      onSecondary: Color(0xFF07142E),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Color(0xFF2B0606),
      outline: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.textPrimary,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            height: 1.4,
            color: AppColors.textPrimary,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            height: 1.4,
            color: AppColors.textPrimary,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
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
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Color(0xFF04201B),
        elevation: 6,
        shape: CircleBorder(),
      ),
    );
  }
}
