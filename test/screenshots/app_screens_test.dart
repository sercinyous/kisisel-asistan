// Önizleme için gerçek ekran görüntüleri üretir (örnek veriyle).
// Koyu tema: 01–15; açık tema aynı akışla 16–30 (`NN_acik_<ad>.png`).
// Çalıştırma: flutter test --update-goldens test/screenshots/app_screens_test.dart
@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/theme/theme_mode.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_data.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/quick_add_repository.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_quick_add_modal.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/health/presentation/health_screen.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_screen.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/quick_add_fakes.dart';
import '../helpers/test_fonts.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  // Açık temada dosya adı: numara 15 kaydırılır, araya "acik" eklenir.
  String lightName(String name) =>
      '${int.parse(name.substring(0, 2)) + 15}_acik_${name.substring(3)}';

  Future<void> capture(WidgetTester tester, {required bool light}) async {
    AppColors.palette = light ? AppPalette.light : AppPalette.dark;
    addTearDown(() => AppColors.palette = AppPalette.dark);

    // Tarayıcı demosuyla aynı örnek veri: önizleme ile demo aynı görünür.
    final now = DateTime.now();
    final today = AppDates.startOfDay(now);
    final demo = DemoData.seed(now);

    // Aile adı olmayan stil testte kare çizen "FlutterTest" yazı tipine düşer
    // (cihazda sistem yazı tipidir); buton etiketleri okunsun diye Roboto verilir.
    final base = light ? AppTheme.light : AppTheme.dark;
    final theme = base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStatePropertyAll(
            base.filledButtonTheme.style?.textStyle
                ?.resolve(const {})
                ?.copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
    );

    final parser = FakeGeminiParserService(
      (_) async => ParsedEntry.fromJson({
        'nutrition': [
          {
            'meal_type': 'lunch',
            'food_name': 'Tavuk göğsü',
            'quantity_text': '200 gr',
            'calories': 330,
            'protein_g': 62,
            'carbs_g': 0,
            'fat_g': 7,
            'eaten_at': today.add(const Duration(hours: 13)).toIso8601String(),
          },
          {
            'meal_type': 'lunch',
            'food_name': 'Tam çavdar ekmeği',
            'quantity_text': '2 dilim',
            'calories': 130,
            'protein_g': 5,
            'carbs_g': 24,
            'fat_g': 2,
            'eaten_at': today.add(const Duration(hours: 13)).toIso8601String(),
          },
        ],
      }),
    );

    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeModeProvider.overrideWithValue(
            light ? AppThemeMode.light : AppThemeMode.dark,
          ),
          geminiParserServiceProvider.overrideWith((ref, mode) => parser),
          quickAddRepositoryProvider
              .overrideWithValue(RecordingQuickAddRepository()),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          settingsRepositoryProvider.overrideWithValue(demo.settings),
          routinesRepositoryProvider.overrideWithValue(demo.routines),
          tasksRepositoryProvider.overrideWithValue(demo.tasks),
          notesRepositoryProvider.overrideWithValue(demo.notes),
          healthRepositoryProvider.overrideWithValue(demo.health),
          kokpitRepositoryProvider.overrideWithValue(demo.kokpit),
          reportsRepositoryProvider.overrideWithValue(demo.reports),
          healthServiceProvider.overrideWithValue(
            FakeHealthService(
              HealthSnapshot(
                status: HealthStatus.ok,
                steps: 6480,
                activeKcal: 412,
                sleepMinutes: 432,
                readAt: now,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('tr', 'TR')],
          locale: const Locale('tr', 'TR'),
          home: const RepaintBoundary(
            key: ValueKey('shot'),
            child: HomeShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('out/${light ? lightName(name) : name}.png'),
      );
    }

    await shot('01_kokpit_gun');

    await tester.tap(find.text('Ay'));
    await shot('02_kokpit_ay');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -620));
    await shot('03_kokpit_ay_alt');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gün'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Yeni giriş'));
    await shot('04_giris_secimi');
    await tester.tap(find.text('Sağlık & beslenme girişi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AiQuickAddModal),
        matching: find.byType(TextField),
      ),
      'Öğlen 200 gr tavuk göğsü ve 2 dilim tam çavdar ekmeği yedim',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayrıştır'));
    await shot('05_saglik_girisi');
    await tester.tap(find.byTooltip('Kapat').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Operasyon'));
    await shot('06_operasyon_gorevler');
    await tester.tap(find.text('Sabitler'));
    await shot('07_operasyon_sabitler');

    await tester.tap(find.byTooltip('Kokpit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ayarlar'));
    await shot('08_ayarlar');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    Finder scrollOf(Type screen) => find
        .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
        .first;

    await tester.tap(find.byTooltip('Sağlık'));
    await shot('09_saglik');
    await tester.drag(scrollOf(HealthScreen), const Offset(0, -560));
    await shot('10_saglik_ogunler');
    await tester.drag(scrollOf(HealthScreen), const Offset(0, -700));
    await shot('11_saglik_antrenman');

    await tester.tap(find.byTooltip('Raporlar'));
    // Biten son hafta: içinde bulunulan hafta Pazartesi günü neredeyse boştur.
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Önceki hafta'));
    await shot('12_raporlar_haftalik');
    await tester.drag(scrollOf(ReportsScreen), const Offset(0, -600));
    await shot('13_raporlar_haftalik_alt');
    await tester.drag(scrollOf(ReportsScreen), const Offset(0, 5000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Günlük'));
    await tester.pumpAndSettle();
    // Bugünün raporu gece üretilir; dolu görünüm için düne gidilir.
    await tester.tap(find.byTooltip('Önceki gün'));
    await shot('14_raporlar_gunluk');
    await tester.drag(scrollOf(ReportsScreen), const Offset(0, -600));
    await shot('15_raporlar_gunluk_alt');
  }

  // Görüntüler bugünün tarihine ve saatine bağlıdır; kayıtlı PNG'lerle
  // karşılaştırmak ertesi gün yanlış alarm verir. Bu dosya yalnızca
  // --update-goldens ile görüntü üretmek için çalışır.
  testWidgets(
    'ekran görüntüleri',
    (tester) => capture(tester, light: false),
    skip: !autoUpdateGoldenFiles,
  );

  testWidgets(
    'ekran görüntüleri (açık tema)',
    (tester) async {
      // Testlerde gölgeler düz çizilir; beyaz zeminde alt barın gölgesi
      // cihazdaki gibi (bulanık) görünsün diye burada açılır.
      debugDisableShadows = false;
      try {
        await capture(tester, light: true);
      } finally {
        debugDisableShadows = true;
      }
    },
    skip: !autoUpdateGoldenFiles,
  );
}
