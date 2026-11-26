/// Sunucudaki serbest metin üst sınırları (schema.sql `guvenlik_limits`).
/// Yazmadan önce aynı sınırla kırpılır; böylece uzun yapıştırma kaydı bozmaz.
abstract final class TextLimits {
  static const int taskDescription = 4000;
  static const int taskAssignee = 120;
  static const int noteContent = 20000;
  static const int workoutTitle = 200;
  static const int workoutNotes = 2000;
  static const int quantityText = 200;
}

/// [text]'i en çok [max] karaktere (Unicode kod noktası) kırpar.
String? clipText(String? text, int max) {
  if (text == null || text.runes.length <= max) return text;
  return String.fromCharCodes(text.runes.take(max));
}
