import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/health/presentation/body/checkin_flow.dart';
import 'package:kisisel_asistan/features/health/presentation/health_segment.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/body_providers.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/streaks_providers.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_day_view.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_health_card.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';

import '../helpers/kokpit_fakes.dart';

StreakStatus streak(StreakKind kind, int current) => StreakStatus(
      kind: kind,
      current: current,
      best: current,
      today: StreakToday.done,
      days: const {},
    );

Override streaks(List<StreakStatus> list) => streaksProvider.overrideWith(
      (ref) async => StreaksState(streaks: list, lowIntake: false),
    );

Override checkin({required bool day, bool done = false}) =>
    checkinTodayProvider.overrideWith(
      (ref) async => CheckinToday(
        isCheckinDay: day,
        done: done,
        scheduleLine: 'Sonraki ölçü günü: Pazartesi · 7 gün kaldı',
      ),
    );

void main() {
  late KokpitHarness harness;

  setUpAll(() => initializeDateFormatting(AppDates.locale));

  setUp(() {
    harness = KokpitHarness()..mockPlatformChannel();
    harness.routines.routines = const [];
  });

  testWidgets('Sağlık kartı: kalan, yenen/hedef, adım ve seri satırı',
      (tester) async {
    await harness.pump(tester, overrides: [
      streaks([
        streak(StreakKind.steps, 7),
        streak(StreakKind.logging, 12),
        streak(StreakKind.deficit, 4),
      ]),
      checkin(day: false),
    ]);

    expect(find.text('Kalan 550 kcal'), findsOneWidget);
    expect(find.text('1.450 / 2.000 kcal'), findsOneWidget);
    expect(find.text('8.432 / 8.000 adım'), findsOneWidget);
    expect(find.text('Seriler: Adım 7 · Kayıt 12 · Açık 4'), findsOneWidget);
    expect(find.byType(KokpitRing), findsOneWidget);
    expect(find.text('Ölçü ve fotoğraf günü · ~3 dk'), findsNothing);
  });

  testWidgets('hedef aşılınca başlık "fazla" der', (tester) async {
    harness.kokpit.nutrition = const NutritionSummary(calories: 2350);
    await harness
        .pump(tester, overrides: [streaks(const []), checkin(day: false)]);
    expect(find.text('350 kcal fazla'), findsOneWidget);
    expect(find.byKey(const ValueKey('kokpit-streak-line')), findsNothing,
        reason: 'seri yoksa satır yok');
  });

  testWidgets('karta dokununca Sağlık > Bugün açılır', (tester) async {
    final container = await harness.pump(tester, overrides: [
      streaks(const []),
      checkin(day: false),
    ]);
    container.read(healthSegmentProvider.notifier).state = HealthSegment.plan;

    await tester.tap(find.byKey(const ValueKey('kokpit-health-card')));
    await tester.pump();

    expect(container.read(homeTabRequestProvider), kokpitHealthTab);
    expect(container.read(healthSegmentProvider), HealthSegment.today);
  });

  testWidgets('ölçü gününde listenin başında sistem satırı; sayaca girmez',
      (tester) async {
    await harness.pump(tester, overrides: [
      streaks(const []),
      checkin(day: true),
    ]);
    await harness.scrollThrough(tester);
    expect(find.text('Ölçü ve fotoğraf günü · ~3 dk'), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget,
        reason: 'ölçü satırı Günlük işler sayacına girmez');

    await tester.tap(find.byKey(const ValueKey('kokpit-checkin')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckinFlowScreen), findsOneWidget);
  });

  test('kokpitTodayItems: ölçü satırı en başta', () {
    final items = kokpitTodayItems(
      routines: const [],
      tasks: const [],
      now: DateTime(2026, 11, 23, 8),
      checkin: const KokpitCheckinItem(done: false),
    );
    expect(items.single, isA<KokpitCheckinItem>());
  });

  testWidgets('su kutusu ortak su durumunu artırır', (tester) async {
    await harness
        .pump(tester, overrides: [streaks(const []), checkin(day: false)]);
    expect(find.text('Su'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kokpit-water-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0,25 /'), findsOneWidget);
  });
}
