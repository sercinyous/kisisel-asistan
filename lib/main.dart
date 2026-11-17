import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/utils/date_utils.dart';
import 'features/health/presentation/health_source_providers.dart';

Future<void> main() async {
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

  final notifications = NotificationService();
  await notifications.init();

  // Sağlık verisi kaynağı ve Google bağlantı izleri ilk okumadan önce
  // bilinmeli (Google seçiliyken HealthKit izin penceresi açılmasın).
  final healthSource = await loadInitialHealthSource();
  // Google bağlantı izleri oturumdaki kullanıcıya göre saklanır; başka
  // kullanıcının bağlantısı okunmaz.
  final googleLink = await const GoogleLinkStore()
      .load(userId: Supabase.instance.client.auth.currentUser?.id);

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notifications),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialHealthSourceProvider.overrideWithValue(healthSource),
        initialGoogleLinkProvider.overrideWithValue(googleLink),
      ],
      child: const KisiselAsistanApp(),
    ),
  );
}
