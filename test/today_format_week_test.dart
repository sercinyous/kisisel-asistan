import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/streaks.dart';
import 'package:kisisel_asistan/features/health/presentation/today/today_common.dart';

WeekDeficit _week(List<double?> values, {int target = 3850}) => WeekDeficit(
      weekStart: DateTime(2026, 11, 23),
      days: [
        for (final (i, v) in values.indexed)
          DayDeficit(
              date: DateTime(2026, 11, 23 + i), deficit: v, isToday: false),
      ],
      targetKcal: target,
    );

void main() {
  test('veri yoksa "—" ve "Henüz veri yok"', () {
    final w = _week([null, null]);
    expect(w.hasData, isFalse);
    expect(TodayFormat.weekTotal(w), '—');
    expect(TodayFormat.weekKg(w), 'Henüz veri yok');
  });

  test('fazla alımda kg yerine "fazla alım"', () {
    final w = _week([-400, null]);
    expect(TodayFormat.weekTotal(w), '+400 kcal');
    expect(TodayFormat.weekKg(w), 'fazla alım');
  });

  test('açıkta yaklaşık kg; hedef her ekranda aynı biçim', () {
    final w = _week([770, 770]);
    expect(TodayFormat.weekKg(w), '≈ 0,20 kg');
    expect(TodayFormat.weekTarget(3850), 'hedef −3.850 kcal');
  });
}
