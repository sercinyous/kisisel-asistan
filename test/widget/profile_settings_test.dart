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
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:kisisel_asistan/features/settings/presentation/profile_goals_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeSettingsRepository settings;
  late FakeNotificationService notifications;

  const heightKey = Key('settings-height');
  const birthYearKey = Key('settings-birth-year');
  const femaleKey = Key('settings-sex-female');
  const maleKey = Key('settings-sex-male');
  const unspecifiedKey = Key('settings-sex-unspecified');

  /// Doğum yılı üst sınırı: bu yıl − 10.
  final maxBirthYear = DateTime.now().year - 10;

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
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileGoalsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tembel liste: profil alanları ekrana gelene kadar kaydırılır.
  Future<void> showProfile(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(birthYearKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Key key, String text) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(key), text);
    await tester.pump();
  }

  Future<void> tapChip(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    // Önceki denemenin uyarı çubuğu Kaydet'in üstünü kapatmasın.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, Key key) =>
      tester.widget<ChoiceChip>(find.byKey(key)).selected;

  testWidgets('boy 180, doğum yılı 1990, Erkek girilip kaydedilince depoya gider',
      (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    expect(find.text('Profil'), findsOneWidget);

    await enter(tester, heightKey, '180');
    await enter(tester, birthYearKey, '1990');
    await tapChip(tester, maleKey);
    await save(tester);

    expect(settings.saved, hasLength(1));
    final map = settings.saved.single.toMap();
    expect(map['height_cm'], 180);
    expect(map['birth_year'], 1990);
    expect(map['sex'], 'male');
    expect(settings.saved.single.profileComplete, isTrue);
    expect(find.text('Ayarlar kaydedildi.'), findsOneWidget);
  });

  testWidgets('üç cinsiyet seçeneği doğru değerle yazılır', (tester) async {
    for (final (key, value) in [
      (femaleKey, 'female'),
      (maleKey, 'male'),
      (unspecifiedKey, 'unspecified'),
    ]) {
      settings = FakeSettingsRepository();
      await pumpSettings(tester);
      await showProfile(tester);
      await tapChip(tester, key);
      expect(selected(tester, key), isTrue, reason: value);
      await save(tester);
      expect(settings.saved.single.sex, value);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('cinsiyet seçenekleri Türkçe etiketlidir', (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    expect(find.text('Kadın'), findsOneWidget);
    expect(find.text('Erkek'), findsOneWidget);
    expect(find.text('Belirtmek istemiyorum'), findsOneWidget);
  });

  testWidgets('boy 99 hata verir ve kaydedilmez', (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    await enter(tester, heightKey, '99');
    await save(tester);

    expect(find.text('100–250 arası olmalı'), findsOneWidget);
    expect(settings.saved, isEmpty);
  });

  testWidgets('boy 251 hata verir, 100 ve 250 kabul edilir', (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    await enter(tester, heightKey, '251');
    await save(tester);
    expect(find.text('100–250 arası olmalı'), findsOneWidget);
    expect(settings.saved, isEmpty);

    await enter(tester, heightKey, '100');
    await save(tester);
    expect(settings.saved.single.heightCm, 100);

    await enter(tester, heightKey, '250');
    await save(tester);
    expect(settings.saved.last.heightCm, 250);
  });

  testWidgets('doğum yılı bu yıl−10’dan büyükse hata verir ve kaydedilmez',
      (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    await enter(tester, birthYearKey, '${maxBirthYear + 1}');
    await save(tester);

    expect(find.text('1900–$maxBirthYear arası olmalı'), findsOneWidget);
    expect(settings.saved, isEmpty);
  });

  testWidgets('doğum yılı bu yıl−10 kabul edilir; 1899 reddedilir',
      (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    await enter(tester, birthYearKey, '1899');
    await save(tester);
    expect(find.text('1900–$maxBirthYear arası olmalı'), findsOneWidget);
    expect(settings.saved, isEmpty);

    await enter(tester, birthYearKey, '$maxBirthYear');
    await save(tester);
    expect(settings.saved.single.birthYear, maxBirthYear);
  });

  testWidgets('geçersiz boy ekranda görünmüyorken de kayıt engellenir',
      (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    await enter(tester, heightKey, '99');

    // Kısa ekranda tembel liste alanı bellekten atana kadar yukarı kaydırılır
    // (profil, hedeflerin altındadır).
    tester.view.physicalSize = const Size(750, 500);
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(heightKey), findsNothing);

    await save(tester);
    expect(settings.saved, isEmpty);
    expect(
      find.text('Profil kaydedilemedi. Boy 100–250 arası olmalı.'),
      findsOneWidget,
    );
  });

  testWidgets('boş bırakmak profili null bırakır', (tester) async {
    await pumpSettings(tester);
    // Yalnızca kalori değişir; profil alanlarına dokunulmaz.
    await tester.enterText(find.byKey(const Key('settings-calories')), '2300');
    await tester.pump();
    await save(tester);

    final s = settings.saved.single;
    expect(s.dailyCalories, 2300);
    expect(s.heightCm, isNull);
    expect(s.birthYear, isNull);
    expect(s.sex, isNull);
    expect(s.toMap()['height_cm'], isNull);
    expect(s.toMap()['birth_year'], isNull);
    expect(s.toMap()['sex'], isNull);
  });

  testWidgets('dolu profil temizlenebilir: alanlar boşaltılır, seçim kaldırılır',
      (tester) async {
    settings = FakeSettingsRepository(
      settings: const UserSettings.defaults()
          .copyWith(heightCm: 180, birthYear: 1990, sex: 'male'),
    );
    await pumpSettings(tester);
    await showProfile(tester);

    expect(
      tester.widget<TextFormField>(find.byKey(heightKey)).controller!.text,
      '180',
    );
    expect(
      tester.widget<TextFormField>(find.byKey(birthYearKey)).controller!.text,
      '1990',
    );
    expect(selected(tester, maleKey), isTrue);

    await enter(tester, heightKey, '');
    await enter(tester, birthYearKey, '');
    await tapChip(tester, maleKey);
    expect(selected(tester, maleKey), isFalse);
    await save(tester);

    final s = settings.saved.single;
    expect(s.heightCm, isNull);
    expect(s.birthYear, isNull);
    expect(s.sex, isNull);
    expect(s.profileComplete, isFalse);
  });

  testWidgets('Kaydet profil değişmedikçe kapalı, cinsiyet seçilince açılır',
      (tester) async {
    await pumpSettings(tester);
    FilledButton button() => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kaydet'));
    expect(button().onPressed, isNull);

    await showProfile(tester);
    await tapChip(tester, femaleKey);
    expect(button().onPressed, isNotNull);

    await tapChip(tester, femaleKey);
    expect(button().onPressed, isNull, reason: 'seçim geri alındı');
  });

  testWidgets('profil eksikken ipucu görünür, doluyken görünmez',
      (tester) async {
    await pumpSettings(tester);
    await showProfile(tester);
    expect(
      find.text('Enerji dengesi için boy, doğum yılı ve cinsiyet gerekli.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    settings = FakeSettingsRepository(
      settings: const UserSettings.defaults()
          .copyWith(heightCm: 170, birthYear: 1985, sex: 'female'),
    );
    await pumpSettings(tester);
    await showProfile(tester);
    expect(
      find.text('Enerji dengesi için boy, doğum yılı ve cinsiyet gerekli.'),
      findsNothing,
    );
  });

  testWidgets('Profil bölümü 375x667 ve 1.3 metin ölçeğinde taşmaz',
      (tester) async {
    await pumpSettings(tester, textScale: 1.3);
    await showProfile(tester);
    await enter(tester, heightKey, '99');
    await tester.pumpAndSettle();
    expect(find.text('100–250 arası olmalı'), findsOneWidget);
    await tapChip(tester, unspecifiedKey);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Belirtmek istemiyorum'), findsOneWidget);
  });
}
