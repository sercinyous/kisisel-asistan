import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/domain/energy_balance.dart';
import 'package:kisisel_asistan/features/health/domain/goal_mode.dart';
import 'package:kisisel_asistan/features/health/domain/targets_engine.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/targets_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/today/day_balance_card.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

ResolvedTargets _resolved(GoalMode goal) => resolveTargets(
      settings: const UserSettings.defaults().copyWith(
        goalMode: goal,
        expenditureKcalManual: 2800,
        targetWeightKg: 75,
        heightCm: 180,
        birthYear: 1990,
        sex: 'male',
      ),
      latestWeightKg: 80,
      age: 36,
      sex: Sex.male,
    );

Future<Color?> _pumpLine(WidgetTester tester, GoalMode goal) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      todayDeficitProvider.overrideWith((ref) async => -300),
      resolvedTargetsProvider.overrideWith((ref) async => _resolved(goal)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: DayDeficitLine()),
    ),
  ));
  await tester.pumpAndSettle();
  final text = tester.widget<Text>(find.byKey(const Key('day-deficit')));
  expect(text.data, startsWith('Kalori fazlası (şu ana kadar)'));
  return text.style?.color;
}

void main() {
  testWidgets('yağ yakmada fazla uyarı renginde', (tester) async {
    expect(await _pumpLine(tester, GoalMode.fatLoss), AppColors.warning);
  });

  testWidgets('kas yapmada fazla hedeftir: uyarı rengi yok', (tester) async {
    expect(await _pumpLine(tester, GoalMode.leanGain), AppColors.textPrimary);
  });
}
