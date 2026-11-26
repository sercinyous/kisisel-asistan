import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/friends/data/friends_repository.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_screen.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fakes.dart';

/// Bildirim ve engellemeleri kaydeden demo depo; [failReport] ile hata verir.
class _RecordingFriends extends DemoFriendsRepository {
  final reports = <String>[];
  final blocked = <String>[];
  bool failReport = false;

  @override
  Future<void> report({required String subject, required String reason}) async {
    if (failReport) throw StateError('ağ yok');
    reports.add('$subject|$reason');
  }

  @override
  Future<void> block(String userId) async {
    blocked.add(userId);
    await super.block(userId);
  }
}

void main() {
  late _RecordingFriends friends;

  setUp(() => friends = _RecordingFriends());

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(800, 1700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(settings: const UserSettings.defaults()),
          ),
          authSessionProvider
              .overrideWith((ref) => Stream<Session?>.value(null)),
          friendsRepositoryProvider.overrideWithValue(friends),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const FriendsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openReportFor(WidgetTester tester, String name) async {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(
      of: row.first,
      matching: find.byTooltip('Seçenekler'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bildir').last);
    await tester.pumpAndSettle();
  }

  testWidgets('arkadaşı bildir: onay sonrası kimlik ve gerekçeyle gönderilir',
      (tester) async {
    await pump(tester);
    await openReportFor(tester, 'Elif');
    await tester.enterText(
        find.byKey(const ValueKey('report-reason')), 'rahatsız edici');
    await tester.tap(find.widgetWithText(TextButton, 'Bildir'));
    await tester.pumpAndSettle();

    expect(friends.reports, hasLength(1));
    expect(friends.reports.single, contains('kullanıcı f-1'));
    expect(friends.reports.single, contains('gerekçe: rahatsız edici'));
    expect(friends.blocked, isEmpty);
    expect(find.text('Bildirimin alındı. Teşekkürler.'), findsOneWidget);
  });

  testWidgets('bildirim başarısızsa teşekkür değil hata gösterilir',
      (tester) async {
    friends.failReport = true;
    await pump(tester);
    await openReportFor(tester, 'Elif');
    await tester.tap(find.widgetWithText(TextButton, 'Bildir'));
    await tester.pumpAndSettle();

    expect(find.text('Bildirimin alındı. Teşekkürler.'), findsNothing);
    expect(find.textContaining('İşlem yapılamadı'), findsOneWidget);
  });

  testWidgets('"Ayrıca engelle" ile bildirilen arkadaş engellenir',
      (tester) async {
    await pump(tester);
    await openReportFor(tester, 'Elif');
    await tester.tap(find.byKey(const ValueKey('report-block')));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Bildir'));
    await tester.pumpAndSettle();

    expect(friends.blocked, ['f-1']);
    expect(find.text('Bildirimin alındı ve kullanıcı engellendi.'),
        findsOneWidget);
  });

  testWidgets('gelen isteği bildirmek onay ister; vazgeçince hiçbir şey olmaz',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Bildir'));
    await tester.pumpAndSettle();
    expect(find.text('Deniz bildirilsin mi?'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-block')), findsNothing);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(friends.reports, isEmpty);
    expect(find.text('Deniz'), findsOneWidget);
  });
}
