import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/fat_loss_screen.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

Future<FakeSettingsRepository> _pump(
  WidgetTester tester, {
  List<WeightEntry> weights = const [],
  UserSettings settings = const UserSettings.defaults(),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeSettingsRepository(settings: settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthRepositoryProvider
            .overrideWithValue(FakeHealthRepository(weights: [...weights])),
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const FatLossScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

WeightEntry _weight(double kg) => WeightEntry(
      id: 'w1',
      weightKg: kg,
      loggedAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

void main() {
  testWidgets('kilo yoksa boş durum ve Kilo ekle', (tester) async {
    await _pump(tester);
    expect(find.text('Planı hesaplamak için bir kilo ölçümü gerekli.'),
        findsOneWidget);
    expect(find.byKey(const Key('fat-loss-add-weight')), findsOneWidget);
    expect(find.text(fatLossDisclaimer), findsOneWidget);
  });

  testWidgets('kiloyla hedefler, karşılıklar ve menü', (tester) async {
    await _pump(tester, weights: [_weight(84)]);
    expect(find.text('2.184'), findsOneWidget);
    expect(find.text('168 g'), findsOneWidget);
    expect(find.text('216 g'), findsOneWidget);
    expect(find.text('Tavuk göğsü · 540 g'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-menu-total')), findsOneWidget);
    expect(find.text(fatLossDisclaimer), findsOneWidget);
    // Varsayılan harcama 3000: 816 kcal açık → 0,74 kg/hafta, uyarı yok.
    expect(find.text('≈ 0,7 kg/hafta'), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-warning')), findsNothing);
    expect(find.text(fatLossWaterNote), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byType(SegmentedButton<FatLossMacro>),
      matching: find.text('Yağ'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Zeytinyağı · 5 yemek kaşığı'), findsOneWidget);
  });

  testWidgets('haftada 0,8 kg üstünde uyarı', (tester) async {
    // 60 kg → 1560 kcal; 3000 harcama → 1440 açık → 1,3 kg/hafta.
    await _pump(tester, weights: [_weight(60)]);
    expect(find.byKey(const Key('fat-loss-warning')), findsOneWidget);
    expect(find.text(fatLossFastWarning), findsOneWidget);
  });

  testWidgets('açık yoksa kayıp yok açıklaması', (tester) async {
    // 120 kg → 3120 kcal > 3000.
    await _pump(tester, weights: [_weight(120)]);
    expect(find.byKey(const Key('fat-loss-no-loss')), findsOneWidget);
    expect(find.byKey(const Key('fat-loss-warning')), findsNothing);
  });

  testWidgets('hedefleri ayarla: onay sonrası yalnızca makrolar yazılır',
      (tester) async {
    final repo = await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Hedefler güncellensin mi?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fat-loss-apply-confirm')));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    final s = repo.saved.single;
    const d = UserSettings.defaults();
    expect(s.dailyCalories, 2184);
    expect(s.dailyProteinG, 168);
    expect(s.dailyFatG, 72);
    expect(s.dailyCarbsG, 216);
    expect(s.dailySteps, d.dailySteps);
    expect(s.targetWeightKg, d.targetWeightKg);
    expect(find.text('Hedefler güncellendi'), findsOneWidget);
  });

  testWidgets('vazgeçince kaydedilmez', (tester) async {
    final repo = await _pump(tester, weights: [_weight(84)]);
    await tester.tap(find.byKey(const Key('fat-loss-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
  });
}
