import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/app.dart';
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/theme/app_theme_scope.dart';
import 'package:kisisel_asistan/core/theme/theme_mode.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/core/widgets/app_bottom_bar.dart';
import 'package:kisisel_asistan/core/widgets/bento.dart';
import 'package:kisisel_asistan/demo/demo_data.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_screen.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/data/kokpit_repository.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_screen.dart';
import 'package:kisisel_asistan/features/operations/data/notes_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_screen.dart';
import 'package:kisisel_asistan/features/shell/presentation/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_fonts.dart';

/// Gerçek uygulamayla aynı kök: tercih → [AppThemeScope] → MaterialApp.
class _ThemedApp extends ConsumerWidget {
  const _ThemedApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppThemeScope(
      mode: ref.watch(themeModeProvider),
      builder: (context, theme) => MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    );
  }
}

/// `const` kurulur, `Theme.of` çağırmaz; rengi yalnızca AppColors'tan okur.
class _ConstProbe extends StatelessWidget {
  const _ConstProbe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds++;
    return ColoredBox(
      key: const Key('probe-box'),
      color: AppColors.background,
      // Kendi katmanında: üst bileşen boyansa da kendiliğinden boyanmaz.
      child: const RepaintBoundary(
        child: CustomPaint(
          painter: _PalettePainter(),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Rengi boyama anında okur ve "yeniden boyama gerekmez" der.
class _PalettePainter extends CustomPainter {
  const _PalettePainter();

  static Color? lastPainted;

  @override
  void paint(Canvas canvas, Size size) {
    lastPainted = AppColors.accent;
    canvas.drawCircle(
      size.center(Offset.zero),
      8,
      Paint()..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_PalettePainter oldDelegate) => false;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting(AppDates.locale);
    await loadRealFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _ConstProbe.builds = 0;
    _PalettePainter.lastPainted = null;
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

  // Palet süreç genelinde tektir; sonraki teste koyu bırakılır.
  tearDown(() => AppColors.palette = AppPalette.dark);

  void usePhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  /// Örnek veriyle çalışan uygulama bağımlılıkları.
  List<Override> demoOverrides() {
    final now = DateTime.now();
    final demo = DemoData.seed(now);
    return [
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      settingsRepositoryProvider.overrideWithValue(demo.settings),
      routinesRepositoryProvider.overrideWithValue(demo.routines),
      tasksRepositoryProvider.overrideWithValue(demo.tasks),
      notesRepositoryProvider.overrideWithValue(demo.notes),
      healthRepositoryProvider.overrideWithValue(demo.health),
      kokpitRepositoryProvider.overrideWithValue(demo.kokpit),
      reportsRepositoryProvider.overrideWithValue(demo.reports),
      authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
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
    ];
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required Widget home,
    AppThemeMode initial = AppThemeMode.dark,
    List<Override> overrides = const [],
  }) async {
    usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeModeProvider.overrideWithValue(initial),
          ...overrides,
        ],
        child: _ThemedApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(_ThemedApp)));

  Future<void> select(WidgetTester tester, AppThemeMode mode) async {
    await containerOf(tester).read(themeModeProvider.notifier).select(mode);
    await tester.pump();
  }

  Color scaffoldColor(WidgetTester tester, Finder scaffold) => tester
      .widget<Material>(
        find
            .descendant(of: scaffold, matching: find.byType(Material))
            .first,
      )
      .color!;

  SystemUiOverlayStyle rootOverlayStyle(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .descendant(
              of: find.byType(AppThemeScope),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      )
      .value;

  group('yeniden boyama garantisi', () {
    testWidgets('const bileşen tek karede yeni paletle kurulur ve boyanır',
        (tester) async {
      await pumpApp(tester, home: const _ConstProbe());

      ColoredBox box() =>
          tester.widget<ColoredBox>(find.byKey(const Key('probe-box')));
      expect(box().color, AppPalette.dark.background);
      expect(_PalettePainter.lastPainted, AppPalette.dark.accent);
      final buildsBefore = _ConstProbe.builds;

      await select(tester, AppThemeMode.light);

      expect(AppColors.palette, same(AppPalette.light));
      expect(_ConstProbe.builds, buildsBefore + 1,
          reason: 'const bileşen de yeniden kurulmalı');
      expect(box().color, AppPalette.light.background);
      expect(
        tester.renderObject(find.byKey(const Key('probe-box'))),
        paints..rect(color: AppPalette.light.background),
      );
      expect(_PalettePainter.lastPainted, AppPalette.light.accent,
          reason: 'shouldRepaint false dese de yeniden boyanmalı');
      expect(
        Theme.of(tester.element(find.byType(_ConstProbe))).brightness,
        Brightness.light,
      );

      await select(tester, AppThemeMode.dark);
      expect(box().color, AppPalette.dark.background);
      expect(_PalettePainter.lastPainted, AppPalette.dark.accent);
    });

    testWidgets('durum çubuğu ikonları temaya göre değişir', (tester) async {
      await pumpApp(tester, home: const _ConstProbe());
      expect(rootOverlayStyle(tester).statusBarIconBrightness, Brightness.light);

      await select(tester, AppThemeMode.light);
      expect(rootOverlayStyle(tester).statusBarIconBrightness, Brightness.dark);
      expect(rootOverlayStyle(tester).statusBarBrightness, Brightness.light);
    });

    testWidgets(
        'Ayarlar açıkken tema değişince gezinme, kaydırma ve form korunur',
        (tester) async {
      await pumpApp(tester, home: const HomeShell(), overrides: demoOverrides());

      // Kokpit listesi biraz kaydırılır, ardından Ayarlar üstüne açılır.
      final kokpitList = find.descendant(
        of: find.byType(KokpitScreen),
        matching: find.byType(Scrollable),
      );
      await tester.drag(kokpitList.first, const Offset(0, -260));
      await tester.pumpAndSettle();
      final kokpitOffset =
          tester.state<ScrollableState>(kokpitList.first).position.pixels;
      expect(kokpitOffset, greaterThan(100));

      // Ayarlar düğmesi kaydırınca ekran dışında kaldı; aynı rota açılır.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Kaydedilmemiş bir düzenleme ve kaydırılmış bir liste.
      await tester.enterText(find.byKey(const Key('settings-calories')), '2345');
      await tester.pump();
      final settingsList = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await tester.drag(settingsList.first, const Offset(0, -180));
      await tester.pumpAndSettle();
      final settingsOffset =
          tester.state<ScrollableState>(settingsList.first).position.pixels;
      expect(settingsOffset, greaterThan(100));
      final settingsElement = tester.element(find.byType(SettingsScreen));
      final shellElement =
          tester.element(find.byType(HomeShell, skipOffstage: false));

      await select(tester, AppThemeMode.light);

      // Gezinme yığını yerinde: Ayarlar hâlâ üstte, kabuk altında.
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        tester.element(find.byType(SettingsScreen)),
        same(settingsElement),
      );
      expect(
        tester.element(find.byType(HomeShell, skipOffstage: false)),
        same(shellElement),
      );
      expect(navigator.canPop(), isTrue);
      expect(find.byType(AppBottomBar), findsNothing);

      // Kaydırma ve form durumu yerinde.
      expect(
        tester.state<ScrollableState>(settingsList.first).position.pixels,
        settingsOffset,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('settings-calories')))
            .controller!
            .text,
        '2345',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNotNull,
        reason: 'kaydedilmemiş değişiklik kaybolmadı',
      );

      // Görünen ekran açık paletle boyandı.
      expect(
        scaffoldColor(tester, find.byType(Scaffold).last),
        AppPalette.light.background,
      );
      final settingsCard = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BentoCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(settingsCard.color, AppPalette.light.surface);

      // Alttaki (sahne dışı) kabuk da yeni paletle kuruldu.
      final hiddenCard = tester.widget<Material>(
        find
            .descendant(
              of: find.descendant(
                of: find.byType(KokpitScreen, skipOffstage: false),
                matching: find.byType(BentoCard, skipOffstage: false),
                skipOffstage: false,
              ),
              matching: find.byType(Material, skipOffstage: false),
              skipOffstage: false,
            )
            .first,
      );
      expect(hiddenCard.color, AppPalette.light.surface);

      // Geri dönülünce Kokpit kaldığı yerde ve açık temada. Form hâlâ
      // "değişti" durumunda olduğu için önce çıkış onayı sorulur.
      await navigator.maybePop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç ve çık'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        tester.state<ScrollableState>(kokpitList.first).position.pixels,
        kokpitOffset,
      );
      expect(
        scaffoldColor(tester, find.byType(Scaffold).first),
        AppPalette.light.background,
      );
      expect(find.byType(AppBottomBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('sistem modu', () {
    testWidgets('cihazın açık/koyu ayarını izler', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await pumpApp(
        tester,
        home: const _ConstProbe(),
        initial: AppThemeMode.system,
      );

      ColoredBox box() =>
          tester.widget<ColoredBox>(find.byKey(const Key('probe-box')));
      expect(box().color, AppPalette.dark.background);
      expect(AppColors.palette, same(AppPalette.dark));

      // Uygulama açıkken sistem ayarı değişir.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(box().color, AppPalette.light.background);
      expect(AppColors.palette, same(AppPalette.light));
      expect(
        Theme.of(tester.element(find.byType(_ConstProbe))).brightness,
        Brightness.light,
      );
      expect(rootOverlayStyle(tester).statusBarIconBrightness, Brightness.dark);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(box().color, AppPalette.dark.background);
      expect(AppColors.palette, same(AppPalette.dark));
    });

    testWidgets('Açık ve Koyu seçiliyken cihaz ayarı yok sayılır',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await pumpApp(tester, home: const _ConstProbe());

      ColoredBox box() =>
          tester.widget<ColoredBox>(find.byKey(const Key('probe-box')));
      expect(box().color, AppPalette.dark.background, reason: 'varsayılan koyu');

      await select(tester, AppThemeMode.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(box().color, AppPalette.light.background);
    });
  });

  group('gerçek uygulama kökü', () {
    testWidgets('KisiselAsistanApp saklanan açık tercihle açılır',
        (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialThemeModeProvider.overrideWithValue(AppThemeMode.light),
            authSessionProvider
                .overrideWith((ref) => Stream<Session?>.value(null)),
          ],
          child: const KisiselAsistanApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        scaffoldColor(tester, find.byType(Scaffold)),
        AppPalette.light.background,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.dashboard_rounded)).color,
        AppPalette.light.accent,
      );
    });

    testWidgets('ConfigErrorApp verilen tercihi uygular', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        const ConfigErrorApp(
          missingKeys: ['SUPABASE_URL'],
          themeMode: AppThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        scaffoldColor(tester, find.byType(Scaffold)),
        AppPalette.light.background,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.settings_suggest_rounded)).color,
        AppPalette.light.warning,
      );
    });
  });

  group('Ayarlar > Görünüm', () {
    testWidgets('Açık seçilince hemen uygulanır ve cihaza yazılır',
        (tester) async {
      await pumpApp(
        tester,
        home: const SettingsScreen(),
        overrides: demoOverrides(),
      );

      expect(find.text('Görünüm'), findsOneWidget);
      expect(find.text('Sistem'), findsOneWidget);
      expect(find.text('Koyu'), findsOneWidget);
      expect(
        scaffoldColor(tester, find.byType(Scaffold)),
        AppPalette.dark.background,
      );
      SegmentedButton<AppThemeMode> picker() => tester.widget(
            find.byKey(const Key('settings-theme-mode')),
          );
      expect(picker().selected, {AppThemeMode.dark});

      await tester.tap(find.text('Açık'));
      await tester.pumpAndSettle();

      expect(
        scaffoldColor(tester, find.byType(Scaffold)),
        AppPalette.light.background,
      );
      expect(picker().selected, {AppThemeMode.light});
      expect(containerOf(tester).read(themeModeProvider), AppThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeModeStore.key), 'light');

      // Cihaz tercihidir: kaydedilmemiş form değişikliği sayılmaz.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Sistem'));
      await tester.pumpAndSettle();
      expect(prefs.getString(ThemeModeStore.key), 'system');
      expect(picker().selected, {AppThemeMode.system});
      expect(tester.takeException(), isNull);
    });
  });
}
