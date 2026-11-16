import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/quick_add_mode_sheet.dart';

import '../helpers/test_fonts.dart';

/// Seçim sayfasını açan sayfa; dönen değeri saklar.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  QuickAddMode? result;
  bool closed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final value = await QuickAddModeSheet.show(context);
            setState(() {
              result = value;
              closed = true;
            });
          },
          child: const Text('aç'),
        ),
      ),
    );
  }
}

void main() {
  late bool realFonts;

  setUpAll(() async => realFonts = await loadRealFonts());

  Future<_HostState> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const _Host()),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    return tester.state<_HostState>(find.byType(_Host));
  }

  testWidgets('iki seçenek kapsam açıklamalarıyla gösterilir', (tester) async {
    await open(tester);

    expect(find.text('Ne eklemek istersin?'), findsOneWidget);
    expect(find.text('İş girişi'), findsOneWidget);
    expect(find.text('Görev, randevu, not ya da tekrarlayan iş.'),
        findsOneWidget);
    expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);
    expect(find.text('Öğün, antrenman ya da kilo.'), findsOneWidget);
  });

  testWidgets('"İş girişi" work döndürür', (tester) async {
    final host = await open(tester);
    await tester.tap(find.text('İş girişi'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(host.result, QuickAddMode.work);
  });

  testWidgets('"Sağlık & beslenme girişi" health döndürür', (tester) async {
    final host = await open(tester);
    await tester.tap(find.text('Sağlık & beslenme girişi'));
    await tester.pumpAndSettle();

    expect(host.result, QuickAddMode.health);
  });

  testWidgets('dışına dokunulursa seçim yapılmadan kapanır', (tester) async {
    final host = await open(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(host.closed, isTrue);
    expect(host.result, isNull);
  });

  testWidgets('375pt genişlik ve 1.3 metin ölçeğinde taşmaz', (tester) async {
    if (!realFonts) return markTestSkipped('Roboto bulunamadı');
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(375, 667) * 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await open(tester);

    expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
