import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';

void main() {
  // Geçmiş bir gün (tam bazal) ve ondan sonraki bir "şimdi".
  final pastDay = DateTime(2026, 11, 10);
  final now = DateTime(2026, 11, 17, 12);

  /// 80 kg, 180 cm, 30 yaş, erkek: bazal 1780. Net'i doğrudan `net` verir
  /// (aktif kalori 0, geçmiş gün).
  EnergyDay dayWithNet(
    double net, {
    int mealEntryCount = 1,
    int birthYear = 1996,
    int? activeKcalFromMetrics = 0,
    int workoutKcal = 0,
    double weightKg = 80,
    Sex sex = Sex.male,
    DateTime? day,
    DateTime? clock,
    double? intakeOverride,
  }) {
    final d = day ?? pastDay;
    final basal = basalKcal(
      weightKg: weightKg,
      heightCm: 180,
      age: d.year - birthYear,
      sex: sex,
    );
    return computeEnergyDay(
      day: d,
      now: clock ?? now,
      weightKg: weightKg,
      heightCm: 180,
      birthYear: birthYear,
      sex: sex,
      mealEntryCount: mealEntryCount,
      intakeKcal: intakeOverride ?? basal + net,
      activeKcalFromMetrics: activeKcalFromMetrics,
      workoutKcal: workoutKcal,
    );
  }

  group('basalKcal (Mifflin-St Jeor)', () {
    test('80 kg, 180 cm, 30 yaş: erkek 1780, kadın 1614, belirtmeyen 1697', () {
      expect(
        basalKcal(weightKg: 80, heightCm: 180, age: 30, sex: Sex.male),
        1780,
      );
      expect(
        basalKcal(weightKg: 80, heightCm: 180, age: 30, sex: Sex.female),
        1614,
      );
      expect(
        basalKcal(weightKg: 80, heightCm: 180, age: 30, sex: Sex.unspecified),
        1697,
      );
    });

    test('geçersiz kilo ya da boy sessizce yanlış sayı üretmez', () {
      expect(
        () => basalKcal(weightKg: 0, heightCm: 180, age: 30, sex: Sex.male),
        throwsArgumentError,
      );
      expect(
        () => basalKcal(
            weightKg: double.nan, heightCm: 180, age: 30, sex: Sex.male),
        throwsArgumentError,
      );
      expect(
        () => basalKcal(weightKg: 80, heightCm: 0, age: 30, sex: Sex.male),
        throwsArgumentError,
      );
    });
  });

  group('Sex.tryParse', () {
    test('veritabanı değerlerini eşler, bilinmeyeni null yapar', () {
      expect(Sex.tryParse('female'), Sex.female);
      expect(Sex.tryParse('male'), Sex.male);
      expect(Sex.tryParse('unspecified'), Sex.unspecified);
      expect(Sex.tryParse('x'), isNull);
      expect(Sex.tryParse(null), isNull);
    });
  });

  group('yorum bantları', () {
    final cases = <double, EnergyVerdict>{
      -1500: EnergyVerdict.veryHighDeficit,
      -1000: EnergyVerdict.veryHighDeficit,
      -999: EnergyVerdict.burning,
      -150: EnergyVerdict.burning,
      -149: EnergyVerdict.steady,
      0: EnergyVerdict.steady,
      149: EnergyVerdict.steady,
      150: EnergyVerdict.slightOver,
      499: EnergyVerdict.slightOver,
      500: EnergyVerdict.over,
      1800: EnergyVerdict.over,
    };
    cases.forEach((net, verdict) {
      test('net $net -> ${verdict.name}', () {
        final d = dayWithNet(net);
        expect(d.net, net);
        expect(d.verdict, verdict);
      });
    });

    test('ondalıklı sınır değerleri doğru banda düşer', () {
      expect(dayWithNet(-149.5).verdict, EnergyVerdict.steady);
      expect(dayWithNet(149.5).verdict, EnergyVerdict.steady);
      expect(dayWithNet(499.9).verdict, EnergyVerdict.slightOver);
      expect(dayWithNet(-999.9).verdict, EnergyVerdict.burning);
    });
  });

  group('öğün yok', () {
    test('mealEntryCount 0: noMeals, net ve alınan null, yorum yok', () {
      final d = dayWithNet(0, mealEntryCount: 0, intakeOverride: 0);
      expect(d.verdict, EnergyVerdict.noMeals);
      expect(d.net, isNull);
      expect(d.intake, isNull);
      expect(d.walkingMinutesToCompensate, isNull);
      expect(d.tomorrowCutKcal, isNull);
      // Yakılan taraf yine de hesaplanır (grafikte çizgi için).
      expect(d.basal, 1780);
    });

    test('öğün yokken intakeKcal ne olursa olsun yorum üretilmez', () {
      final d = dayWithNet(0, mealEntryCount: 0, intakeOverride: 5000);
      expect(d.verdict, EnergyVerdict.noMeals);
      expect(d.net, isNull);
    });
  });

  group('18 yaş altı', () {
    test('yaş 17: underAge, sayılar dolu, telafi önerisi yok', () {
      // 2026 - 2009 = 17; net +300 yetişkinde slightOver olurdu.
      final d = dayWithNet(300, birthYear: 2009);
      expect(d.verdict, EnergyVerdict.underAge);
      expect(d.intake, isNotNull);
      expect(d.net, isNotNull);
      expect(d.walkingMinutesToCompensate, isNull);
      expect(d.tomorrowCutKcal, isNull);
    });

    test('yaş 18: yorum üretilir', () {
      final d = dayWithNet(300, birthYear: 2008);
      expect(d.verdict, EnergyVerdict.slightOver);
    });

    test('doğum yılı gelecekte (geçersiz): yorum üretilmez', () {
      final d = dayWithNet(300, birthYear: 2030);
      expect(d.verdict, EnergyVerdict.underAge);
    });

    test('öğünü olmayan küçük için "öğün girilmedi" durumu korunur', () {
      final d = dayWithNet(0,
          birthYear: 2009, mealEntryCount: 0, intakeOverride: 0);
      expect(d.verdict, EnergyVerdict.noMeals);
    });
  });

  group('yakılan: aktif kalori kaynağı', () {
    test('metrik yok + antrenman 300: yakılan = bazal + 300, veri eksik', () {
      final d = dayWithNet(0,
          activeKcalFromMetrics: null, workoutKcal: 300, intakeOverride: 2000);
      expect(d.active, 300);
      expect(d.basal + d.active, 1780 + 300);
      expect(d.activeDataMissing, isTrue);
      expect(d.net, 2000 - 2080);
    });

    test('metrik 0 + antrenman 300: antrenman yedek olur, veri eksik sayılır',
        () {
      final d = dayWithNet(0,
          activeKcalFromMetrics: 0, workoutKcal: 300, intakeOverride: 2000);
      expect(d.active, 300);
      expect(d.activeDataMissing, isTrue);
    });

    test('metrik 500 + antrenman 300: çift sayım yok, yalnızca metrik', () {
      final d = dayWithNet(0,
          activeKcalFromMetrics: 500, workoutKcal: 300, intakeOverride: 2000);
      expect(d.active, 500);
      expect(d.basal + d.active, 1780 + 500);
      expect(d.activeDataMissing, isFalse);
    });

    test('metrik yok, antrenman yok: aktif 0, veri eksik', () {
      final d = dayWithNet(0,
          activeKcalFromMetrics: null, workoutKcal: 0, intakeOverride: 2000);
      expect(d.active, 0);
      expect(d.activeDataMissing, isTrue);
    });

    test('negatif antrenman kalorisi yok sayılır', () {
      final d = dayWithNet(0,
          activeKcalFromMetrics: null, workoutKcal: -50, intakeOverride: 2000);
      expect(d.active, 0);
    });
  });

  group('bugün ve gün değişimi', () {
    test('bugün 12:00: bazal 1780 x 0,5 = 890, isToday true', () {
      final today = DateTime(2026, 11, 17);
      final d = dayWithNet(0, day: today, clock: DateTime(2026, 11, 17, 12));
      expect(d.isToday, isTrue);
      expect(d.basal, closeTo(890, 1e-9));
    });

    test('bugün 18:00: bazal 3/4', () {
      final today = DateTime(2026, 11, 17);
      final d = dayWithNet(0, day: today, clock: DateTime(2026, 11, 17, 18));
      expect(d.basal, closeTo(1335, 1e-9));
    });

    test('gün değişimi: aynı gün gece yarısından sonra dün olur, bazal tam', () {
      final yesterday = DateTime(2026, 11, 17);
      final before = dayWithNet(0,
          day: yesterday, clock: DateTime(2026, 11, 17, 23, 59, 59));
      expect(before.isToday, isTrue);
      expect(before.basal, lessThan(1780));
      expect(before.basal, greaterThan(1779));

      final after = dayWithNet(0,
          day: yesterday, clock: DateTime(2026, 11, 18, 0, 0, 30));
      expect(after.isToday, isFalse);
      expect(after.basal, 1780);
    });

    test('geçmiş gün: isToday false ve bazal tam', () {
      final d = dayWithNet(0);
      expect(d.isToday, isFalse);
      expect(d.basal, 1780);
    });

    test('saat bileşenli gün tarihe indirgenir', () {
      final d = dayWithNet(0, day: DateTime(2026, 11, 10, 15, 30));
      expect(d.day, DateTime(2026, 11, 10));
      expect(d.isToday, isFalse);
    });

    test('bugün için yaş, günün yılına göre hesaplanır', () {
      // Aralık sonu: doğum yılı 2008, yıl 2026 -> 18 yaş, yorum üretilir.
      final d = dayWithNet(300,
          birthYear: 2008,
          day: DateTime(2026, 12, 31),
          clock: DateTime(2027, 1, 1, 9));
      expect(d.verdict, EnergyVerdict.slightOver);
    });
  });

  group('telafi', () {
    test('net +300, 80 kg: 62 dakika yürüyüş ya da yarın 300 kcal az', () {
      final d = dayWithNet(300);
      expect(d.verdict, EnergyVerdict.slightOver);
      expect(d.walkingMinutesToCompensate, 62);
      expect(d.tomorrowCutKcal, 300);
    });

    test('net +150: alt sınırda da telafi var', () {
      final d = dayWithNet(150);
      expect(d.walkingMinutesToCompensate, 31);
      expect(d.tomorrowCutKcal, 150);
    });

    test('tam bölünen dakika bir yukarı yuvarlanmaz', () {
      // 100 kg: 3,5 x 3,5 x 100 / 200 = 6,125 kcal/dk; 245 / 6,125 = 40.
      final d = dayWithNet(245, weightKg: 100);
      expect(d.walkingMinutesToCompensate, 40);
    });

    test('telafi yalnızca slightOver bandında verilir', () {
      expect(dayWithNet(-200).walkingMinutesToCompensate, isNull);
      expect(dayWithNet(0).walkingMinutesToCompensate, isNull);
      expect(dayWithNet(149).tomorrowCutKcal, isNull);
      expect(dayWithNet(500).walkingMinutesToCompensate, isNull);
      expect(dayWithNet(500).tomorrowCutKcal, isNull);
      expect(dayWithNet(-1200).tomorrowCutKcal, isNull);
    });
  });

  group('giriş sağlamlığı', () {
    test('negatif ya da sonsuz alınan kalori 0 sayılır, NaN üretmez', () {
      final neg = dayWithNet(0, intakeOverride: -100);
      expect(neg.intake, 0);
      expect(neg.net!.isFinite, isTrue);
      final nan = dayWithNet(0, intakeOverride: double.nan);
      expect(nan.intake, 0);
      expect(nan.net!.isFinite, isTrue);
      final inf = dayWithNet(0, intakeOverride: double.infinity);
      expect(inf.intake, 0);
    });

    test('EnergyDay eşitliği değerlere bakar', () {
      expect(dayWithNet(300), dayWithNet(300));
      expect(dayWithNet(300).hashCode, dayWithNet(300).hashCode);
      expect(dayWithNet(300) == dayWithNet(301), isFalse);
    });
  });

  group('summarize', () {
    test('net [-500, +200, null]: 2 gün, toplam -300, ~ -0,039 kg', () {
      final days = [
        dayWithNet(-500),
        dayWithNet(200),
        dayWithNet(0, mealEntryCount: 0, intakeOverride: 0),
      ];
      final s = summarize(days);
      expect(s.days, 2);
      expect(s.sumNet, -300);
      expect(s.estimatedFatKg, closeTo(-0.039, 0.0005));
      expect(s.estimatedFatKg, closeTo(-300 / 7700, 1e-12));
    });

    test('boş ve hepsi öğünsüz: 0 gün, 0 toplam, NaN yok', () {
      final empty = summarize(const []);
      expect(empty.days, 0);
      expect(empty.sumNet, 0);
      expect(empty.estimatedFatKg, 0);
      final none = summarize([
        dayWithNet(0, mealEntryCount: 0, intakeOverride: 0),
        dayWithNet(0, mealEntryCount: 0, intakeOverride: 0),
      ]);
      expect(none.days, 0);
      expect(none.estimatedFatKg.isNaN, isFalse);
    });

    test('fazla günler pozitif yağ değişimi verir', () {
      final s = summarize([dayWithNet(770), dayWithNet(770)]);
      expect(s.days, 2);
      expect(s.sumNet, 1540);
      expect(s.estimatedFatKg, closeTo(0.2, 1e-12));
    });
  });
}
