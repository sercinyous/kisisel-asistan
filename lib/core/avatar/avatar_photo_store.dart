import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_providers.dart';

/// Profil fotoğrafının Storage kovası ve nesne adı: `avatars/<uid>/avatar.jpg`.
const String avatarBucket = 'avatars';
String avatarObjectPath(String userId) => '$userId/avatar.jpg';

/// Profil fotoğrafı deposu (Supabase Storage). Kova özeldir: okuma imzalı
/// adresle yapılır; arkadaşlar da RLS ile okuyabilir.
abstract class AvatarPhotoStore {
  /// Bu ortamda fotoğraf yüklenebilir mi (web demosunda hayır).
  bool get supported;

  /// Kendi klasörüne yazar (varsa üzerine).
  Future<void> upload(Uint8List jpeg);

  /// Kendi fotoğrafını siler.
  Future<void> remove();

  /// [userId]'nin fotoğrafı için imzalı adres; yoksa null.
  Future<String?> signedUrl(String userId, int version);
}

class SupabaseAvatarPhotoStore implements AvatarPhotoStore {
  const SupabaseAvatarPhotoStore(this._client);

  final SupabaseClient _client;

  /// İmzalı adresin geçerlilik süresi; önbellek [avatarUrlRefreshAfter]
  /// dolunca (süre bitmeden) yenilenir.
  static const int signedUrlSeconds = 60 * 60;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Oturum bulunamadı.');
    return id;
  }

  @override
  bool get supported => !kIsWeb;

  @override
  Future<void> upload(Uint8List jpeg) async {
    await _client.storage.from(avatarBucket).uploadBinary(
          avatarObjectPath(_userId),
          jpeg,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
            cacheControl: '3600',
          ),
        );
  }

  @override
  Future<void> remove() async {
    await _client.storage.from(avatarBucket).remove([avatarObjectPath(_userId)]);
  }

  @override
  Future<String?> signedUrl(String userId, int version) async {
    try {
      final url = await _client.storage
          .from(avatarBucket)
          .createSignedUrl(avatarObjectPath(userId), signedUrlSeconds);
      return '$url&v=$version';
    } on StorageException {
      return null;
    }
  }
}

/// Fotoğrafsız ortam (web demosu, testler): yükleme yok, adres yok.
class UnsupportedAvatarPhotoStore implements AvatarPhotoStore {
  const UnsupportedAvatarPhotoStore();

  @override
  bool get supported => false;

  @override
  Future<void> upload(Uint8List jpeg) =>
      Future.error(UnsupportedError('Fotoğraf bu ortamda yüklenemez.'));

  @override
  Future<void> remove() async {}

  @override
  Future<String?> signedUrl(String userId, int version) async => null;
}

/// Fotoğraf seçenekleri gösterilsin mi? Web'de (ve web demosunda) hayır.
final avatarPhotoSupportedProvider = Provider<bool>((ref) => !kIsWeb);

final avatarPhotoStoreProvider = Provider<AvatarPhotoStore>((ref) {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  return SupabaseAvatarPhotoStore(ref.watch(supabaseClientProvider));
});

/// İmzalı adres önbellekte en çok bu kadar tutulur (adres 1 saat geçerli).
const Duration avatarUrlRefreshAfter = Duration(minutes: 50);

/// İmzalı adres önbelleği, (kullanıcı, sürüm) başına. Yalnızca başarılı adres
/// tutulur ve [avatarUrlRefreshAfter] sonra yenilenir; null ya da hata
/// önbelleğe alınmaz (dinleyen kalmayınca atılır, sonra yeniden istenir).
/// Oturum değişince depo yeniden kurulur ve önbellek boşalır.
final avatarPhotoUrlProvider =
    FutureProvider.autoDispose.family<String?, (String, int)>((ref, key) async {
  final store = ref.watch(avatarPhotoStoreProvider);
  final url = await store.signedUrl(key.$1, key.$2);
  if (url != null) {
    final link = ref.keepAlive();
    final timer = Timer(avatarUrlRefreshAfter, () {
      link.close();
      ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);
  }
  return url;
});

/// Seçici izin hatası (iOS `camera_access_denied` / `photo_access_denied`).
class AvatarPermissionDenied implements Exception {
  const AvatarPermissionDenied(this.source);

  final AvatarPhotoSource source;

  String get message => source == AvatarPhotoSource.camera
      ? 'Kamera izni yok. iPhone Ayarlar > Ritim\'den açabilirsin.'
      : 'Fotoğraf izni yok. iPhone Ayarlar > Ritim\'den açabilirsin.';

  @override
  String toString() => 'AvatarPermissionDenied($source)';
}

/// Fotoğraf kaynağı.
enum AvatarPhotoSource { camera, gallery }

/// Seçilen görüntünün ham baytları; vazgeçilirse null.
typedef AvatarImagePicker = Future<Uint8List?> Function(
    AvatarPhotoSource source);

final avatarImagePickerProvider = Provider<AvatarImagePicker>(
  (ref) => (source) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
      source: source == AvatarPhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
      );
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' || e.code == 'photo_access_denied') {
        throw AvatarPermissionDenied(source);
      }
      rethrow;
    }
    return file?.readAsBytes();
  },
);
