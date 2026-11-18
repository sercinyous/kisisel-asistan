import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';

void main() {
  group('latestBodyMeasurements', () {
    test('en son geçerli boy (m → cm) ve kilo seçilir', () {
      final m = latestBodyMeasurements([
        (type: 'height', value: 1.78, at: DateTime(2024, 1, 1)),
        (type: 'height', value: 1.805, at: DateTime(2026, 1, 1)),
        (type: 'weight', value: 82.46, at: DateTime(2026, 5, 1)),
        (type: 'weight', value: 90, at: DateTime(2025, 5, 1)),
      ]);
      expect(m.heightCm, 181);
      expect(m.weightKg, 82.5);
      expect(m.isEmpty, isFalse);
    });

    test('aralık dışı ve sonlu olmayan ölçümler atlanır', () {
      final m = latestBodyMeasurements([
        (type: 'height', value: 0.5, at: DateTime(2026, 1, 1)),
        (type: 'height', value: double.nan, at: DateTime(2026, 2, 1)),
        (type: 'weight', value: 12, at: DateTime(2026, 1, 1)),
        (type: 'weight', value: 300, at: DateTime(2026, 2, 1)),
      ]);
      expect(m.heightCm, isNull);
      expect(m.weightKg, isNull);
      expect(m.isEmpty, isTrue);
    });

    test('ölçüm yoksa boş', () {
      expect(latestBodyMeasurements(const []).isEmpty, isTrue);
    });
  });
}
