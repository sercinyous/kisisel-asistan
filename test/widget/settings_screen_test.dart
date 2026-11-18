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
import 'package:kisisel_asistan/features/settings/presentation/settings_screen.dart';
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
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('varsayılanlar 375x667 ve 1.3 metin ölçeğinde taşmadan çizilir',
      (tester) async {
    await pumpSettings(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Hedefler'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('settings-calories'))).controller!.text,
      '2000',
    );

    // Tembel liste: tüm bölümler ekrana gelsin diye sona kadar kaydırılır.
    final seen = <String>{};
    for (var i = 0; i < 18; i++) {
      for (final title in [
        'Bildirimler',
        'Ekip',
        'Görev kategorileri',
        'Bağlantılar',
        'Hesap',
      ]) {
        if (find.text(title).evaluate().isNotEmpty) seen.add(title);
      }
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(seen, {
      'Bildirimler',
      'Ekip',
      'Görev kategorileri',
      'Bağlantılar',
      'Hesap',
    });
    expect(find.text('Çıkış yap'), findsOneWidget);
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
    expect(find.text('Ayarlar kaydedildi.'), findsOneWidget);
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
    await pumpSettings(tester);
    await scrollToPermission(tester);

    expect(find.textContaining('Kapalı'), findsOneWidget);
    expect(notifications.permissionRequests, 0);
  });

  testWidgets('"İzin iste" butonu izni ister ve durumu yeniler', (tester) async {
    notifications.permissionGranted = false;
    await pumpSettings(tester);
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
