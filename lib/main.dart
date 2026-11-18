import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/error_reporter.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/utils/date_utils.dart';
import 'features/health/presentation/health_source_providers.dart';

void main() {
  // Yakalanmamış hatalar (Flutter, platform, zone) oturum açıkken
  // public.app_errors'a yazılır; testte ve hata ayıklamada kapalı.
  ErrorReporter? reporter;
  runZonedGuarded(
    () => _run(onReporter: (r) => reporter = r),
    (error, stack) => reporter?.report(error, stack),
  );
}

Future<void> _run({required void Function(ErrorReporter) onReporter}) async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Saklanan görünüm tercihi ilk kareden önce okunur (renk sıçraması olmaz).
  final themeMode = await loadInitialThemeMode();
  SystemChrome.setSystemUIOverlayStyle(AppColors.palette.overlayStyle);

  final missing = Env.missingKeys;
  if (missing.isNotEmpty) {
    runApp(ConfigErrorApp(missingKeys: missing, themeMode: themeMode));
    return;
  }

  await initializeDateFormatting(AppDates.locale);
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
  if (errorReportingEnabled) {
    onReporter(supabaseErrorReporter(Supabase.instance.client)..install());
  }

  final notifications = NotificationService();
  await notifications.init();

  // Sağlık verisi kaynağı ve Google bağlantı izleri ilk okumadan önce
  // bilinmeli (Google seçiliyken HealthKit izin penceresi açılmasın).
  // Kaynak tercihi ve Google bağlantı izleri oturumdaki kullanıcıya göre
  // saklanır; başka kullanıcınınki okunmaz.
  final userId = Supabase.instance.client.auth.currentUser?.id;
  final healthSource = await loadInitialHealthSource(userId: userId);
  final googleLink = await const GoogleLinkStore().load(userId: userId);

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notifications),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialHealthSourceProvider.overrideWithValue(healthSource),
        initialHealthSourceOwnerProvider.overrideWithValue(userId),
        initialGoogleLinkProvider.overrideWithValue(googleLink),
      ],
      child: const KisiselAsistanApp(),
    ),
  );
}
