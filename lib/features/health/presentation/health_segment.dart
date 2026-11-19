import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sağlık sekmesinin alt görünümleri.
enum HealthSegment {
  summary('Özet'),
  nutrition('Beslenme'),
  movement('Hareket');

  const HealthSegment(this.label);

  final String label;
}

/// Sağlık sekmesinde seçili alt görünüm. Başka ekranlar (ör. Kokpit) bunu
/// [HealthSegment.nutrition] yapıp Sağlık sekmesine geçerek Beslenme'yi
/// doğrudan açabilir.
final healthSegmentProvider =
    StateProvider<HealthSegment>((ref) => HealthSegment.summary);
