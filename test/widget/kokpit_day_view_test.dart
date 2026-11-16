import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_format.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_screen.dart';

import '../helpers/kokpit_fakes.dart';
import '../helpers/test_fonts.dart';

DateTime today() => AppDates.startOfDay(DateTime.now());
DateTime thisMonth() => DateTime(today().year, today().month);
int daysInThisMonth() => DateTime(today().year, today().month + 1, 0).day;

Routine daily(String id, String title, {String? time}) => Routine.fromMap({
      'id': id,
      'title': title,
      'category': 'operasyon',
      'time_of_day': time,
    });

Routine monthly(String id, String title, int day, {int? hour}) => Routine(
      id: id,
      title: title,
      scope: Routine.scopeWork,
      category: 'finans',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: day,
      hour: hour,
      minute: hour == null ? null : 0,
    );

void main() {
  late KokpitHarness harness;
  late bool realFonts;

  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    realFonts = await loadRealFonts();
  });

  setUp(() {
    harness = KokpitHarness()..mockPlatformChannel();
    harness.routines.routines = [
      daily('r1', 'Sabah push performans kontrolü', time: '09:00:00'),
      daily('r2', 'Editör vardiya kontrolü'),
      monthly('m1', 'Maaş ödemeleri', today().day, hour: 10),
    ];
  });

  group('Gün görünümü', () {
    testWidgets('günlük rutinler ve aylık işler ayrı bölümlerde',
        (tester) async {
      await harness.pump(tester);

      expect(find.text('Gün'), findsOneWidget);
      expect(find.text('Ay'), findsOneWidget);
      expect(find.text('Bugünün rutinleri'), findsOneWidget);
      expect(find.text('0 / 2'), findsOneWidget,
          reason: 'aylık iş günlük sayaca girmez');
      expect(find.text('Sabah push performans kontrolü'), findsOneWidget);

      expect(find.text('Yaklaşan aylık işler'), findsOneWidget);
      expect(find.text('1 açık'), findsOneWidget);
      expect(find.text('Maaş ödemeleri'), findsOneWidget);
      expect(find.text('Bugün'), findsOneWidget);
      expect(
        find.text('${KokpitFormat.dayMonth(today())} · 10:00'),
        findsOneWidget,
      );
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
    });

    testWidgets('durum metni: gün kaldı / gecikti', (tester) async {
      final day = today().day;
      final extra = <Routine>[];
      // Ay sınırına yakın günlerde ilgili örnek kurulamaz; o satır atlanır.
      final hasUpcoming = day + 2 <= daysInThisMonth();
      final hasOverdue = day - 2 >= 1;
      if (hasUpcoming) extra.add(monthly('m2', 'Kira ödemesi', day + 2));
      if (hasOverdue) extra.add(monthly('m3', 'KDV beyannamesi', day - 2));
      harness.routines.routines = [...harness.routines.routines, ...extra];

      await harness.pump(tester);

      if (hasUpcoming) {
        expect(find.text('Kira ödemesi'), findsOneWidget);
        expect(find.text('2 gün kaldı'), findsOneWidget);
      }
      if (hasOverdue) {
        expect(find.text('KDV beyannamesi'), findsOneWidget);
        expect(find.text('2 gün gecikti'), findsOneWidget);
      }
      expect(find.text('${1 + extra.length} açık'), findsOneWidget);
    });

    testWidgets('pencere dışındaki aylık iş listelenmez; ayar değişince girer',
        (tester) async {
      final day = today().day;
      if (day + 5 > daysInThisMonth()) {
        markTestSkipped('Ay sonuna 5 günden az kaldı');
        return;
      }
      harness.routines.routines = [
        monthly('m9', 'Aylık push performans raporu', day + 5),
      ];
      await harness.pump(tester);
      expect(find.text('Yaklaşan aylık işler'), findsNothing);
      expect(find.text('Aylık push performans raporu'), findsNothing);
    });

    testWidgets('monthly_lead_days ayarı pencereyi genişletir', (tester) async {
      final day = today().day;
      if (day + 5 > daysInThisMonth()) {
        markTestSkipped('Ay sonuna 5 günden az kaldı');
        return;
      }
      harness.settings.settings =
          const UserSettings.defaults().copyWith(monthlyLeadDays: 7);
      harness.routines.routines = [
        monthly('m9', 'Aylık push performans raporu', day + 5),
      ];
      await harness.pump(tester);
      expect(find.text('Aylık push performans raporu'), findsOneWidget);
      expect(find.text('5 gün kaldı'), findsOneWidget);
    });

    testWidgets('aylık iş yoksa bölüm çizilmez', (tester) async {
      harness.routines.routines = [daily('r1', 'Tek rutin')];
      await harness.pump(tester);
      expect(find.text('Bugünün rutinleri'), findsOneWidget);
      expect(find.text('Yaklaşan aylık işler'), findsNothing);
    });

    testWidgets('"Bugün ve yaklaşanlar" bugünün saati geçmiş açık işini de '
        'gösterir', (tester) async {
      harness.tasks.tasks = [
        TaskItem(
          id: 't0',
          title: 'Sabah toplantısı',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today(),
        ),
        TaskItem(
          id: 't1',
          title: 'Dünkü iş',
          category: 'Ekip',
          priority: 'medium',
          status: 'todo',
          dueAt: today().subtract(const Duration(hours: 5)),
        ),
      ];
      await harness.pump(tester);
      await harness.scrollThrough(tester);
      expect(find.text('Bugün ve yaklaşanlar'), findsOneWidget);
      expect(find.text('Sabah toplantısı'), findsOneWidget);
      expect(find.text('Dünkü iş'), findsNothing);
    });
  });

  group('aylık işi Gün görünümünden işaretleme', () {
    testWidgets('iyimser işaretlenir, dönem anahtarı ayın 1\'idir',
        (tester) async {
      harness.routines.toggleGate = Completer<void>();
      final container = await harness.pump(tester);

      await tester.ensureVisible(find.text('Maaş ödemeleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maaş ödemeleri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.routines.toggles, [
        (routineId: 'm1', periodKey: thisMonth(), completed: true),
      ]);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue,
          reason: 'sunucu onayı beklenmeden');
      expect(find.text('Yapıldı'), findsOneWidget);
      expect(find.text('0 / 2'), findsOneWidget,
          reason: 'günlük sayaç etkilenmez');

      harness.routines.toggleGate!.complete();
      await tester.pumpAndSettle();
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        container.read(todayOccurrencesProvider).value!.monthly.single.status,
        OccurrenceStatus.done,
      );
    });

    testWidgets('işaretlenen iş Ay görünümünde de "Yapıldı" olur; geri alınca '
        'ikisi de güncellenir', (tester) async {
      await harness.pump(tester);
      await harness.tapRow(tester, 'Maaş ödemeleri');
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);

      await harness.showView(tester, 'Ay');
      expect(find.text('Aylık sabitler'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);
      expect(find.text('Yapıldı'), findsOneWidget);

      await harness.showView(tester, 'Gün');
      await harness.tapRow(tester, 'Maaş ödemeleri');
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
      expect(harness.routines.completions, isEmpty);

      await harness.showView(tester, 'Ay');
      expect(find.text('0 / 1'), findsOneWidget);
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
    });

    testWidgets('sunucu hatasında geri alınır ve kullanıcı uyarılır',
        (tester) async {
      harness.routines.toggleGate = Completer<void>();
      await harness.pump(tester);

      await tester.ensureVisible(find.text('Maaş ödemeleri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maaş ödemeleri'));
      await tester.pump();
      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isTrue);

      harness.routines.toggleGate!.completeError(Exception('ağ yok'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(harness.isChecked(tester, 'Maaş ödemeleri'), isFalse);
      expect(find.text('Aylık iş güncellenemedi. Tekrar dene.'), findsOneWidget);
    });
  });

  group('başlık', () {
    testWidgets('dişli Ayarlar ekranını açar', (tester) async {
      await harness.pump(tester);
      expect(find.byType(SettingsScreen), findsNothing);

      await tester.tap(find.byTooltip('Ayarlar'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Bugünün rutinleri'), findsOneWidget);
    });

    testWidgets('görünüm seçimi Gün ↔ Ay arasında geçer', (tester) async {
      await harness.pump(tester);
      await harness.showView(tester, 'Ay');
      expect(find.text('Bugünün rutinleri'), findsNothing);
      expect(find.text(KokpitFormat.monthTitle(thisMonth())), findsOneWidget);
      expect(find.text('Ay özeti', skipOffstage: false), findsOneWidget);

      await harness.showView(tester, 'Gün');
      expect(find.text('Bugünün rutinleri'), findsOneWidget);
      expect(find.text('Ay özeti', skipOffstage: false), findsNothing);
    });
  });

  // Gerçek yazı tipi (Roboto) ile ölçülür; 375x667 = iPhone SE.
  group('Gün görünümü taşma yok (aylık işlerle)', () {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('375x667, metin ölçeği $scale', (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK önbelleğinde Roboto bulunamadı');
          return;
        }
        final day = today().day;
        harness.routines.routines = [
          ...harness.routines.routines,
          monthly(
            'm2',
            'Aylık push performans raporunun hazırlanması ve ekiple paylaşımı',
            day > 2 ? day - 2 : day,
            hour: 10,
          ),
          monthly(
            'm3',
            'Kira',
            day + 2 <= daysInThisMonth() ? day + 2 : day,
          ),
        ];
        harness.tasks.tasks = [
          TaskItem(
            id: 't1',
            title: 'Push bildirim performans raporunu hazırla ve ekip ile '
                'paylaş, ardından haftalık toplantıda sun',
            category: 'Pusholder',
            priority: 'high',
            status: 'todo',
            assignee: 'Mehmet',
            dueAt: DateTime(2099, 1, 6, 12),
          ),
        ];
        await harness.pump(tester, textScale: scale);
        expect(await harness.scrollThrough(tester), isEmpty);

        await harness.tapRow(
          tester,
          'Aylık push performans raporunun hazırlanması ve ekiple paylaşımı',
        );
        expect(await harness.scrollThrough(tester), isEmpty);
      });
    }
  });
}
