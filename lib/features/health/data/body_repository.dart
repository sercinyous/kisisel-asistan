import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/avatar/avatar_image.dart';
import '../../../core/services/supabase_providers.dart';
import '../domain/body_models.dart';

export '../domain/body_models.dart';

/// İlerleme fotoğraflarının özel kovası (yalnızca sahibi okur/yazar).
const String bodyPhotoBucket = 'body_photos';

/// Fotoğraf imzalı adresinin süresi: 10 dakika.
const int bodyPhotoSignedUrlSeconds = 10 * 60;

/// JPEG'e çevirme ve küçültme (testlerde değiştirilebilir).
typedef PhotoPreparer = Future<Uint8List> Function(Uint8List input);

final bodyRepositoryProvider = Provider<BodyRepository>((ref) {
  // Oturum (kullanıcı) değişince bağımlı tüm sağlayıcılar yeniden kurulur.
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SupabaseBodyRepository(ref.watch(supabaseClientProvider));
});

/// Mezura ölçüleri ve ilerleme fotoğrafları (RLS: yalnızca sahibi).
abstract class BodyRepository {
  /// Bu ortamda fotoğraf yüklenebilir mi (web demosunda hayır).
  bool get photosSupported;

  /// [from]'dan bugüne ölçüler, eskiden yeniye; [from] yoksa hepsi.
  Future<List<BodyMeasurement>> fetchMeasurements({DateTime? from});

  /// Aynı gün varsa üzerine yazar (`user_id, measured_on`).
  Future<BodyMeasurement> upsertMeasurement(BodyMeasurement measurement);

  Future<void> deleteMeasurement(String id);

  /// Tüm fotoğraf satırları, yeniden eskiye.
  Future<List<ProgressPhoto>> fetchPhotos();

  /// Görüntüyü 1600 px'e küçültür, EXIF'i siler, JPEG %80 yükler ve satırı
  /// yazar (aynı gün + poz varsa üzerine).
  Future<ProgressPhoto> uploadPhoto({
    required DateTime takenOn,
    required PhotoPose pose,
    required Uint8List imageBytes,
  });

  /// Önce Storage nesnesi, sonra satır silinir.
  Future<void> deletePhoto(ProgressPhoto photo);

  /// 10 dakikalık imzalı adres; nesne yoksa `null`.
  Future<String?> signedUrl(String storagePath);
}

class SupabaseBodyRepository implements BodyRepository {
  SupabaseBodyRepository(this._client, {PhotoPreparer? prepare})
      : _prepare = prepare ?? prepareProgressPhotoJpeg;

  final SupabaseClient _client;
  final PhotoPreparer _prepare;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  @override
  bool get photosSupported => !kIsWeb;

  @override
  Future<List<BodyMeasurement>> fetchMeasurements({DateTime? from}) async {
    var query = _client.from('body_measurements').select(
        'id, measured_on, waist_cm, hip_cm, chest_cm, arm_cm, thigh_cm, '
        'neck_cm, note');
    if (from != null) query = query.gte('measured_on', dateOnlyIso(from));
    final rows = await query.order('measured_on', ascending: true);
    return [for (final r in rows) BodyMeasurement.fromMap(r)];
  }

  @override
  Future<BodyMeasurement> upsertMeasurement(BodyMeasurement m) async {
    final row = await _client
        .from('body_measurements')
        .upsert({'user_id': _userId, ...m.toMap()},
            onConflict: 'user_id,measured_on')
        .select()
        .single();
    return BodyMeasurement.fromMap(row);
  }

  @override
  Future<void> deleteMeasurement(String id) async {
    await _client.from('body_measurements').delete().eq('id', id);
  }

  @override
  Future<List<ProgressPhoto>> fetchPhotos() async {
    final rows = await _client
        .from('progress_photos')
        .select('id, taken_on, pose, storage_path')
        .order('taken_on', ascending: false);
    return [
      for (final r in rows)
        if (ProgressPhoto.tryFromMap(r) case final p?) p,
    ];
  }

  @override
  Future<ProgressPhoto> uploadPhoto({
    required DateTime takenOn,
    required PhotoPose pose,
    required Uint8List imageBytes,
  }) async {
    final userId = _userId;
    final jpeg = await _prepare(imageBytes);
    final path = progressPhotoPath(userId, takenOn, pose);
    await _client.storage.from(bodyPhotoBucket).uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
            cacheControl: '600',
          ),
        );
    final row = await _client
        .from('progress_photos')
        .upsert({
          'user_id': userId,
          'taken_on': dateOnlyIso(takenOn),
          'pose': pose.name,
          'storage_path': path,
        }, onConflict: 'user_id,taken_on,pose')
        .select('id, taken_on, pose, storage_path')
        .single();
    return ProgressPhoto.tryFromMap(row)!;
  }

  @override
  Future<void> deletePhoto(ProgressPhoto photo) async {
    await _client.storage.from(bodyPhotoBucket).remove([photo.storagePath]);
    await _client.from('progress_photos').delete().eq('id', photo.id);
  }

  @override
  Future<String?> signedUrl(String storagePath) async {
    try {
      return await _client.storage
          .from(bodyPhotoBucket)
          .createSignedUrl(storagePath, bodyPhotoSignedUrlSeconds);
    } on StorageException {
      return null;
    }
  }
}

/// Bellekte çalışan depo (web demosu ve testler). Fotoğraf yüklenmez.
class MemoryBodyRepository implements BodyRepository {
  MemoryBodyRepository({
    List<BodyMeasurement>? measurements,
    List<ProgressPhoto>? photos,
  })  : measurements = measurements ?? [],
        photos = photos ?? [];

  final List<BodyMeasurement> measurements;
  final List<ProgressPhoto> photos;
  int _nextId = 1;

  @override
  bool get photosSupported => false;

  @override
  Future<List<BodyMeasurement>> fetchMeasurements({DateTime? from}) async {
    final list = [
      for (final m in measurements)
        if (from == null || !m.measuredOn.isBefore(from)) m,
    ]..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
    return list;
  }

  @override
  Future<BodyMeasurement> upsertMeasurement(BodyMeasurement m) async {
    final day =
        DateTime(m.measuredOn.year, m.measuredOn.month, m.measuredOn.day);
    final index = measurements.indexWhere((e) => e.measuredOn == day);
    final saved = BodyMeasurement(
      id: index >= 0 ? measurements[index].id : 'm${_nextId++}',
      measuredOn: day,
      values: {
        for (final e in m.values.entries) e.key: roundCm(e.value),
      },
      note: m.note,
    );
    if (index >= 0) {
      measurements[index] = saved;
    } else {
      measurements.add(saved);
    }
    return saved;
  }

  @override
  Future<void> deleteMeasurement(String id) async =>
      measurements.removeWhere((m) => m.id == id);

  @override
  Future<List<ProgressPhoto>> fetchPhotos() async =>
      [...photos]..sort((a, b) => b.takenOn.compareTo(a.takenOn));

  @override
  Future<ProgressPhoto> uploadPhoto({
    required DateTime takenOn,
    required PhotoPose pose,
    required Uint8List imageBytes,
  }) =>
      Future.error(UnsupportedError('Bu ortamda fotoğraf yüklenemez.'));

  @override
  Future<void> deletePhoto(ProgressPhoto photo) async =>
      photos.removeWhere((p) => p.id == photo.id);

  @override
  Future<String?> signedUrl(String storagePath) async => null;
}
