import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/widgets/ritim_top/ritim_top.dart';
import 'package:kisisel_asistan/core/widgets/sunset_stripe.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  tearDown(() => AppColors.palette = AppPalette.dark);

  for (final MapEntry(key: name, value: p) in {
    'koyu': AppPalette.dark,
    'açık': AppPalette.light,
  }.entries) {
    test('$name: Vice City rolleri yüzeyde en az 3:1', () {
      for (final c in [p.sunsetStart, p.sunsetMid, p.sunsetEnd, p.neonTeal]) {
        expect(_contrast(c, p.surface), greaterThanOrEqualTo(3.0),
            reason: '$c');
        expect(_contrast(c, p.background), greaterThanOrEqualTo(3.0),
            reason: '$c');
      }
    });
  }

  test('AppColors gün batımı ve kutlama listeleri etkin paleti izler', () {
    AppColors.palette = AppPalette.light;
    expect(AppColors.sunset, [
      AppPalette.light.sunsetStart,
      AppPalette.light.sunsetMid,
      AppPalette.light.sunsetEnd,
    ]);
    expect(AppColors.celebration.last, AppPalette.light.neonTeal);
    AppColors.palette = AppPalette.dark;
    expect(AppColors.sunset.first, AppPalette.dark.sunsetStart);
  });

  testWidgets('SunsetStripe ve renkli RitimTop çizilir', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        SunsetStripe(),
        RitimTop(mode: RitimTopMode.idle, size: 48),
      ]),
    ));
    expect(find.byType(SunsetStripe), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
