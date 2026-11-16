import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_providers.dart';

import '../helpers/reports_fakes.dart';
import '../helpers/test_fonts.dart';

const fullSummary = 'İş tarafında güçlü bir hafta: görevlerin dörtte üçü '
    'kapandı, rutinler düzenli. Form tarafında perşembe ve cuma antrenmanları '
    'kaçtı, protein iki gün hedefin altında kaldı.\n'
    'Perşembe antrenmanını sabaha al.\n'
    'Öğle öğününe 30 g protein ekle.\n'
    'Maaş ödemeleri bu hafta: salı günü tamamla.';

IconButton arrow(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

FilledButton filledButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  late ReportsHarness harness;
  late bool realFonts;

  final thisWeek = ReportsHarness.thisWeek;
  final lastWeek = ReportsHarness.lastWeek;
  final today = ReportsHarness.today;
  final yesterday = AppDates.addDays(today, -1);

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  setUp(() => harness = ReportsHarness());

  group('haftalık görünüm', () {
    testWidgets('dolu rapor 375x667 ve metin ölçeği 1.3 ile taşmadan çizilir',
        (tester) async {
      if (!realFonts) {
        markTestSkipped('SDK yazı tipleri bulunamadı');
        return;
      }
      harness.reports.weekly = [
        weeklyReport(thisWeek, summary: fullSummary, workRate: 100),
        weeklyReport(lastWeek, workRate: 74, formRate: 80, weightChange: -0.5),
        weeklyReport(DateTime(2026, 10, 26), weightChange: null),
      ];
      await harness.pump(tester, textScale: 1.3);

      expect(find.text('Raporlar'), findsOneWidget);
      expect(find.text('16 – 22 Kasım'), findsOneWidget);
      expect(find.text('%100'), findsOneWidget);
      expect(find.text('%71'), findsOneWidget);
      expect(find.text('Görev 9 / 12 · Rutin %82'), findsOneWidget);
      expect(find.text('Antrenman 5 / 7 · Protein 5 gün'), findsOneWidget);

      await harness.expectNoOverflowWhileScrolling(tester);
      // Kaydırma sonunda listenin altı görünür.
      expect(find.text('Geçmiş haftalar'), findsOneWidget);
      expect(find.text('9 – 15 Kasım'), findsOneWidget);
      expect(find.text('İş %74 · Form %80 · −0,5 kg'), findsOneWidget);
      expect(find.text('26 Eki – 1 Kas'), findsOneWidget);
    });

    testWidgets('grafik, ortalamalar ve yorum taslaktaki içerikle gelir',
        (tester) async {
      final semantics = tester.ensureSemantics();
      harness.reports.weekly = [weeklyReport(thisWeek, summary: fullSummary)];
      await harness.pump(tester);

      expect(find.text('Günlük tamamlama'), findsOneWidget);
      // Seriler yalnızca renkle ayrılmaz: lejant etiketi + ekran okuyucu özeti.
      expect(find.text('İş'), findsWidgets);
      expect(find.text('Form'), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp(r'Pzt: iş %100, form %100')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(find.text('Aktif kalori'), 150);
      for (final text in const [
        'Ort. kalori',
        '1.960',
        'Ort. protein',
        '158 g',
        'Kilo',
        '−0,4 kg',
        'Ort. adım',
        '8.240',
        'Ort. uyku',
        '7 sa 05',
        'Aktif kalori',
        '430',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }

      await tester.scrollUntilVisible(
        find.text('Raporu yeniden oluştur'),
        150,
      );
      expect(find.text('Haftalık değerlendirme'), findsOneWidget);
      expect(find.textContaining('İş tarafında güçlü bir hafta'), findsOneWidget);
      expect(find.text('Perşembe antrenmanını sabaha al.'), findsOneWidget);
      expect(find.text('Öğle öğününe 30 g protein ekle.'), findsOneWidget);
      expect(find.text('Raporu yeniden oluştur'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('yorum üretilemediyse sayılar yine görünür', (tester) async {
      harness.reports.weekly = [weeklyReport(thisWeek, summary: null)];
      await harness.pump(tester);

      expect(find.text('%78'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Yorum üretilemedi'), 200);
      expect(find.text('Yorum üretilemedi'), findsOneWidget);
      expect(find.text('Raporu yeniden oluştur'), findsOneWidget);
    });

    testWidgets('rapor yoksa oluşturma çağrısı gösterilir', (tester) async {
      await harness.pump(tester);

      expect(find.text('Bu hafta için rapor henüz oluşmadı'), findsOneWidget);
      expect(find.text('Raporu oluştur'), findsOneWidget);
      expect(find.text('Raporu yeniden oluştur'), findsNothing);
      expect(find.text('Günlük tamamlama'), findsNothing);
    });

    testWidgets('gelecek haftaya gidilmez; geri ve ileri çalışır',
        (tester) async {
      harness.reports.weekly = [
        weeklyReport(thisWeek, workRate: 78),
        weeklyReport(lastWeek, workRate: 55),
      ];
      await harness.pump(tester);

      expect(find.text('16 – 22 Kasım'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);

      await tester.tap(find.byTooltip('Önceki hafta'));
      await tester.pumpAndSettle();
      expect(find.text('9 – 15 Kasım'), findsOneWidget);
      expect(find.text('%55'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Sonraki hafta'));
      await tester.pumpAndSettle();
      expect(find.text('16 – 22 Kasım'), findsOneWidget);
      expect(find.text('%78'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);
    });

    testWidgets('listeden geçmiş haftaya dokununca o hafta yüklenir',
        (tester) async {
      harness.reports.weekly = [
        weeklyReport(thisWeek),
        weeklyReport(lastWeek, workRate: 55, summary: 'Geçen haftanın özeti.'),
      ];
      await harness.pump(tester);

      await harness.tapKey(tester, 'reports-week-2026-11-09');

      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('9 – 15 Kasım'), findsOneWidget);
      expect(find.text('%55'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Geçen haftanın özeti.'), 200);
      expect(find.text('Geçen haftanın özeti.'), findsOneWidget);
      // Seçili hafta listede yer almaz; içinde bulunulan hafta listeye girer.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('reports-week-2026-11-16')),
        200,
      );
      expect(
        find.byKey(const ValueKey('reports-week-2026-11-09')),
        findsNothing,
      );
    });
  });

  group('yeniden oluşturma', () {
    testWidgets('doğru tür ve tarihle çağırır, meşgul olur, yeni özeti gösterir',
        (tester) async {
      harness.reports
        ..weekly = [weeklyReport(thisWeek, summary: 'Eski özet.')]
        ..weeklyBuilder =
            ((week) => weeklyReport(week, summary: 'Yeni özet.'))
        ..regenerateGate = Completer<void>();
      await harness.pump(tester);

      await harness.tapText(tester, 'Raporu yeniden oluştur');

      expect(harness.reports.regenerated, [
        (kind: ReportKind.weekly, date: thisWeek),
      ]);
      expect(find.text('Oluşturuluyor…'), findsOneWidget);
      expect(filledButton(tester).onPressed, isNull);
      expect(find.text('Eski özet.'), findsOneWidget);

      harness.reports.regenerateGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Yeni özet.'), findsOneWidget);
      expect(find.text('Eski özet.'), findsNothing);
      expect(find.text('Raporu yeniden oluştur'), findsOneWidget);
      expect(filledButton(tester).onPressed, isNotNull);
    });

    testWidgets('hata satır içinde gösterilir; tekrar dene başarıya ulaşır',
        (tester) async {
      harness.reports
        ..weekly = [weeklyReport(thisWeek, summary: 'Eski özet.')]
        ..weeklyBuilder =
            ((week) => weeklyReport(week, summary: 'Yeni özet.'))
        ..regenerateError =
            const ReportGenerationException('Bağlantı kurulamadı.');
      await harness.pump(tester);

      await harness.tapText(tester, 'Raporu yeniden oluştur');
      await tester.pumpAndSettle();

      expect(find.text('Bağlantı kurulamadı.'), findsOneWidget);
      expect(find.text('Eski özet.'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);

      harness.reports.regenerateError = null;
      await harness.tapText(tester, 'Tekrar dene');
      await tester.pumpAndSettle();

      expect(harness.reports.regenerated, hasLength(2));
      expect(find.text('Bağlantı kurulamadı.'), findsNothing);
      expect(find.text('Yeni özet.'), findsOneWidget);
    });

    testWidgets('rapor yokken "Raporu oluştur" raporu getirir', (tester) async {
      harness.reports.weeklyBuilder =
          (week) => weeklyReport(week, summary: 'İlk özet.');
      await harness.pump(tester);

      await harness.tapText(tester, 'Raporu oluştur');
      await tester.pumpAndSettle();

      expect(harness.reports.regenerated, [
        (kind: ReportKind.weekly, date: thisWeek),
      ]);
      expect(find.text('%78'), findsOneWidget);
      expect(find.text('Bu hafta için rapor henüz oluşmadı'), findsNothing);
    });
  });

  group('günlük görünüm', () {
    Future<void> openDaily(WidgetTester tester, {double textScale = 1.0}) async {
      await harness.pump(tester, textScale: textScale);
      await tester.tap(find.text('Günlük'));
      await tester.pumpAndSettle();
    }

    testWidgets('günün sayıları hedeflerle çizilir (ölçek 1.3, taşma yok)',
        (tester) async {
      if (!realFonts) {
        markTestSkipped('SDK yazı tipleri bulunamadı');
        return;
      }
      harness.reports.daily = [
        dailyReport(today, summary: 'Çarşamba özeti.', workRate: 100),
        dailyReport(yesterday),
      ];
      await openDaily(tester, textScale: 1.3);

      expect(find.text('18 Kasım Çarşamba'), findsOneWidget);
      expect(find.text('%100'), findsOneWidget);
      expect(find.text('Görev 2 / 3 · Rutin 5 / 7'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('/ 2.000 kcal'), 150);
      expect(find.text('1.840'), findsOneWidget);
      expect(find.text('148 g'), findsOneWidget);
      expect(find.text('/ 170 g'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('/ 10.000'), 150);
      expect(find.text('10.240'), findsOneWidget);
      expect(find.text('7 sa 05'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Çarşamba özeti.'), 150);
      expect(find.text('Günlük değerlendirme'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await harness.expectNoOverflowWhileScrolling(tester);
      expect(find.text('Son 7 gün'), findsOneWidget);
    });

    testWidgets('gün gezinme: geleceğe gidilmez, önceki gün yüklenir',
        (tester) async {
      harness.reports.daily = [
        dailyReport(today, summary: 'Çarşamba özeti.'),
        dailyReport(yesterday, summary: 'Salı özeti.', workRate: 40),
      ];
      await openDaily(tester);

      expect(find.text('18 Kasım Çarşamba'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNull);

      await tester.tap(find.byTooltip('Önceki gün'));
      await tester.pumpAndSettle();
      expect(find.text('17 Kasım Salı'), findsOneWidget);
      expect(find.text('%40'), findsOneWidget);
      expect(arrow(tester, Icons.chevron_right_rounded).onPressed, isNotNull);

      await tester.tap(find.byTooltip('Sonraki gün'));
      await tester.pumpAndSettle();
      expect(find.text('18 Kasım Çarşamba'), findsOneWidget);
    });

    testWidgets('son 7 gün listesinden güne gidilir', (tester) async {
      harness.reports.daily = [
        dailyReport(today),
        dailyReport(yesterday, workRate: 40),
      ];
      await openDaily(tester);

      await harness.tapKey(tester, 'reports-day-2026-11-17');
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(find.text('17 Kasım Salı'), findsOneWidget);
      expect(find.text('%40'), findsOneWidget);
    });

    testWidgets('rapor yoksa oluştur; günlük tür ve o günle çağrılır',
        (tester) async {
      harness.reports.dailyBuilder =
          (day) => dailyReport(day, summary: 'Bugünün özeti.');
      await openDaily(tester);

      expect(find.text('Bu gün için rapor henüz oluşmadı'), findsOneWidget);
      await harness.tapText(tester, 'Raporu oluştur');
      await tester.pumpAndSettle();

      expect(harness.reports.regenerated, [
        (kind: ReportKind.daily, date: today),
      ]);
      await tester.scrollUntilVisible(find.text('Bugünün özeti.'), 150);
      expect(find.text('Bugünün özeti.'), findsOneWidget);
    });
  });
}
