import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/health_source.dart'
    show MemoryAppleHealthConsentStore, appleHealthConsentStoreProvider;
import 'package:kisisel_asistan/core/services/health_service.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/routines/data/routines_repository.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/presentation/hesap_screen.dart';
import 'package:kisisel_asistan/features/settings/presentation/notifications_page.dart';
import 'package:kisisel_asistan/features/settings/presentation/profile_goals_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeSettingsRepository settings;
  late FakeNotificationService notifications;

  setUp(() {
    settings = FakeSettingsRepository();
    notifications = FakeNotificationService();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    double textScale = 1.0,
    Widget home = const ProfileGoalsPage(),
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(750, 1334);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          routinesRepositoryProvider.overrideWithValue(FakeRoutinesRepository()),
          tasksRepositoryProvider.overrideWithValue(FakeTasksRepository()),
          healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
          appleHealthConsentStoreProvider.overrideWithValue(
            MemoryAppleHealthConsentStore(grantAll: true),
          ),
          healthServiceProvider.overrideWithValue(
            FakeHealthService(const HealthSnapshot(status: HealthStatus.denied)),
          ),
          notificationServiceProvider.overrideWithValue(notifications),
          authSessionProvider.overrideWith((ref) => Stream<Session?>.value(null)),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ayarlar Hesap menüsünü açar; altı satır ve küçük grup taşmaz',
      (tester) async {
    await pumpSettings(tester, textScale: 1.3, home: const HesapScreen());
    expect(tester.takeException(), isNull);
    expect(find.byType(HesapScreen), findsOneWidget);
    for (final title in [
      'Profil ve hedefler',
      'Arkadaşlar',
      'Bildirimler',
      'Görünüm',
      'Kategoriler ve ekip',
      'Bağlantılar',
      'Sorun bildir',
      'Çıkış yap',
    ]) {
      // Başlıktaki avatar listeyi uzatır: alt grup kaydırılarak görünür.
      await tester.scrollUntilVisible(find.text(title), 80);
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('hesap-avatar')), findsOneWidget);
    expect(find.text('Hatırlatıcılar'), findsNothing);
    expect(find.text('Kaydet'), findsNothing);
    expect(find.text('Koyu'), findsOneWidget);
  });

  testWidgets('Profil ve hedefler satırı alt sayfayı açar', (tester) async {
    await pumpSettings(tester, home: const HesapScreen());
    await tester.tap(find.text('Profil ve hedefler'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileGoalsPage), findsOneWidget);
    expect(find.text('Hedefler'), findsOneWidget);
  });

  testWidgets('Profil ve hedefler 375x667 ve 1.3 ölçekte taşmaz; Hesabımı sil en altta',
      (tester) async {
    await pumpSettings(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('settings-calories'))).controller!.text,
      '2000',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-delete-account')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hesabımı sil'), findsOneWidget);
  });

  testWidgets('Kaydet düzenlenen kalori değerini depoya yazar', (tester) async {
    await pumpSettings(tester);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet')).onPressed,
      isNull,
      reason: 'değişiklik yokken kapalı',
    );

    await tester.enterText(find.byKey(const Key('settings-calories')), '2300');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(settings.saved.single.dailyCalories, 2300);
    expect(settings.saved.single.dailyProteinG, 120);
    expect(find.text('Kaydedildi.'), findsOneWidget);
  });

  testWidgets('sınır dışı değer kaydedilmez', (tester) async {
    await pumpSettings(tester);
    await tester.enterText(find.byKey(const Key('settings-calories')), '100');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();

    expect(settings.saved, isEmpty);
    expect(find.text('800–6000 arası olmalı'), findsOneWidget);
  });

  Future<void> scrollToPermission(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Bildirim izni'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ekranı açmak bildirim izni istemez, yalnızca durumu gösterir',
      (tester) async {
    notifications.permissionGranted = false;
    await pumpSettings(tester, home: const NotificationsPage());
    await scrollToPermission(tester);

    expect(find.textContaining('Kapalı ·'), findsOneWidget);
    expect(notifications.permissionRequests, 0);
  });

  testWidgets('"İzin iste" butonu izni ister ve durumu yeniler', (tester) async {
    notifications.permissionGranted = false;
    await pumpSettings(tester, home: const NotificationsPage());
    await scrollToPermission(tester);

    // Kullanıcı sistem penceresinde izin verir.
    notifications.permissionGranted = true;
    await tester.ensureVisible(find.text('İzin iste'));
    await tester.tap(find.text('İzin iste'));
    await tester.pumpAndSettle();

    expect(notifications.permissionRequests, greaterThanOrEqualTo(1));
    expect(find.text('Açık'), findsOneWidget);
  });
}
