import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_format.dart';

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('weekRange', () {
    test('aynı ay içinde ay adı bir kez yazılır', () {
      expect(ReportsFormat.weekRange(DateTime(2026, 11, 9)), '9 – 15 Kasım');
    });

    test('ay değişiyorsa iki uçta kısa ay adı', () {
      expect(ReportsFormat.weekRange(DateTime(2026, 10, 26)), '26 Eki – 1 Kas');
    });

    test('yıl değişen hafta', () {
      expect(ReportsFormat.weekRange(DateTime(2026, 12, 28)), '28 Ara – 3 Oca');
    });
  });

  group('sleepShort', () {
    test('dakika iki haneli yazılır', () {
      expect(ReportsFormat.sleepShort(425), '7 sa 05');
      expect(ReportsFormat.sleepShort(450), '7 sa 30');
    });

    test('veri yoksa çizgi', () {
      expect(ReportsFormat.sleepShort(0), '—');
    });
  });

  group('splitSummary', () {
    test('tek paragraf: öneri yok', () {
      final parts = ReportsFormat.splitSummary('Dengeli bir gün.');
      expect(parts.body, 'Dengeli bir gün.');
      expect(parts.suggestions, isEmpty);
    });

    test('değerlendirmeden sonraki kısa satırlar öneridir', () {
      final parts = ReportsFormat.splitSummary(
        'İş tarafında güçlü bir hafta.\n\n'
        'Perşembe antrenmanını sabaha al.\n'
        '- Öğle öğününe 30 g protein ekle.\n'
        '2. Uyku saatini sabitle.\n',
      );
      expect(parts.body, 'İş tarafında güçlü bir hafta.');
      expect(parts.suggestions, [
        'Perşembe antrenmanını sabaha al.',
        'Öğle öğününe 30 g protein ekle.',
        'Uyku saatini sabitle.',
      ]);
    });

    test('en fazla 3 öneri; önceki satırlar değerlendirmede kalır', () {
      final parts = ReportsFormat.splitSummary('A.\nB.\nC.\nD.\nE.');
      expect(parts.body, 'A.\n\nB.');
      expect(parts.suggestions, ['C.', 'D.', 'E.']);
    });

    test('uzun son paragraf öneri sayılmaz', () {
      final long = 'Form tarafında ${'çok ' * 40}uzun bir paragraf.';
      final parts = ReportsFormat.splitSummary('İş iyi.\n$long');
      expect(parts.body, 'İş iyi.\n\n$long');
      expect(parts.suggestions, isEmpty);
    });

    test('öneriler kapalıysa bütün metin değerlendirmedir', () {
      final parts =
          ReportsFormat.splitSummary('A.\nB.', withSuggestions: false);
      expect(parts.body, 'A.\n\nB.');
      expect(parts.suggestions, isEmpty);
    });
  });
}
