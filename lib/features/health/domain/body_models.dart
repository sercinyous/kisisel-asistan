// Vücut ölçüleri (mezura) ve ilerleme fotoğrafları. Saf modeller ve
// doğrulama; yalnızca sahibine görünür (arkadaşlara, raporlara ve AI'a
// girmez).

/// Ölçü alanları.
enum BodyField {
  waist('Bel', 'waist_cm', 'Bel: göbek hizası, nefes verince', true),
  hip('Kalça', 'hip_cm', 'Kalça: en geniş yer, ayaklar bitişik', true),
  chest('Göğüs', 'chest_cm', 'Göğüs: meme ucu hizası, kollar yanda', false),
  arm('Kol', 'arm_cm', 'Kol: pazının en kalın yeri, kol gevşek', false),
  thigh('Uyluk', 'thigh_cm', 'Uyluk: kasığın hemen altı, en kalın yer', false),
  neck('Boyun', 'neck_cm', 'Boyun: gırtlağın hemen altı', false);

  const BodyField(this.label, this.column, this.help, this.lowerIsBetter);

  final String label;
  final String column;

  /// Formdaki tek satırlık yardım.
  final String help;

  /// Azalma başarı sayılır (bel, kalça).
  final bool lowerIsBetter;
}

/// Ölçü sınırları (schema.sql check ile aynı) ve şüpheli fark eşiği.
abstract final class BodyLimits {
  static const double minCm = 20;
  static const double maxCm = 250;

  /// Önceki ölçüden bu kadar fark "Yanlış girmiş olabilir misin?" sorar.
  static const double suspiciousDeltaCm = 5;
}

/// Bir günün mezura ölçüsü (`body_measurements`).
class BodyMeasurement {
  const BodyMeasurement({
    required this.measuredOn,
    required this.values,
    this.id,
    this.note,
  });

  /// Sunucudan okunmamış taslakta `null`.
  final String? id;

  /// Yerel gün.
  final DateTime measuredOn;

  /// Girilen alanlar (cm, bir ondalık). Girilmeyen alan yoktur.
  final Map<BodyField, double> values;
  final String? note;

  double? operator [](BodyField field) => values[field];

  factory BodyMeasurement.fromMap(Map<String, dynamic> map) {
    final values = <BodyField, double>{};
    for (final f in BodyField.values) {
      final v = map[f.column];
      if (v is num) values[f] = v.toDouble();
    }
    final note = map['note'];
    return BodyMeasurement(
      id: map['id'] as String?,
      measuredOn: DateTime.parse(map['measured_on'] as String),
      values: values,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }

  /// Yazılabilir sütunlar; girilmeyen alan açıkça `null` yazılır (upsert
  /// eski değeri bırakmasın).
  Map<String, dynamic> toMap() => {
        'measured_on': dateOnlyIso(measuredOn),
        for (final f in BodyField.values)
          f.column: values[f] == null ? null : roundCm(values[f]!),
        'note': note,
      };
}

/// Bir ondalığa yuvarlar.
double roundCm(double v) => (v * 10).round() / 10;

/// "2026-11-02"
String dateOnlyIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Formun doğrulaması: en az bir alan, her alan 20–250 cm. Geçerliyse `null`.
String? validateMeasurement(Map<BodyField, double?> values) {
  final filled = {
    for (final e in values.entries)
      if (e.value != null) e.key: e.value!,
  };
  if (filled.isEmpty) return 'En az bir ölçü gir.';
  for (final e in filled.entries) {
    if (!e.value.isFinite ||
        e.value < BodyLimits.minCm ||
        e.value > BodyLimits.maxCm) {
      return '${e.key.label} 20–250 cm arasında olmalı.';
    }
  }
  return null;
}

/// Önceki ölçüden 5 cm'den fazla farklı alanlar ("Yanlış girmiş olabilir
/// misin?" [Düzelt] [Doğru]).
List<BodyField> suspiciousFields(
  BodyMeasurement? previous,
  Map<BodyField, double?> next,
) {
  if (previous == null) return const [];
  return [
    for (final f in BodyField.values)
      if (next[f] != null &&
          previous[f] != null &&
          (next[f]! - previous[f]!).abs() > BodyLimits.suspiciousDeltaCm)
        f,
  ];
}

/// Bir alanın son değeri ve farkları.
class BodyFieldSummary {
  const BodyFieldSummary({
    required this.field,
    required this.last,
    required this.fromStart,
    required this.fromPrevious,
  });

  final BodyField field;
  final double last;

  /// İlk girişten fark; tek giriş varsa `null`.
  final double? fromStart;

  /// Bir önceki girişten fark; tek giriş varsa `null`.
  final double? fromPrevious;

  /// Fark hedef yönünde mi (bel/kalça azalıyor, diğerleri belirsiz)?
  bool? get improving {
    final d = fromPrevious;
    if (d == null || d == 0 || !field.lowerIsBetter) return null;
    return d < 0;
  }
}

/// Alan başına özet (ölçüsü olan alanlar); [entries] herhangi bir sırada.
List<BodyFieldSummary> summarizeMeasurements(List<BodyMeasurement> entries) {
  final sorted = [...entries]
    ..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
  return [
    for (final f in BodyField.values)
      if (sorted.any((e) => e[f] != null))
        _summary(f, [
          for (final e in sorted)
            if (e[f] != null) e[f]!,
        ]),
  ];
}

BodyFieldSummary _summary(BodyField f, List<double> values) {
  final last = values.last;
  return BodyFieldSummary(
    field: f,
    last: last,
    fromStart: values.length < 2 ? null : roundCm(last - values.first),
    fromPrevious:
        values.length < 2 ? null : roundCm(last - values[values.length - 2]),
  );
}

/// Fotoğraf pozu.
enum PhotoPose {
  front('Ön'),
  side('Yan'),
  back('Arka');

  const PhotoPose(this.label);
  final String label;

  static PhotoPose? tryParse(Object? value) {
    for (final p in values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// Storage yolu: `<uid>/<YYYY-MM-DD>/<poz>.jpg` (schema.sql ile aynı).
String progressPhotoPath(String userId, DateTime takenOn, PhotoPose pose) =>
    '$userId/${dateOnlyIso(takenOn)}/${pose.name}.jpg';

/// `progress_photos` satırı.
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.takenOn,
    required this.pose,
    required this.storagePath,
  });

  final String id;
  final DateTime takenOn;
  final PhotoPose pose;
  final String storagePath;

  static ProgressPhoto? tryFromMap(Map<String, dynamic> map) {
    final pose = PhotoPose.tryParse(map['pose']);
    final taken = DateTime.tryParse('${map['taken_on']}');
    final path = map['storage_path'];
    if (pose == null || taken == null || path is! String) return null;
    return ProgressPhoto(
      id: '${map['id']}',
      takenOn: DateTime(taken.year, taken.month, taken.day),
      pose: pose,
      storagePath: path,
    );
  }
}

/// Bir kontrol gününün fotoğrafları (poz → fotoğraf).
class PhotoCheckin {
  const PhotoCheckin({required this.date, required this.photos});

  final DateTime date;
  final Map<PhotoPose, ProgressPhoto> photos;
}

/// Fotoğrafları tarihe göre gruplar, yeniden eskiye.
List<PhotoCheckin> groupPhotos(List<ProgressPhoto> photos) {
  final byDate = <DateTime, Map<PhotoPose, ProgressPhoto>>{};
  for (final p in photos) {
    (byDate[p.takenOn] ??= {})[p.pose] = p;
  }
  final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in dates) PhotoCheckin(date: d, photos: byDate[d]!),
  ];
}
