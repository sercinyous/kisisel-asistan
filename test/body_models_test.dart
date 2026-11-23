import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/data/body_repository.dart';

BodyMeasurement _m(DateTime d, Map<BodyField, double> v, [String? id]) =>
    BodyMeasurement(id: id, measuredOn: d, values: v);

void main() {
  test('doğrulama: en az bir alan, 20–250 cm', () {
    expect(validateMeasurement({BodyField.waist: null}), 'En az bir ölçü gir.');
    expect(validateMeasurement({BodyField.waist: 88.5}), isNull);
    expect(validateMeasurement({BodyField.neck: 10}),
        'Boyun 20–250 cm arasında olmalı.');
    expect(validateMeasurement({BodyField.hip: 251}), isNotNull);
  });

  test('önceki ölçüden 5 cm üstü fark şüpheli', () {
    final prev = _m(DateTime(2026, 11, 16),
        {BodyField.waist: 90, BodyField.hip: 100});
    expect(
        suspiciousFields(prev, {BodyField.waist: 84.5, BodyField.hip: 99}),
        [BodyField.waist]);
    expect(suspiciousFields(prev, {BodyField.waist: 85}), isEmpty);
    expect(suspiciousFields(null, {BodyField.waist: 50}), isEmpty);
  });

  test('özet: son değer, başlangıçtan ve öncekinden fark', () {
    final s = summarizeMeasurements([
      _m(DateTime(2026, 11, 16), {BodyField.waist: 88.5}),
      _m(DateTime(2026, 11, 2), {BodyField.waist: 92, BodyField.arm: 35}),
      _m(DateTime(2026, 11, 9), {BodyField.waist: 89}),
    ]);
    final waist = s.firstWhere((e) => e.field == BodyField.waist);
    expect(waist.last, 88.5);
    expect(waist.fromStart, -3.5);
    expect(waist.fromPrevious, -0.5);
    expect(waist.improving, isTrue);
    final arm = s.firstWhere((e) => e.field == BodyField.arm);
    expect(arm.fromStart, isNull);
    expect(s.map((e) => e.field), [BodyField.waist, BodyField.arm]);
  });

  test('satır eşleme ve upsert gövdesi', () {
    final m = BodyMeasurement.fromMap(const {
      'id': 'x',
      'measured_on': '2026-11-02',
      'waist_cm': 88.5,
      'hip_cm': null,
      'note': ' ',
    });
    expect(m[BodyField.waist], 88.5);
    expect(m[BodyField.hip], isNull);
    expect(m.note, isNull);
    final map = m.toMap();
    expect(map['measured_on'], '2026-11-02');
    expect(map['hip_cm'], isNull);
    expect(map.containsKey('hip_cm'), isTrue);
  });

  test('fotoğraf yolu ve gruplama', () {
    expect(progressPhotoPath('u1', DateTime(2026, 11, 2), PhotoPose.side),
        'u1/2026-11-02/side.jpg');
    final photos = [
      for (final (d, p) in [
        ('2026-11-02', 'front'),
        ('2026-11-09', 'front'),
        ('2026-11-09', 'back'),
      ])
        ProgressPhoto.tryFromMap({
          'id': '$d$p',
          'taken_on': d,
          'pose': p,
          'storage_path': 'u1/$d/$p.jpg',
        })!,
    ];
    final groups = groupPhotos(photos);
    expect(groups.first.date, DateTime(2026, 11, 9));
    expect(groups.first.photos.keys, containsAll([PhotoPose.front, PhotoPose.back]));
    expect(ProgressPhoto.tryFromMap(const {'pose': 'top'}), isNull);
  });

  test('bellek deposu aynı günü günceller', () async {
    final repo = MemoryBodyRepository();
    await repo.upsertMeasurement(
        _m(DateTime(2026, 11, 2, 15), {BodyField.waist: 90.04}));
    await repo.upsertMeasurement(
        _m(DateTime(2026, 11, 2), {BodyField.waist: 89.5}));
    final list = await repo.fetchMeasurements();
    expect(list, hasLength(1));
    expect(list.single[BodyField.waist], 89.5);
  });
}
