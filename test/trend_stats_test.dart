import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/trend_stats.dart';

/// 16 Kasım 2026 Pazartesi; hafta 16–22 Kasım.
final _mon = DateTime(2026, 11, 16);
final _tue = DateTime(2026, 11, 17);
final _wed = DateTime(2026, 11, 18);
final _thu = DateTime(2026, 11, 19);
final _fri = DateTime(2026, 11, 20);
final _sat = DateTime(2026, 11, 21);
final _sun = DateTime(2026, 11, 22);
final _week = [_mon, _tue, _wed, _thu, _fri, _sat, _sun];

bool _steps10k(double v) => v >= 10000;

TrendStats _build({
  required Map<DateTime, double> values,
  required DateTime today,
  List<DateTime>? days,
  bool isCurrentPeriod = true,
  bool Function(double)? hit,
}) =>
    TrendStats.build(
      days: days ?? _week,
      values: values,
      hit: hit ?? _steps10k,
      today: today,
      isCurrentPeriod: isCurrentPeriod,
    );

List<DayStatus> _statuses(TrendStats s) => [for (final d in s.days) d.status];

void main() {
  group('TrendStats.build: plandaki sabit örnek (bugün Perşembe)', () {
    final stats = _build(
      values: {_mon: 12000, _tue: 8000, _thu: 10500},
      today: _thu,
    );

    test('gün durumları', () {
      expect(_statuses(stats), [
        DayStatus.hit,
        DayStatus.miss,
        DayStatus.noData,
        DayStatus.hit,
        DayStatus.future,
        DayStatus.future,
        DayStatus.future,
      ]);
    });

    test('günler girdi sırasıyla korunur', () {
      expect([for (final d in stats.days) d.day], _week);
    });

    test('sayaçlar ve yüzde', () {
      expect(stats.hitDays, 2);
      expect(stats.dataDays, 3);
      expect(stats.percent, closeTo(2 / 3, 1e-12));
    });

    test('ortalama bugün dahil (tutturuldu)', () {
      expect(stats.average, closeTo(10166.67, 0.01));
    });

    test('seriler', () {
      expect(stats.currentStreak, 1);
      expect(stats.longestStreak, 1);
    });

    test('değerler yalnızca verisi olan geçmiş/bugün günlerde dolu', () {
      expect([for (final d in stats.days) d.value], [
        12000,
        8000,
        null,
        10500,
        null,
        null,
        null,
      ]);
    });
  });

  group('TrendStats.build: bugün devam ediyor', () {
    final stats = _build(
      values: {_mon: 12000, _tue: 8000, _thu: 4000},
      today: _thu,
    );

    test('hedefi tutturmamış bugün inProgress olur', () {
      expect(stats.days[3].status, DayStatus.inProgress);
      expect(stats.days[3].value, 4000);
    });

    test('paydaya ve ortalamaya girmez', () {
      expect(stats.hitDays, 1);
      expect(stats.dataDays, 2);
      expect(stats.percent, closeTo(0.5, 1e-12));
      expect(stats.average, 10000);
    });

    test('mevcut seri: Salı kaçırıldığı için 0', () {
      expect(stats.currentStreak, 0);
      expect(stats.longestStreak, 1);
    });

    test('devam eden bugün seriyi bozmaz', () {
      final s = _build(
        values: {_mon: 12000, _tue: 11000, _thu: 4000},
        today: _thu,
      );
      expect(s.days[3].status, DayStatus.inProgress);
      expect(s.currentStreak, 2);
      expect(s.longestStreak, 2);
      expect(s.hitDays, 2);
      expect(s.dataDays, 2);
    });

    test('bugün verisiz: noData, paydada yok, seriyi bozmaz', () {
      final s = _build(values: {_mon: 12000, _tue: 11000}, today: _thu);
      expect(s.days[3].status, DayStatus.noData);
      expect(s.days[3].value, isNull);
      expect(s.dataDays, 2);
      expect(s.currentStreak, 2);
    });
  });

  group('TrendStats.build: seriler', () {
    test('[hit, noData, hit] → en uzun seri 2 (verisiz gün bozmaz)', () {
      final s = _build(
        days: [_mon, _tue, _wed],
        values: {_mon: 11000, _wed: 12000},
        today: _sun,
      );
      expect(_statuses(s), [DayStatus.hit, DayStatus.noData, DayStatus.hit]);
      expect(s.longestStreak, 2);
      expect(s.currentStreak, 2);
    });

    test('veri olup tutturulmayan gün seriyi bozar', () {
      final s = _build(
        days: [_mon, _tue, _wed, _thu],
        values: {_mon: 11000, _tue: 12000, _wed: 100, _thu: 13000},
        today: _sun,
      );
      expect(_statuses(s), [
        DayStatus.hit,
        DayStatus.hit,
        DayStatus.miss,
        DayStatus.hit,
      ]);
      expect(s.longestStreak, 2);
      expect(s.currentStreak, 1);
    });

    test('dönem sonundaki tutmayan gün mevcut seriyi 0 yapar', () {
      final s = _build(
        days: [_mon, _tue, _wed],
        values: {_mon: 11000, _tue: 12000, _wed: 100},
        today: _sun,
      );
      expect(s.longestStreak, 2);
      expect(s.currentStreak, 0);
    });

    test('en uzun seri dönemin ortasında kalabilir', () {
      final s = _build(
        days: _week,
        values: {
          _mon: 1,
          _tue: 11000,
          _wed: 11000,
          _thu: 11000,
          _fri: 1,
          _sat: 11000,
          _sun: 1,
        },
        today: DateTime(2026, 11, 30),
      );
      expect(s.longestStreak, 3);
      expect(s.currentStreak, 0);
    });

    test('geçmiş dönemde mevcut seri null; en uzun seri korunur', () {
      final s = _build(
        values: {_mon: 12000, _tue: 11000, _wed: 100},
        today: DateTime(2026, 12, 3),
        isCurrentPeriod: false,
      );
      expect(s.currentStreak, isNull);
      expect(s.longestStreak, 2);
    });
  });

  group('TrendStats.build: boş ve sınır durumlar', () {
    test('hiç veri yok: yüzde ve ortalama null, 0/0 yok', () {
      final s = _build(values: const {}, today: _thu);
      expect(s.percent, isNull);
      expect(s.average, isNull);
      expect(s.dataDays, 0);
      expect(s.hitDays, 0);
      expect(s.longestStreak, 0);
      expect(s.currentStreak, 0);
      expect(_statuses(s), [
        DayStatus.noData,
        DayStatus.noData,
        DayStatus.noData,
        DayStatus.noData,
        DayStatus.future,
        DayStatus.future,
        DayStatus.future,
      ]);
    });

    test('yalnızca devam eden bugün verisi: yüzde/ortalama null', () {
      final s = _build(values: {_thu: 4000}, today: _thu);
      expect(s.days[3].status, DayStatus.inProgress);
      expect(s.dataDays, 0);
      expect(s.percent, isNull);
      expect(s.average, isNull);
    });

    test('tamamen gelecek dönem: hepsi future, veri yok', () {
      final s = _build(
        values: {_mon: 12000},
        today: DateTime(2026, 11, 10),
        isCurrentPeriod: false,
      );
      expect(_statuses(s).every((x) => x == DayStatus.future), isTrue);
      expect(s.dataDays, 0);
      expect(s.percent, isNull);
      expect(s.average, isNull);
      expect(s.days.every((d) => d.value == null), isTrue);
    });

    test('gelecek günün değeri (hatalı kaynak) hesaba girmez', () {
      final s = _build(values: {_mon: 12000, _fri: 99999}, today: _thu);
      expect(s.days[4].status, DayStatus.future);
      expect(s.days[4].value, isNull);
      expect(s.dataDays, 1);
      expect(s.average, 12000);
    });

    test('tamamen geçmiş dönem: future yok', () {
      final s = _build(
        values: {_mon: 12000, _tue: 11000, _wed: 9000},
        today: DateTime(2026, 12, 1),
        isCurrentPeriod: false,
      );
      expect(s.days.any((d) => d.status == DayStatus.future), isFalse);
      expect(s.hitDays, 2);
      expect(s.dataDays, 3);
      expect(s.percent, closeTo(2 / 3, 1e-12));
      expect(s.average, closeTo(32000 / 3, 1e-9));
    });

    test('saat bileşenli tarihler günün başına indirgenir', () {
      final s = _build(
        days: [
          DateTime(2026, 11, 16, 13, 45),
          DateTime(2026, 11, 17, 8),
        ],
        values: {
          DateTime(2026, 11, 16, 23, 59): 12000,
          DateTime(2026, 11, 17, 6): 100,
        },
        today: DateTime(2026, 11, 17, 21, 30),
      );
      expect(s.days[0].day, DateTime(2026, 11, 16));
      expect(s.days[0].status, DayStatus.hit);
      expect(s.days[1].day, DateTime(2026, 11, 17));
      expect(s.days[1].status, DayStatus.inProgress);
    });

    test('NaN/sonsuz değer verisiz sayılır', () {
      final s = _build(
        days: [_mon, _tue, _wed],
        values: {_mon: double.nan, _tue: double.infinity, _wed: 11000},
        today: _sun,
      );
      expect(_statuses(s), [DayStatus.noData, DayStatus.noData, DayStatus.hit]);
      expect(s.dataDays, 1);
      expect(s.average, 11000);
    });

    test('hit işlevi ham değeri alır (kalori bandı gibi iki uçlu kural)', () {
      bool band(double v) => v >= 1700 && v <= 2200;
      final s = _build(
        days: [_mon, _tue, _wed],
        values: {_mon: 1700, _tue: 2201, _wed: 1950},
        today: _sun,
        hit: band,
      );
      expect(_statuses(s), [DayStatus.hit, DayStatus.miss, DayStatus.hit]);
      expect(s.hitDays, 2);
      expect(s.dataDays, 3);
    });

    test('28 günlük ay: hepsi tutan gün → seri 28', () {
      final feb = [for (var d = 1; d <= 28; d++) DateTime(2027, 2, d)];
      final s = _build(
        days: feb,
        values: {for (final d in feb) d: 12000},
        today: DateTime(2027, 3, 5),
        isCurrentPeriod: false,
      );
      expect(s.days.length, 28);
      expect(s.hitDays, 28);
      expect(s.dataDays, 28);
      expect(s.percent, 1);
      expect(s.longestStreak, 28);
    });

    test('31 günlük ay: bugün ortada, kalan günler future', () {
      final dec = [for (var d = 1; d <= 31; d++) DateTime(2026, 12, d)];
      final s = _build(
        days: dec,
        values: {DateTime(2026, 12, 1): 12000, DateTime(2026, 12, 10): 3000},
        today: DateTime(2026, 12, 10),
      );
      expect(s.days.length, 31);
      expect(s.days[9].status, DayStatus.inProgress);
      expect(s.days[10].status, DayStatus.future);
      expect(s.days.last.status, DayStatus.future);
      expect(s.hitDays, 1);
      expect(s.dataDays, 1);
    });

    test('days listesi değiştirilemez', () {
      final s = _build(values: {_mon: 12000}, today: _thu);
      expect(
        () => s.days.add(TrendDay(
          day: _sun,
          value: null,
          status: DayStatus.future,
        )),
        throwsUnsupportedError,
      );
    });

    test('girdi listesi sonradan değişse de sonuç değişmez', () {
      final input = [_mon, _tue];
      final s = _build(days: input, values: {_mon: 12000}, today: _sun);
      input.add(_wed);
      expect(s.days.length, 2);
    });
  });
}
