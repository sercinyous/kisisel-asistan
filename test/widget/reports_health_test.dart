import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/presentation/health_providers.dart'
    show weightSeriesProvider;
import 'package:kisisel_asistan/features/health/presentation/providers/body_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/streaks_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/week_deficit_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_health.dart';

WeightEntry w(DateTime at, double kg) =>
    WeightEntry(id: at.toIso8601String(), weightKg: kg, loggedAt: at);

BodyMeasurement m(DateTime on, Map<BodyField, double> values) =>
    BodyMeasurement(measuredOn: on, values: values);

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  group('saf yardımcılar', () {
    test('açık etiketi', () {
      expect(deficitLabel(3100), '−3.100 kcal');
      expect(deficitLabel(-400), '+400 kcal');
      expect(deficitLabel(0.2), '0 kcal');
      expect(deficitKgLabel(0.4), '≈0,4 kg');
      expect(deficitKgLabel(0), isNull);
    });

    test('dönem kilo farkı: önceki son tartıdan aralığın son tartısına', () {
      final series = [
        w(DateTime(2026, 11, 20, 8), 80.0),
        w(DateTime(2026, 11, 24, 8), 79.6),
        w(DateTime(2026, 11, 27, 8), 79.2),
      ];
      expect(
        periodWeightChange(
            series, DateTime(2026, 11, 23), DateTime(2026, 11, 29)),
        closeTo(-0.8, 1e-9),
      );
      expect(
        periodWeightChange(
            [series[1]], DateTime(2026, 11, 23), DateTime(2026, 11, 29)),
        isNull,
        reason: 'tek ölçüm fark vermez',
      );
    });

    test('ay ölçü farkı: "Bel −2,5 cm"', () {
      final list = [
        m(DateTime(2026, 10, 26), {BodyField.waist: 92, BodyField.hip: 104}),
        m(DateTime(2026, 11, 9), {BodyField.waist: 90.5}),
        m(DateTime(2026, 11, 23), {BodyField.waist: 89.5, BodyField.arm: 34}),
      ];
      final deltas = monthMeasurementDeltas(list, DateTime(2026, 11));
      expect(deltas.map(measurementDeltaLabel), ['Bel −2,5 cm']);
      expect(monthMeasurementDeltas(list, DateTime(2026, 9)), isEmpty);
    });
  });

  testWidgets('haftalık kart: açık, hedef, seriler ve kilo', (tester) async {
    final now = DateTime(2026, 11, 26, 12);
    final week = AppDates.weekStart(now);
    final deficit = WeekDeficit(
      weekStart: week,
      days: [
        for (var i = 0; i < 4; i++)
          DayDeficit(
            date: AppDates.addDays(week, i),
            deficit: 775,
            isToday: i == 3,
          ),
      ],
      targetKcal: 3850,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kokpitClockProvider.overrideWith((ref) => now),
        weekDeficitProvider(week).overrideWith((ref) async => deficit),
        streaksProvider.overrideWith((ref) async => const StreaksState(
              streaks: [
                StreakStatus(
                  kind: StreakKind.logging,
                  current: 12,
                  best: 12,
                  today: StreakToday.done,
                  days: {},
                ),
              ],
              lowIntake: false,
            )),
        weightSeriesProvider(reportsWeightLookbackDays).overrideWith(
          (ref) async => [
            w(DateTime(2026, 11, 20, 8), 80.0),
            w(DateTime(2026, 11, 25, 8), 79.6),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportsHealthWeekCard(weekStart: week),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('−3.100 kcal'), findsOneWidget);
    expect(find.text('≈0,4 kg'), findsOneWidget);
    expect(find.text('Hedef −3.850 kcal · %81'), findsOneWidget);
    expect(find.text('12 gün'), findsOneWidget);
    expect(find.text('Kayıt serisi'), findsOneWidget);
    expect(find.text('Kilo'), findsOneWidget);
    expect(find.textContaining('0,4 kg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('haftalık kart: kas yapmada fazla ve +hedef', (tester) async {
    final now = DateTime(2026, 11, 26, 12);
    final week = AppDates.weekStart(now);
    final deficit = WeekDeficit(
      weekStart: week,
      days: [
        for (var i = 0; i < 4; i++)
          DayDeficit(
            date: AppDates.addDays(week, i),
            deficit: -250,
            isToday: i == 3,
          ),
      ],
      targetKcal: 1750,
      surplusGoal: true,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kokpitClockProvider.overrideWith((ref) => now),
        weekDeficitProvider(week).overrideWith((ref) async => deficit),
        streaksProvider.overrideWith((ref) async =>
            const StreaksState(streaks: [], lowIntake: false)),
        weightSeriesProvider(reportsWeightLookbackDays)
            .overrideWith((ref) async => const <WeightEntry>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportsHealthWeekCard(weekStart: week),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Haftalık fazla'), findsOneWidget);
    expect(find.text('Haftalık açık'), findsNothing);
    expect(find.text('+1.000 kcal'), findsOneWidget);
    expect(find.text('≈0,1 kg'), findsOneWidget);
    expect(find.text('Hedef +1.750 kcal · %57'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
