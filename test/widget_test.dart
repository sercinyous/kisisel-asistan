import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/app.dart';

// Bu dosya bilerek depoda durur: `flutter create .` mevcut dosyanın üzerine
// yazmadığı için bozuk sayaç şablonu testini projeye ekleyemez.
void main() {
  testWidgets('ConfigErrorApp eksik anahtarları gösterir', (tester) async {
    await tester.pumpWidget(
      const ConfigErrorApp(missingKeys: ['SUPABASE_URL']),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
