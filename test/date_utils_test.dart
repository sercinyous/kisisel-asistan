import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('ymd', () {
    test('sıfır dolgulu yyyy-MM-dd', () {
      expect(AppDates.ymd(DateTime(2026, 1, 5)), '2026-01-05');
      expect(AppDates.ymd(DateTime(2026, 11, 16, 23, 59)), '2026-11-16');
      expect(AppDates.ymd(DateTime(987, 3, 9)), '0987-03-09');
    });
  });

  group('startOfDay / endOfDay', () {
    test('gün sınırları', () {
      final d = DateTime(2026, 12, 31, 18, 45);
      expect(AppDates.startOfDay(d), DateTime(2026, 12, 31));
      expect(AppDates.endOfDay(d), DateTime(2027, 1, 1));
    });
  });

  group('relativeDayTime', () {
    final now = DateTime(2026, 11, 16, 10, 30); // Pazartesi

    test('bugün', () {
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 16, 15), now: now),
        'Bugün 15:00',
      );
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 16, 0, 5), now: now),
        'Bugün 00:05',
      );
    });

    test('yarın (gece yarısından hemen sonra dahil)', () {
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 17, 9, 30), now: now),
        'Yarın 09:30',
      );
      expect(
        AppDates.relativeDayTime(
          DateTime(2026, 11, 17),
          now: DateTime(2026, 11, 16, 23, 59),
        ),
        'Yarın 00:00',
      );
    });

    test('dün', () {
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 15, 23, 59), now: now),
        'Dün 23:59',
      );
    });

    test('diğer günler Türkçe kısa tarih ile', () {
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 18, 14), now: now),
        '18 Kas Çar 14:00',
      );
      expect(
        AppDates.relativeDayTime(DateTime(2026, 11, 14, 8), now: now),
        '14 Kas Cmt 08:00',
      );
    });

    test('UTC hedef yerel saate çevrilir', () {
      final utc = DateTime(2026, 11, 16, 15).toUtc();
      expect(AppDates.relativeDayTime(utc, now: now), 'Bugün 15:00');
    });
  });

  group('longDay / hourMinute', () {
    test('Türkçe uzun gün', () {
      expect(AppDates.longDay(DateTime(2026, 11, 16)), '16 Kasım Pazartesi');
      expect(AppDates.hourMinute(DateTime(2026, 11, 16, 7, 5)), '07:05');
    });
  });

  group('greeting sınırları', () {
    String at(int h, [int m = 0]) =>
        AppDates.greeting(DateTime(2026, 11, 16, h, m));

    test('00:00–04:59 İyi geceler', () {
      expect(at(0), 'İyi geceler');
      expect(at(4, 59), 'İyi geceler');
    });
    test('05:00–11:59 Günaydın', () {
      expect(at(5), 'Günaydın');
      expect(at(11, 59), 'Günaydın');
    });
    test('12:00–17:59 İyi günler', () {
      expect(at(12), 'İyi günler');
      expect(at(17, 59), 'İyi günler');
    });
    test('18:00–23:59 İyi akşamlar', () {
      expect(at(18), 'İyi akşamlar');
      expect(at(23, 59), 'İyi akşamlar');
    });
  });

  group('weekStart / addDays', () {
    test('haftanın Pazartesi gece yarısı', () {
      expect(AppDates.weekStart(DateTime(2026, 11, 16, 14, 30)),
          DateTime(2026, 11, 16)); // Pazartesi
      expect(AppDates.weekStart(DateTime(2026, 11, 18)), DateTime(2026, 11, 16));
      expect(AppDates.weekStart(DateTime(2026, 11, 22, 23, 59)),
          DateTime(2026, 11, 16)); // Pazar
    });
    test('ay ve yıl sınırını aşar', () {
      expect(AppDates.weekStart(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
      expect(AppDates.weekStart(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });
    test('addDays takvim günü ekler', () {
      expect(AppDates.addDays(DateTime(2026, 11, 30), 1), DateTime(2026, 12, 1));
      expect(AppDates.addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(AppDates.addDays(DateTime(2026, 11, 16), 7), DateTime(2026, 11, 23));
    });
  });
}
