import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/error_reporter.dart';
import 'package:kisisel_asistan/features/settings/domain/terms_text.dart';
import 'package:kisisel_asistan/features/settings/presentation/terms_screen.dart';

void main() {
  test('sürüm etiketi yapı numarasını parantezle gösterir', () {
    expect(appVersionLabel('1.2.0+14'), '1.2.0 (14)');
    expect(appVersionLabel('1.0.0'), '1.0.0');
    expect(appVersionLabel('1.0.0+'), '1.0.0+');
  });

  test('koşullar en düşük yaşı, engelleme ve tıbbi uyarıyı içerir', () {
    final text =
        termsSections.expand((s) => s.paragraphs).join('\n');
    expect(text, contains('13 yaş'));
    expect(text, contains('Engelle'));
    expect(text, contains('tıbbi tavsiye'));
  });

  testWidgets('koşullar ekranı tüm bölüm başlıklarını gösterir',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LegalTextScreen.terms()),
    );
    expect(find.text('Kullanım koşulları'), findsOneWidget);
    expect(find.text(termsSections.first.title), findsOneWidget);
  });
}
