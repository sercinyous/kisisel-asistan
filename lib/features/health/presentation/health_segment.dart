import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sağlık sekmesinin alt görünümleri: Bugün · Vücut · Plan.
enum HealthSegment {
  today('Bugün'),
  body('Vücut'),
  plan('Plan');

  const HealthSegment(this.label);

  final String label;
}

/// Sağlık sekmesinde seçili alt görünüm. Başka ekranlar (ör. Kokpit) bunu
/// ayarlayıp Sağlık sekmesine geçerek istenen görünümü doğrudan açabilir.
final healthSegmentProvider =
    StateProvider<HealthSegment>((ref) => HealthSegment.today);
