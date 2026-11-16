import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_providers.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeReportsRepository reports;

  final monday = DateTime(2026, 11, 9);

  WeeklyReport weekly(DateTime weekStart, {int rate = 70, String? summary = 'özet'}) =>
      WeeklyReport(
        weekStart: weekStart,
        metrics: ReportMetrics(workRate: rate),
        aiSummary: summary,
        aiStatus: summary == null ? ReportAiStatus.failed : ReportAiStatus.ok,
      );
  DailyReport daily(DateTime day, {int rate = 60}) => DailyReport(
        reportDate: day,
        metrics: ReportMetrics(workRate: rate),
        aiSummary: 'gün',
        aiStatus: ReportAiStatus.ok,
      );

  setUp(() => reports = FakeReportsRepository());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [reportsRepositoryProvider.overrideWithValue(reports)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('weeklyReportProvider', () {
    test('haftanın raporunu verir', () async {
      reports.weekly = [weekly(monday, rate: 78), weekly(DateTime(2026, 11, 2))];
      final container = makeContainer();
      final report = await container.read(weeklyReportProvider(monday).future);
      expect(report!.weekStart, monday);
      expect(report.metrics.workRate, 78);
    });

    test('rapor yoksa null (hata değil)', () async {
      final container = makeContainer();
      expect(await container.read(weeklyReportProvider(monday).future), isNull);
    });

    test('hafta içi bir gün verilirse o haftanın raporu', () async {
      reports.weekly = [weekly(monday)];
      final container = makeContainer();
      final report = await container
          .read(weeklyReportProvider(DateTime(2026, 11, 12, 15)).future);
      expect(report!.weekStart, monday);
    });

    test('okuma hatası iletilir', () async {
      reports.fetchError = Exception('ağ yok');
      final container = makeContainer();
      container.listen(weeklyReportProvider(monday), (_, __) {});
      await expectLater(
        container.read(weeklyReportProvider(monday).future),
        throwsException,
      );
    });
  });

  test('weeklyReportListProvider: yeniden eskiye', () async {
    reports.weekly = [
      weekly(DateTime(2026, 10, 26)),
      weekly(monday),
      weekly(DateTime(2026, 11, 2)),
    ];
    final container = makeContainer();
    final list = await container.read(weeklyReportListProvider.future);
    expect(list.map((r) => r.weekStart), [
      monday,
      DateTime(2026, 11, 2),
      DateTime(2026, 10, 26),
    ]);
  });

  group('dailyReportProvider', () {
    test('günün raporu; saat verilse de gün başına indirgenir', () async {
      reports.daily = [daily(DateTime(2026, 11, 15), rate: 88)];
      final container = makeContainer();
      final report = await container
          .read(dailyReportProvider(DateTime(2026, 11, 15, 23, 50)).future);
      expect(report!.metrics.workRate, 88);
    });

    test('rapor yoksa null', () async {
      final container = makeContainer();
      expect(
        await container.read(dailyReportProvider(DateTime(2026, 11, 15)).future),
        isNull,
      );
    });
  });

  group('dailyReportListProvider', () {
    test('aralık iki uç dahil, yeniden eskiye', () async {
      reports.daily = [
        for (var d = 8; d <= 16; d++) daily(DateTime(2026, 11, d)),
      ];
      final container = makeContainer();
      final range = lastSevenDays(DateTime(2026, 11, 15, 12));
      expect(range, (from: DateTime(2026, 11, 9), to: DateTime(2026, 11, 15)));
      final list = await container.read(dailyReportListProvider(range).future);
      expect(list.map((r) => r.reportDate.day), [15, 14, 13, 12, 11, 10, 9]);
    });

    test('aynı aralık aynı önbellek girdisidir (kayıt eşitliği)', () {
      expect(
        dailyReportListProvider(lastSevenDays(DateTime(2026, 11, 15))),
        dailyReportListProvider(lastSevenDays(DateTime(2026, 11, 15, 9))),
      );
    });
  });

  group('regenerateReport', () {
    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      ReportKind kind,
      DateTime date,
      void Function(Object error) onError,
    ) async {
      final container = makeContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  try {
                    await regenerateReport(ref, kind, date);
                  } catch (e) {
                    onError(e);
                  }
                },
                child: const Text('yeniden oluştur'),
              ),
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('haftalık: depoyu çağırır, raporu ve listeyi tazeler', (tester) async {
      reports.weeklyBuilder = (weekStart) => weekly(weekStart, rate: 91);
      final container = await pumpHost(
        tester,
        ReportKind.weekly,
        DateTime(2026, 11, 11),
        (e) => fail('$e'),
      );
      container.listen(weeklyReportProvider(monday), (_, __) {});
      container.listen(weeklyReportListProvider, (_, __) {});
      await tester.pumpAndSettle();
      expect(container.read(weeklyReportProvider(monday)).value, isNull);
      expect(container.read(weeklyReportListProvider).value, isEmpty);

      await tester.tap(find.text('yeniden oluştur'));
      await tester.pumpAndSettle();

      expect(reports.regenerated, [(kind: ReportKind.weekly, date: monday)]);
      expect(container.read(weeklyReportProvider(monday)).value!.metrics.workRate, 91);
      expect(container.read(weeklyReportListProvider).value, hasLength(1));
    });

    testWidgets('günlük: günün raporunu ve aralık listesini tazeler', (tester) async {
      final day = DateTime(2026, 11, 15);
      reports.dailyBuilder = (d) => daily(d, rate: 44);
      final container =
          await pumpHost(tester, ReportKind.daily, day, (e) => fail('$e'));
      final range = lastSevenDays(day);
      container.listen(dailyReportProvider(day), (_, __) {});
      container.listen(dailyReportListProvider(range), (_, __) {});
      await tester.pumpAndSettle();
      expect(container.read(dailyReportProvider(day)).value, isNull);

      await tester.tap(find.text('yeniden oluştur'));
      await tester.pumpAndSettle();

      expect(reports.regenerated, [(kind: ReportKind.daily, date: day)]);
      expect(container.read(dailyReportProvider(day)).value!.metrics.workRate, 44);
      expect(container.read(dailyReportListProvider(range)).value, hasLength(1));
    });

    testWidgets('üretim bitene kadar eski rapor görünür', (tester) async {
      reports.weekly = [weekly(monday, rate: 50)];
      reports.weeklyBuilder = (weekStart) => weekly(weekStart, rate: 95);
      reports.regenerateGate = Completer<void>();
      final container =
          await pumpHost(tester, ReportKind.weekly, monday, (e) => fail('$e'));
      container.listen(weeklyReportProvider(monday), (_, __) {});
      await tester.pumpAndSettle();

      await tester.tap(find.text('yeniden oluştur'));
      await tester.pump();
      expect(container.read(weeklyReportProvider(monday)).value!.metrics.workRate, 50);

      reports.regenerateGate!.complete();
      await tester.pumpAndSettle();
      expect(container.read(weeklyReportProvider(monday)).value!.metrics.workRate, 95);
    });

    testWidgets('hata çağırana iletilir ve veriler yine tazelenir', (tester) async {
      reports.weekly = [weekly(monday, rate: 50)];
      reports.regenerateError =
          const ReportGenerationException('Rapor oluşturulamadı.');
      Object? caught;
      final container =
          await pumpHost(tester, ReportKind.weekly, monday, (e) => caught = e);
      container.listen(weeklyReportProvider(monday), (_, __) {});
      await tester.pumpAndSettle();

      // Sunucu sayıları yazıp yorumda takılmış olabilir: okuma yenilenmeli.
      reports.weekly = [weekly(monday, rate: 61, summary: null)];
      await tester.tap(find.text('yeniden oluştur'));
      await tester.pumpAndSettle();

      expect(caught, isA<ReportGenerationException>());
      expect('$caught', 'Rapor oluşturulamadı.');
      final report = container.read(weeklyReportProvider(monday)).value!;
      expect(report.metrics.workRate, 61);
      expect(report.aiStatus, ReportAiStatus.failed);
    });
  });
}
