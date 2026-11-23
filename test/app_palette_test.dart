import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';

/// WCAG 2.x bağıl parlaklık.
double _luminance(Color color) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG kontrast oranı (1..21). Renkler opak olmalıdır.
double contrast(Color a, Color b) {
  expect(a.a, 1.0, reason: '$a opak olmalı');
  expect(b.a, 1.0, reason: '$b opak olmalı');
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const palettes = {'koyu': AppPalette.dark, 'açık': AppPalette.light};

  test('kontrast hesabı bilinen değerleri verir', () {
    expect(contrast(Colors.black, Colors.white), closeTo(21, 0.001));
    expect(contrast(Colors.white, Colors.white), closeTo(1, 0.001));
    // #767676 beyaz üstünde AA sınırındadır (4.54).
    expect(
      contrast(const Color(0xFF767676), Colors.white),
      closeTo(4.54, 0.01),
    );
  });

  for (final MapEntry(key: name, value: p) in palettes.entries) {
    group('$name palet WCAG kontrastı', () {
      final accents = {
        'accent': p.accent,
        'ops': p.ops,
        'fitness': p.fitness,
        'nutrition': p.nutrition,
        'warning': p.warning,
        'danger': p.danger,
      };

      test('birincil metin zemin ve kart üstünde en az 7', () {
        expect(contrast(p.textPrimary, p.background), greaterThanOrEqualTo(7));
        expect(contrast(p.textPrimary, p.surface), greaterThanOrEqualTo(7));
        expect(contrast(p.textPrimary, p.surfaceHigh), greaterThanOrEqualTo(7));
      });

      test('ikincil metin en az 4.5', () {
        expect(
          contrast(p.textSecondary, p.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(p.textSecondary, p.surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(p.textSecondary, p.surfaceHigh),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('soluk metin en az 3', () {
        expect(contrast(p.textMuted, p.background), greaterThanOrEqualTo(3));
        expect(contrast(p.textMuted, p.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(p.textMuted, p.surfaceHigh), greaterThanOrEqualTo(3));
      });

      for (final MapEntry(key: role, value: color) in accents.entries) {
        test('$role zemin, kart ve giriş alanı üstünde en az 4.5', () {
          expect(
            contrast(color, p.background),
            greaterThanOrEqualTo(4.5),
            reason: '$role / background',
          );
          expect(
            contrast(color, p.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$role / surface',
          );
          expect(
            contrast(color, p.surfaceHigh),
            greaterThanOrEqualTo(4.5),
            reason: '$role / surfaceHigh',
          );
        });

        test('onAccent, $role dolgusu üstünde en az 4.5', () {
          expect(contrast(p.onAccent, color), greaterThanOrEqualTo(4.5));
        });
      }

      test('dolu buton yazıları en az 4.5', () {
        expect(contrast(p.onPrimary, p.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onSecondary, p.ops), greaterThanOrEqualTo(4.5));
        expect(contrast(p.onError, p.danger), greaterThanOrEqualTo(4.5));
      });

      test('ters yüzey (bildirim çubuğu, grafik ipucu) yazısı en az 7', () {
        expect(
          contrast(p.onInverseSurface, p.inverseSurface),
          greaterThanOrEqualTo(7),
        );
      });

      test('kontrol içeriği kart üstünde en az 4.5', () {
        expect(
          contrast(p.controlContent, p.surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }

  group('koyu palet', () {
    const p = AppPalette.dark;

    test('tasarım v2 renkleri (saf OLED siyah)', () {
      expect(p.brightness, Brightness.dark);
      expect(p.background, const Color(0xFF000000));
      expect(p.surface, const Color(0xFF121214));
      expect(p.surfaceHigh, const Color(0xFF1E1E22));
      expect(p.border, const Color(0xFF222226));
      expect(p.textPrimary, const Color(0xFFF4F4F6));
      expect(p.textSecondary, const Color(0xFF8E8E96));
      expect(p.textMuted, const Color(0xFF85858E));
      expect(p.accent, const Color(0xFF7EE0C3));
      expect(p.ops, const Color(0xFF8CC8FF));
      expect(p.fitness, const Color(0xFFFFB59A));
      expect(p.nutrition, const Color(0xFF7EE0C3));
      expect(p.warning, const Color(0xFFFFB59A));
      expect(p.danger, const Color(0xFFFF8FA3));
      expect(p.onAccent, const Color(0xFF0A0A0A));
    });

    test('alt bar, seçim ve karartma önizlemedeki saydamlıklarla aynı', () {
      expect(p.glass, const Color(0xFF28282E).withValues(alpha: 0.62));
      expect(p.glassBorder, Colors.white.withValues(alpha: 0.12));
      expect(p.navSelected, Colors.white.withValues(alpha: 0.14));
      expect(p.selection, Colors.white.withValues(alpha: 0.14));
      expect(p.track, const Color(0xFF26262B));
      expect(p.shadow, Colors.black.withValues(alpha: 0.35));
      expect(p.scrim, Colors.black.withValues(alpha: 0.6));
    });

    test('tema paletten kurulur', () {
      final scheme = AppTheme.dark.colorScheme;
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.dark.scaffoldBackgroundColor, p.background);
      expect(scheme.primary, p.accent);
      expect(scheme.onPrimary, p.onPrimary);
      expect(scheme.secondary, p.ops);
      expect(scheme.outline, p.border);
      expect(scheme.outlineVariant, p.controlOutlineSoft);
      expect(scheme.onSurfaceVariant, p.textPrimary);
      expect(scheme.surfaceContainerHighest, p.track);
    });
  });

  group('açık palet', () {
    const p = AppPalette.light;

    test('sayfa saf beyaz, kart ondan bir ton koyu ve ince kenarlıklı', () {
      expect(p.brightness, Brightness.light);
      expect(p.background, const Color(0xFFFFFFFF));
      expect(_luminance(p.surface), lessThan(_luminance(p.background)));
      expect(_luminance(p.surfaceHigh), lessThan(_luminance(p.surface)));
      expect(_luminance(p.border), lessThan(_luminance(p.surface)));
      // Kart beyaz sayfadan ayrışır ama gri bir blok gibi durmaz.
      expect(contrast(p.surface, p.background), inInclusiveRange(1.05, 1.2));
    });

    test('tema açık parlaklıkta ve paletten kurulur', () {
      final theme = AppTheme.light;
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, p.background);
      expect(theme.colorScheme.primary, p.accent);
      expect(theme.colorScheme.onPrimary, p.onPrimary);
      expect(theme.colorScheme.surface, p.surface);
      expect(theme.colorScheme.onSurface, p.textPrimary);
      expect(theme.colorScheme.error, p.danger);
      expect(theme.inputDecorationTheme.fillColor, p.surfaceHigh);
      expect(theme.snackBarTheme.backgroundColor, p.inverseSurface);
      expect(theme.textTheme.bodyMedium?.color, p.textPrimary);
    });
  });

  test('durum çubuğu ikonları: açık temada koyu, koyu temada açık', () {
    expect(
      AppTheme.light.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      AppTheme.light.appBarTheme.systemOverlayStyle?.statusBarBrightness,
      Brightness.light,
    );
    expect(
      AppTheme.dark.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      AppTheme.dark.appBarTheme.systemOverlayStyle?.statusBarBrightness,
      Brightness.dark,
    );
  });

  test('iki tema aynı tipografi ve yarıçapları kullanır', () {
    final dark = AppTheme.dark;
    final light = AppTheme.light;
    expect(
      light.textTheme.headlineMedium?.fontWeight,
      dark.textTheme.headlineMedium?.fontWeight,
    );
    expect(
      light.textTheme.bodyMedium?.height,
      dark.textTheme.bodyMedium?.height,
    );
    expect(light.cardTheme.shape.runtimeType, dark.cardTheme.shape.runtimeType);
    expect(
      (light.inputDecorationTheme.border! as OutlineInputBorder).borderRadius,
      (dark.inputDecorationTheme.border! as OutlineInputBorder).borderRadius,
    );
  });

  test('AppColors etkin paleti okur', () {
    addTearDown(() => AppColors.palette = AppPalette.dark);

    expect(AppColors.palette, same(AppPalette.dark));
    expect(AppColors.background, AppPalette.dark.background);
    expect(AppColors.forRoutineCategory('spor'), AppPalette.dark.fitness);

    AppColors.palette = AppPalette.light;
    expect(AppColors.background, AppPalette.light.background);
    expect(AppColors.accent, AppPalette.light.accent);
    expect(AppColors.onAccent, AppPalette.light.onAccent);
    expect(AppColors.forRoutineCategory('spor'), AppPalette.light.fitness);
    expect(AppColors.forTaskCategory('Finans'), AppPalette.light.warning);
    expect(AppColors.forPriority('high'), AppPalette.light.danger);
  });
}
