import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/domain/weight_eta.dart';

final _now = DateTime(2026, 11, 18, 12);

/// [daysAgo] gün önce [kg] ölçümü.
WeightEntry _w(int daysAgo, double kg) => WeightEntry(
      id: 'w$daysAgo',
      weightKg: kg,
      loggedAt: _now.subtract(Duration(days: daysAgo)),
    );

void main() {
  test('haftada 0,5 kg kayıp: varış günü doğru ve mesaj Türkçe', () {
    // 6 hafta, her hafta 0,5 kg düşüş; bugün 82 kg.
    final entries = [for (var w = 6; w >= 0; w--) _w(w * 7, 82 + w * 0.5)];
    final eta = estimateWeightEta(entries, targetKg: 78, now: _now);
    expect(eta.status, WeightEtaStatus.onTrack);
    expect(eta.slopeKgPerWeek, closeTo(-0.5, 1e-9));
    expect(eta.fittedNowKg, closeTo(82, 1e-9));
    // 4 kg / (0,5/7 kg/gün) = 56 gün → 13 Ocak 2027.
    expect(eta.eta, DateTime(2027, 1, 13));
    expect(
      weightEtaMessage(eta, targetKg: 78, now: _now),
      "Bu gidişle 78 kg'a yaklaşık 13 Ocak 2027",
    );
  });

  test('aynı yıl içinde varışta yıl yazılmaz', () {
    final now = DateTime(2026, 1, 10, 12);
    final entries = [
      for (var w = 4; w >= 0; w--)
        WeightEntry(
          id: '$w',
          weightKg: 80 + w * 0.5,
          loggedAt: now.subtract(Duration(days: w * 7)),
        ),
    ];
    final eta = estimateWeightEta(entries, targetKg: 78, now: now);
    expect(eta.eta, DateTime(2026, 3, 7));
    expect(weightEtaMessage(eta, targetKg: 78, now: now),
        "Bu gidişle 78 kg'a yaklaşık 7 Mart");
  });

  test('kilo artarken hedef aşağıdaysa trend hedefe doğru değil', () {
    final entries = [for (var w = 5; w >= 0; w--) _w(w * 7, 80 - w * 0.3)];
    final eta = estimateWeightEta(entries, targetKg: 75, now: _now);
    expect(eta.status, WeightEtaStatus.notTowards);
    expect(eta.eta, isNull);
    expect(weightEtaMessage(eta, targetKg: 75, now: _now),
        'Son haftalardaki trend hedefe doğru değil');
  });

  test('kilo alma hedefi: artış hedefe doğru', () {
    final entries = [for (var w = 4; w >= 0; w--) _w(w * 7, 60 - w * 0.25)];
    final eta = estimateWeightEta(entries, targetKg: 62, now: _now);
    expect(eta.status, WeightEtaStatus.onTrack);
    expect(eta.eta, DateTime(2026, 11, 18 + 56));
  });

  test('düz trend hedefe doğru sayılmaz', () {
    final entries = [for (var w = 4; w >= 0; w--) _w(w * 7, 80)];
    expect(estimateWeightEta(entries, targetKg: 75, now: _now).status,
        WeightEtaStatus.notTowards);
  });

  test('hedefe ulaşılmış', () {
    final entries = [for (var w = 4; w >= 0; w--) _w(w * 7, 78.1)];
    final eta = estimateWeightEta(entries, targetKg: 78, now: _now);
    expect(eta.status, WeightEtaStatus.reached);
    expect(weightEtaMessage(eta, targetKg: 78, now: _now),
        '78 kg hedefindesin');
  });

  test('yetersiz veri: az ölçüm, kısa aralık, 8 haftadan eski ölçümler', () {
    expect(
      estimateWeightEta([_w(10, 80), _w(0, 79)], targetKg: 75, now: _now)
          .status,
      WeightEtaStatus.insufficient,
    );
    expect(
      estimateWeightEta([_w(10, 80), _w(5, 79.5), _w(0, 79)],
              targetKg: 75, now: _now)
          .status,
      WeightEtaStatus.insufficient,
    );
    // Pencere dışındaki ölçümler sayılmaz.
    expect(
      estimateWeightEta([_w(90, 90), _w(80, 89), _w(0, 79)],
              targetKg: 75, now: _now)
          .status,
      WeightEtaStatus.insufficient,
    );
  });

  test('2 yıldan uzak varış hedefe doğru sayılmaz', () {
    // Haftada ~60 g kayıp, 20 kg kaldı → ~6 yıl.
    final entries = [for (var w = 6; w >= 0; w--) _w(w * 7, 100 + w * 0.06)];
    expect(estimateWeightEta(entries, targetKg: 80, now: _now).status,
        WeightEtaStatus.notTowards);
  });
}
