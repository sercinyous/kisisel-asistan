import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../settings/presentation/settings_providers.dart';
import '../../data/body_repository.dart';
import '../../domain/checkin.dart';
import '../trend_providers.dart' show trendClockProvider;

export '../../data/body_repository.dart';
export '../../domain/checkin.dart';

/// Tüm mezura ölçüleri, eskiden yeniye.
final measurementsProvider = FutureProvider<List<BodyMeasurement>>(
  (ref) => ref.watch(bodyRepositoryProvider).fetchMeasurements(),
);

/// Alan başına son değer ve farklar (Vücut > Ölçüler kartı).
final measurementSummaryProvider =
    FutureProvider<List<BodyFieldSummary>>((ref) async {
  return summarizeMeasurements(await ref.watch(measurementsProvider.future));
});

/// Tüm ilerleme fotoğrafları, yeniden eskiye.
final progressPhotosProvider = FutureProvider<List<ProgressPhoto>>(
  (ref) => ref.watch(bodyRepositoryProvider).fetchPhotos(),
);

/// Kontrol günlerine göre gruplu fotoğraflar, yeniden eskiye.
final photoCheckinsProvider = FutureProvider<List<PhotoCheckin>>((ref) async {
  return groupPhotos(await ref.watch(progressPhotosProvider.future));
});

/// Bir fotoğrafın 10 dakikalık imzalı adresi; ekrandan çıkınca atılır.
final photoUrlProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, path) {
  final link = ref.keepAlive();
  // İmza 10 dakikada biter; 9 dakika sonra yeniden imzalanır.
  final timer = Future<void>.delayed(const Duration(minutes: 9), link.close);
  ref.onDispose(() => timer.ignore());
  return ref.watch(bodyRepositoryProvider).signedUrl(path);
});

/// Bugünün ölçü günü durumu.
class CheckinToday {
  const CheckinToday({
    required this.isCheckinDay,
    required this.done,
    required this.scheduleLine,
  });

  final bool isCheckinDay;

  /// Bugün ölçü ya da fotoğraf satırı var.
  final bool done;

  /// "Sonraki ölçü günü: Pazartesi · 3 gün kaldı"
  final String scheduleLine;

  /// Banner (ölçü günü ve yapılmadı); kapatma o güne özeldir (arayüz tutar).
  bool get showBanner => isCheckinDay && !done;
}

final checkinTodayProvider = FutureProvider<CheckinToday>((ref) async {
  final settings = ref.watch(settingsOrDefaultProvider);
  final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
  final results = await Future.wait<List<Object>>([
    ref.watch(measurementsProvider.future),
    ref.watch(progressPhotosProvider.future),
  ]);
  final measurements = results[0] as List<BodyMeasurement>;
  final photos = results[1] as List<ProgressPhoto>;
  return CheckinToday(
    isCheckinDay: isCheckinDay(settings, today),
    done: isCheckinDone(
      hasMeasurement: measurements.any((m) => m.measuredOn == today),
      hasPhoto: photos.any((p) => p.takenOn == today),
    ),
    scheduleLine: checkinScheduleLine(settings, today),
  );
});

/// Ölçü/fotoğraf değişince Vücut sağlayıcılarını yeniler.
void invalidateBodyData(ProviderContainer container) {
  container
    ..invalidate(measurementsProvider)
    ..invalidate(progressPhotosProvider);
}
