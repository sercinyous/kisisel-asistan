import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kullanıcıya giden AI/giriş hata iletileri "sen" diliyle yazılır; satıcı
/// adı, HTTP kodu ya da ham sunucu metni içermez.
void main() {
  const files = [
    'lib/features/ai_quick_add/data/gemini_parser_service.dart',
    'lib/features/ai_quick_add/presentation/ai_quick_add_controller.dart',
    'lib/features/auth/domain/sign_in_messages.dart',
    'lib/features/reminders/domain/reminder.dart',
  ];
  final literal = RegExp(r"'([^'\n]*)'");

  for (final path in files) {
    test('$path iletileri resmi dil ve ham hata içermez', () {
      final src = File(path).readAsStringSync();
      for (final m in literal.allMatches(src)) {
        final text = m.group(1)!;
        expect(text.contains('deneyin'), isFalse, reason: text);
        expect(text.contains('Lütfen'), isFalse, reason: text);
        expect(text.contains(r'${e.message}'), isFalse, reason: text);
        expect(text.contains(r'${error.message}'), isFalse, reason: text);
      }
    });
  }

  test('AI kota/zaman aşımı iletileri satıcı adı ve kod içermez', () {
    final src =
        File('lib/features/ai/data/gemini_transport.dart').readAsStringSync();
    for (final s in [
      'Bugünkü AI hakkın doldu',
      'Şu an yanıt alınamadı',
      'Bu metin işlenemedi',
    ]) {
      expect(src.contains(s), isTrue, reason: s);
    }
    expect(src.contains('Gemini kota'), isFalse);
    expect(src.contains('(400)'), isFalse);
    expect(src.contains('deneyin'), isFalse);
  });
}
