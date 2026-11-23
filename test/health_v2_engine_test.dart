import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kisisel_asistan/core/avatar/avatar_image.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/domain/weight_eta.dart';

void main() {
  group('harcama modeli', () {
    final now = DateTime(2026, 11, 23, 12);

    test('elle değer öncelikli; bugün günün oranıyla', () {
      expect(
          dayExpenditure(
              day: DateTime(2026, 11, 22), now: now, manualKcal: 2400),
          const Expenditure(2400, ExpenditureSource.manual));
      expect(
          dayExpenditure(
                  day: DateTime(2026, 11, 23), now: now, manualKcal: 2400)!
              .kcal,
          1200);
    });

    test('sağlık aktif kalorisi varsa bazal + aktif', () {
      final e = dayExpenditure(
          day: DateTime(2026, 11, 22), now: now, basal: 1800, activeKcal: 500);
      expect(e, const Expenditure(2300, ExpenditureSource.health));
    });

    test('yoksa bazal × 1,2 + adım × 0,04', () {
      final e = dayExpenditure(
          day: DateTime(2026, 11, 22), now: now, basal: 1800, steps: 10000);
      expect(e, const Expenditure(2560, ExpenditureSource.estimate));
    });

    test('bazal ve elle değer yoksa null', () {
      expect(dayExpenditure(day: DateTime(2026, 11, 22), now: now), isNull);
    });

    test('plan harcaması: elle, katsayı, adım, varsayılan', () {
      expect(planExpenditure(manualKcal: 900).kcal, 1200);
      expect(planExpenditure(basal: 1800, activityFactor: 1.55).kcal, 2790);
      expect(planExpenditure(basal: 1800, stepsTarget: 8000).kcal, 2480);
      expect(planExpenditure().source, ExpenditureSource.fallback);
    });
  });

  group('weightEta', () {
    final now = DateTime(2026, 11, 23, 9);
    List<WeightEntry> series(double perWeek) => [
          for (var d = 28; d >= 0; d -= 4)
            WeightEntry(
              id: 'w$d',
              weightKg: 84 + perWeek * d / 7,
              loggedAt: now.subtract(Duration(days: d)),
            ),
        ];

    test('hedefe doğru eğilimde tarih ve gerçek hız', () {
      final s = series(0.5);
      final eta = weightEta(s, targetKg: 80, now: now);
      expect(eta.status, WeightEtaStatus.onTrack);
      expect(actualKgPerWeek(s, now: now), closeTo(0.5, 1e-6));
    });

    test('yetersiz veri', () {
      expect(actualKgPerWeek(series(0.5).take(2).toList(), now: now), isNull);
    });
  });

  test('ilerleme fotoğrafı: uzun kenar 1600, EXIF silinir', () {
    final src = img.Image(width: 3200, height: 2000);
    src.exif.imageIfd['Make'] = img.IfdValueAscii('Telefon');
    final jpeg = progressPhotoJpeg(Uint8List.fromList(img.encodeJpg(src)));
    final out = img.decodeJpg(jpeg)!;
    expect(out.width, 1600);
    expect(out.height, 1000);
    expect(out.exif.imageIfd['Make'], isNull);
  });
}
