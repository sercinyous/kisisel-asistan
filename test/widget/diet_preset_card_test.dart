import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/presentation/diet_preset_card.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/targets_providers.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';

const _p = DietPreset.highProtein1800;

Future<void> _pump(
  WidgetTester tester, {
  required UserSettings settings,
  PresetBlock? block,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsOrDefaultProvider.overrideWithValue(settings),
      presetCheckProvider(_p).overrideWith((ref) async =>
          PresetCheck(preset: _p, floorKcal: 1650, block: block)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: SingleChildScrollView(child: DietPresetCard()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('etiket, makrolar ve 4 öğünlük menü görünür', (tester) async {
    await _pump(tester, settings: const UserSettings.defaults());
    expect(find.text('1800 kcal · Yüksek protein'), findsOneWidget);
    expect(find.text('P 150 g'), findsOneWidget);
    expect(find.textContaining('Kahvaltı ·'), findsOneWidget);
    expect(find.textContaining('Öğle ·'), findsOneWidget);
    expect(find.textContaining('Akşam ·'), findsOneWidget);
    expect(find.textContaining('Ara öğün ·'), findsOneWidget);
    expect(find.byKey(const Key('preset-apply')), findsOneWidget);
    expect(find.byKey(const Key('preset-warning')), findsNothing);
  });

  testWidgets('taban altında: uyarı görünür, düğme kapalı', (tester) async {
    await _pump(tester,
        settings: const UserSettings.defaults(), block: PresetBlock.belowFloor);
    expect(find.byKey(const Key('preset-warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preset-apply')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dokununca onay sorulur', (tester) async {
    await _pump(tester, settings: const UserSettings.defaults());
    await tester.tap(find.byKey(const Key('preset-apply')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.text('1800 kcal · Yüksek protein uygulansın mı?'), findsOneWidget);
  });

  testWidgets('paket etkinse "Önceki plana dön" görünür', (tester) async {
    await _pump(
      tester,
      settings: const UserSettings.defaults().copyWith(
        dailyCalories: 1800,
        dailyProteinG: 150,
        dailyCarbsG: 165,
        dailyFatG: 60,
        targetsSource: TargetsSource.manual,
      ),
    );
    expect(find.byKey(const Key('preset-return')), findsOneWidget);
    expect(find.text('Etkin'), findsOneWidget);
  });
}
