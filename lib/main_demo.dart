// Tarayıcı demosu: gerçek arayüz, bellekte duran örnek veri.
// Supabase, Gemini, HealthKit, Google Health ve bildirimler bağlı değildir.
// Derleme: flutter build web -t lib/main_demo.dart --no-web-resources-cdn
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/google_auth.dart';
import 'core/services/health_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/supabase_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_scope.dart';
import 'core/theme/theme_mode.dart';
import 'core/utils/date_utils.dart';
import 'features/friends/data/friends_repository.dart';
import 'features/onboarding/data/onboarding_repository.dart';
import 'demo/demo_backend.dart';
import 'demo/demo_data.dart';
import 'demo/demo_foods.dart';
import 'features/ai_quick_add/data/gemini_parser_service.dart';
import 'features/ai_quick_add/data/quick_add_repository.dart';
import 'features/health/data/food_catalog.dart';
import 'features/health/data/health_repository.dart';
import 'features/health/presentation/health_source_providers.dart';
import 'features/kokpit/data/kokpit_repository.dart';
import 'features/operations/data/notes_repository.dart';
import 'features/operations/data/tasks_repository.dart';
import 'features/reports/data/reports_repository.dart';
import 'features/routines/data/routines_repository.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/shell/presentation/home_shell.dart';

/// Yazı tipleri sayfanın yanındaki dosyalardan yüklenir; CanvasKit'in
/// varsayılan olarak başvurduğu dış font sunucusuna ihtiyaç kalmaz.
Future<void> _loadFonts() async {
  final loader = FontLoader('Roboto');
  for (final file in const ['Regular', 'Medium', 'Bold']) {
    loader.addFont(
      http
          .get(Uri.base.resolve('fonts/Roboto-$file.ttf'))
          .then((r) => ByteData.sublistView(r.bodyBytes)),
    );
  }
  try {
    await loader.load();
  } catch (_) {
    // Yazı tipi yüklenemezse uygulama yine açılır (varsayılan yazı tipiyle).
  }
}

/// Demoda Google seçeneği açık görünsün diye biçimce geçerli, gerçekte
/// hiçbir projeye ait olmayan istemci kimliği (giriş sahtedir).
const String _demoGoogleClientId = '1-demo.apps.googleusercontent.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(AppDates.locale);
  await _loadFonts();

  final data = DemoData.seed(
    DateTime.now(),
    regenerateDelay: const Duration(milliseconds: 900),
  );
  // Depo (localStorage) korumalı alanda hata verirse koyu temayla açılır.
  final themeMode = await loadInitialThemeMode();
  // Kaynak tercihi ve Google bağlantı izi de tarayıcıda saklanır; Google
  // girişi sahtedir (pencere açılmaz, Google'a veri isteği gitmez).
  final healthSource = await loadInitialHealthSource();
  final googleLink = await const GoogleLinkStore().load();
  final googleAuth = FakeGoogleAuthClient(
    email: googleLink.email ?? 'demo@gmail.com',
    signedIn: googleLink.email != null,
    connectDelay: const Duration(milliseconds: 700),
  );

  runApp(
    ProviderScope(
      overrides: [
        initialThemeModeProvider.overrideWithValue(themeMode),
        supabaseClientProvider.overrideWithValue(
          SupabaseClient('https://demo.invalid', 'demo'),
        ),
        authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        geminiParserServiceProvider.overrideWith(
          (ref, mode) => FakeGeminiParserService(
            (input) async {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              return demoParse(input, mode);
            },
          ),
        ),
        quickAddRepositoryProvider
            .overrideWithValue(DemoQuickAddRepository(data)),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        friendsRepositoryProvider.overrideWithValue(DemoFriendsRepository()),
        settingsRepositoryProvider.overrideWithValue(data.settings),
        onboardingRepositoryProvider.overrideWithValue(
          FakeOnboardingRepository(
            settings: data.settings,
            routines: data.routines,
            health: data.health,
          ),
        ),
        routinesRepositoryProvider.overrideWithValue(data.routines),
        tasksRepositoryProvider.overrideWithValue(data.tasks),
        notesRepositoryProvider.overrideWithValue(data.notes),
        healthRepositoryProvider.overrideWithValue(data.health),
        // Paketli liste boşsa demo örnek besinleriyle çalışır.
        foodCatalogProvider
            .overrideWith((ref) => loadDemoFoodCatalog(rootBundle)),
        kokpitRepositoryProvider.overrideWithValue(data.kokpit),
        reportsRepositoryProvider.overrideWithValue(data.reports),
        initialHealthSourceProvider.overrideWithValue(healthSource),
        initialGoogleLinkProvider.overrideWithValue(googleLink),
        googleClientIdProvider.overrideWithValue(_demoGoogleClientId),
        googleAuthClientProvider.overrideWithValue(googleAuth),
        googleHealthSourceProvider.overrideWith(
          (ref) => demoGoogleHealthSource(
            ref.watch(googleConnectionProvider.notifier),
            DateTime.now(),
          ),
        ),
        healthServiceProvider.overrideWithValue(
          FakeHealthService(
            HealthSnapshot(
              status: HealthStatus.ok,
              steps: 6480,
              activeKcal: 412,
              sleepMinutes: 432,
              readAt: DateTime.now(),
            ),
          ),
        ),
      ],
      child: const _DemoApp(),
    ),
  );
}

class _DemoApp extends ConsumerWidget {
  const _DemoApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppThemeScope(
      mode: ref.watch(themeModeProvider),
      builder: _app,
    );
  }

  Widget _app(BuildContext context, ThemeData base) {
    return MaterialApp(
      title: 'Ritim Demo',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      ),
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('tr', 'TR')],
      locale: const Locale('tr', 'TR'),
      // Geniş ekranda uygulama telefon genişliğinde ortalanır.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final width = math.min(media.size.width, 430.0);
        return ColoredBox(
          color: AppColors.background,
          child: Center(
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  const _DemoBanner(),
                  Expanded(
                    child: MediaQuery(
                      data: media.copyWith(
                        size: Size(
                          width,
                          media.size.height - _DemoBanner.height,
                        ),
                      ),
                      child: child!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      home: const HomeShell(),
    );
  }
}

/// Sayfanın örnek veriyle çalışan bir demo olduğunu her ekranda belirtir.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Demo',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(text: ' · örnek veri, sayfa yenilenince sıfırlanır'),
          ],
        ),
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11,
          color: AppColors.textSecondary,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
