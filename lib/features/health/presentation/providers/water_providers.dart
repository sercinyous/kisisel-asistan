import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../water_providers.dart';
import 'targets_providers.dart';

export '../water_providers.dart';

/// Tek su durumu: Sağlık kartı ve Kokpit'in `WaterTracker`'ı aynı
/// sağlayıcıyı paylaşır.
final waterProvider = waterTodayProvider;

/// Kiloya göre önerilen günlük su: min(kg × 35, 4.000) ml.
final recommendedWaterMlProvider = FutureProvider<int?>((ref) async {
  final weight = await ref.watch(latestWeightProvider.future);
  return weight == null ? null : recommendedWaterMl(weight.weightKg);
});
