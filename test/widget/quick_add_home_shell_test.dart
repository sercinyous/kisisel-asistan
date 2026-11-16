import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_quick_add_modal.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/quick_add_mode_sheet.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/quick_add_fakes.dart';
import '../helpers/test_fonts.dart';

void main() {
  late QuickAddHarness harness;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    harness = QuickAddHarness(
      work: (_) async => ParsedEntry.fromJson(const {
        'routines': [
          {
            'title': 'Ekip toplantısı',
            'days_of_week': [1],
            'time_of_day': '11:00'
          },
        ],
      }),
      health: (_) async => ParsedEntry.fromJson(const {
        'weights': [
          {'weight_kg': 83.9},
        ],
      }),
    );

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('tr', 'TR'),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    // Alt bar etiketsizdir; sekmeler ipucu (tooltip) metniyle bulunur.
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapPlus(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Yeni giriş'));
    await tester.pumpAndSettle();
  }

  QuickAddMode? openModalMode(WidgetTester tester) {
    final modal = find.byType(AiQuickAddModal);
    if (modal.evaluate().isEmpty) return null;
    final inModal = find.descendant(
      of: modal,
      matching: find.text(QuickAddMode.work.title),
    );
    return inModal.evaluate().isNotEmpty
        ? QuickAddMode.work
        : QuickAddMode.health;
  }

  test('quickAddModeForTab: sekme -> giriş alanı', () {
    expect(quickAddModeForTab(0), isNull, reason: 'Kokpit sorar');
    expect(quickAddModeForTab(1), QuickAddMode.work, reason: 'Operasyon');
    expect(quickAddModeForTab(2), QuickAddMode.health, reason: 'Sağlık');
    expect(quickAddModeForTab(3), isNull, reason: 'Raporlar sorar');
  });

  testWidgets('Operasyon sekmesinde + doğrudan iş girişini açar',
      (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Operasyon');
    await tapPlus(tester);

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(openModalMode(tester), QuickAddMode.work);
  });

  testWidgets('Sağlık sekmesinde + doğrudan sağlık girişini açar',
      (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Sağlık');
    await tapPlus(tester);

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(openModalMode(tester), QuickAddMode.health);
  });

  for (final tab in ['Kokpit', 'Raporlar']) {
    testWidgets('$tab sekmesinde + seçim sayfasını açar', (tester) async {
      await pumpShell(tester);
      await selectTab(tester, tab);
      await tapPlus(tester);

      expect(find.byType(QuickAddModeSheet), findsOneWidget);
      expect(find.byType(AiQuickAddModal), findsNothing);
      expect(find.text('Ne eklemek istersin?'), findsOneWidget);
      expect(find.text('İş girişi'), findsOneWidget);
      expect(find.text('Sağlık & beslenme girişi'), findsOneWidget);
    });
  }

  testWidgets('seçim sayfasında "İş girişi" iş girişini açar', (tester) async {
    await pumpShell(tester);
    await tapPlus(tester);
    await tester.tap(find.text('İş girişi'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(openModalMode(tester), QuickAddMode.work);
  });

  testWidgets(
      'seçim sayfasında "Sağlık & beslenme girişi" sağlık girişini açar',
      (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Raporlar');
    await tapPlus(tester);
    await tester.tap(find.text('Sağlık & beslenme girişi'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(openModalMode(tester), QuickAddMode.health);
  });

  testWidgets('seçim sayfası kapatılırsa giriş açılmaz', (tester) async {
    await pumpShell(tester);
    await tapPlus(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddModeSheet), findsNothing);
    expect(find.byType(AiQuickAddModal), findsNothing);
    expect(harness.repository.saved, isEmpty);
  });

  testWidgets('kayıt sonrası kaydedilen sayı bildirilir', (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Operasyon');
    await tapPlus(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(AiQuickAddModal),
        matching: find.byType(TextField),
      ),
      'Her pazartesi 11:00 ekip toplantısı',
    );
    await tester.pump();
    await tester.tap(find.text('Ayrıştır'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 kaydı kaydet'));
    await tester.pumpAndSettle();

    expect(find.byType(AiQuickAddModal), findsNothing);
    expect(find.text('1 kayıt eklendi.'), findsOneWidget);
    expect(harness.work.inputs, ['Her pazartesi 11:00 ekip toplantısı']);
    expect(harness.repository.saved.single.routines.single.title,
        'Ekip toplantısı');
  });
}
