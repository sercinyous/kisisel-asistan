import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/streaks.dart';

const _t = StreakTargets(
  dailySteps: 8000,
  kcalTarget: 2000,
  floorKcal: 1500,
  plannedDeficit: 500,
);

final _today = DateTime(2026, 11, 23);

DateTime _d(int back) => DateTime(2026, 11, 23 - back);

/// Hedefte bir gün: 3 öğün, 1.900 kcal, harcama 2.500.
StreakDay _good(int back, {int steps = 9000}) => StreakDay(
      date: _d(back),
      steps: steps,
      mealCount: 3,
      intakeKcal: 1900,
      expenditureKcal: 2500,
    );

StreakStatus _of(List<StreakStatus> s, StreakKind k) =>
    s.firstWhere((e) => e.kind == k);

void main() {
  group('seriler', () {
    test('bugün sağlanmadıysa bekleniyor, seri bozulmaz', () {
      final days = [
        for (var b = 5; b >= 1; b--) _good(b),
        StreakDay(date: _today, steps: 1200, mealCount: 1, intakeKcal: 400,
            expenditureKcal: 900),
      ];
      final s = computeStreaks(days: days, targets: _t, today: _today);
      for (final k in StreakKind.values) {
        expect(_of(s, k).current, 5, reason: k.name);
        expect(_of(s, k).today, StreakToday.pending);
      }
    });

    test('bugün sağlandıysa sayılır', () {
      final s = computeStreaks(
          days: [_good(1), _good(0)], targets: _t, today: _today);
      expect(_of(s, StreakKind.logging).current, 2);
      expect(_of(s, StreakKind.logging).today, StreakToday.done);
    });

    test('kaçırılan kapalı gün seriyi bozar; en iyi korunur', () {
      final days = [
        for (var b = 9; b >= 5; b--) _good(b),
        StreakDay(date: _d(4)),
        for (var b = 3; b >= 1; b--) _good(b),
      ];
      final s = computeStreaks(days: days, targets: _t, today: _today);
      final logging = _of(s, StreakKind.logging);
      expect(logging.current, 3);
      expect(logging.best, 5);
      expect(logging.days[_d(4)], isFalse);
    });

    test('tabanın altında yenen gün Açık serisine sayılmaz', () {
      final days = [
        _good(2),
        StreakDay(date: _d(1), steps: 9000, mealCount: 3, intakeKcal: 1300,
            expenditureKcal: 2500),
      ];
      final s = computeStreaks(days: days, targets: _t, today: _today);
      expect(_of(s, StreakKind.deficit).current, 0);
      // Kayıt serisi yine de sayar.
      expect(_of(s, StreakKind.logging).current, 2);
    });

    test('hedefi aşan gün Açık serisine sayılmaz', () {
      final days = [
        _good(2),
        StreakDay(date: _d(1), steps: 9000, mealCount: 3, intakeKcal: 2300,
            expenditureKcal: 2600),
      ];
      final s = computeStreaks(days: days, targets: _t, today: _today);
      expect(_of(s, StreakKind.deficit).current, 0);
    });

    test('açık sınırı aşan gün sayılmaz', () {
      // 1600 kcal, harcama 2600 → 1000 açık > max(650, 500).
      final day = StreakDay(date: _d(1), mealCount: 3, intakeKcal: 1600,
          expenditureKcal: 2600);
      expect(isDeficitDay(day, _t), isFalse);
    });

    test('Kayıt: 2 öğün ya da hedefin yarısı', () {
      expect(
          isLoggingDay(
              StreakDay(date: _d(1), mealCount: 2, intakeKcal: 300), _t),
          isTrue);
      expect(
          isLoggingDay(
              StreakDay(date: _d(1), mealCount: 1, intakeKcal: 1000), _t),
          isTrue);
      expect(
          isLoggingDay(
              StreakDay(date: _d(1), mealCount: 1, intakeKcal: 999), _t),
          isFalse);
    });

    test('adım kaynağı yoksa Adım serisi listede yok', () {
      final s = computeStreaks(
          days: [_good(1)], targets: _t, today: _today, includeSteps: false);
      expect(s.map((e) => e.kind), [StreakKind.logging, StreakKind.deficit]);
      expect(s.first.semantics, 'Kayıt serisi 1 gün');
    });
  });

  group('düşük alım uyarısı', () {
    StreakDay low(int b) => StreakDay(date: _d(b), mealCount: 2,
        intakeKcal: 1000, expenditureKcal: 2400);

    test('son 3 kapalı gün tabanın altındaysa uyarı', () {
      expect(
          lowIntakeWarning(
              days: [low(3), low(2), low(1)], floorKcal: 1500, today: _today),
          isTrue);
    });

    test('bir gün normal ya da kayıtsızsa uyarı yok', () {
      expect(
          lowIntakeWarning(
              days: [low(3), _good(2), low(1)], floorKcal: 1500, today: _today),
          isFalse);
      expect(
          lowIntakeWarning(
              days: [low(3), low(1)], floorKcal: 1500, today: _today),
          isFalse);
    });
  });

  group('haftalık açık', () {
    test('Pzt–bugün toplamı, kayıtsız gün 0, gelecek gün yok', () {
      // 23 Kasım 2026 Pazartesi değil: hafta 23 Kasım Pazartesi'dir.
      final monday = DateTime(2026, 11, 23);
      final today = DateTime(2026, 11, 26, 15);
      final w = computeWeekDeficit(
        weekStart: monday,
        today: today,
        targetKcal: 3850,
        days: [
          StreakDay(date: monday, mealCount: 3, intakeKcal: 1900,
              expenditureKcal: 2500),
          StreakDay(date: DateTime(2026, 11, 24), mealCount: 3,
              intakeKcal: 2100, expenditureKcal: 2600),
          StreakDay(date: DateTime(2026, 11, 25)),
          StreakDay(date: DateTime(2026, 11, 26), mealCount: 2,
              intakeKcal: 900, expenditureKcal: 1500),
        ],
      );
      expect(w.days, hasLength(4));
      expect(w.days.last.isToday, isTrue);
      expect(w.days[2].deficit, isNull);
      expect(w.totalKcal, 600 + 500 + 600);
      expect(w.kg, closeTo(1700 / 7700, 1e-9));
      expect(w.progress, closeTo(1700 / 3850, 1e-9));
    });

    test('hedef: hız × 7700 ya da plan açığı × 7', () {
      expect(weeklyDeficitTarget(kgPerWeek: 0.5, dailyDeficit: 0), 3850);
      expect(weeklyDeficitTarget(dailyDeficit: 816), 5712);
      expect(weeklyDeficitTarget(dailyDeficit: -100), 0);
    });
  });
}
