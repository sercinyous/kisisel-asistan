// Hesap silme onayı ve oturum bitince açık sayfaların kapanması.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/services/notification_health.dart';
import 'package:kisisel_asistan/features/auth/presentation/auth_gate.dart';
import 'package:kisisel_asistan/features/auth/presentation/sign_in_screen.dart';
import 'package:kisisel_asistan/features/health/presentation/food_picker_sheet.dart';
import 'package:kisisel_asistan/features/health/presentation/providers/body_providers.dart';
import 'package:kisisel_asistan/features/settings/data/account_repository.dart';
import 'package:kisisel_asistan/features/stories/data/story_seen_store.dart';
import 'package:kisisel_asistan/features/settings/presentation/delete_account_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session _session(String id) => Session(
      accessToken: 'token-$id',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      ),
    );

/// AuthGate'in kullandığı dinleyiciyle; alt ağaç sağlayıcılara bağlı olmasın
/// diye kök yerine basit bir sayfa gösterir.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<Session?>>(
      authSessionProvider,
      (previous, next) => popToRootOnSignOut(context, previous, next),
    );
    return Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('ic-sayfa')),
            ),
          ),
          child: const Text('ac'),
        ),
      ),
    );
  }
}

void main() {
  test('paylaşılan kişisel anahtarlar kaynaklarıyla aynı', () {
    expect(AccountRepository.sharedPersonalKeys, [
      RecentFoodsStore.key,
      StorySeenStore.prefsKey,
      CheckinDismissNotifier.prefsKey,
      HealthNudgePrefs.prefsKey,
    ]);
  });

  test('e-posta denetimi', () {
    expect(isValidEmail(' ben@gmail.com '), isTrue);
    expect(isValidEmail('a@b.co'), isTrue);
    for (final bad in [null, '', 'ben', 'ben@', 'ben@gmail', 'b en@x.com']) {
      expect(isValidEmail(bad), isFalse, reason: '$bad');
    }
    expect(minPasswordLength, 8);
  });

  group('isDeleteConfirmWord', () {
    for (final word in ['SİL', 'SIL', 'sil', 'sıl', ' Sil ', 'SiL']) {
      test('"$word" kabul edilir', () {
        expect(isDeleteConfirmWord(word), isTrue);
      });
    }
    for (final word in ['', 'SL', 'SILL', 'delete']) {
      test('"$word" reddedilir', () {
        expect(isDeleteConfirmWord(word), isFalse);
      });
    }
  });

  testWidgets('İngilizce klavyeyle SIL yazınca silme düğmesi açılır',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const DeleteAccountScreen(),
        ),
      ),
    );
    ButtonStyleButton button() => tester.widget<ButtonStyleButton>(
          find.byKey(const Key('delete-account-submit')),
        );
    expect(button().onPressed, isNull);
    for (final word in ['SİL', 'SIL', 'sil', 'sıl']) {
      await tester.enterText(
          find.byKey(const Key('delete-account-confirm')), word);
      await tester.pump();
      expect(button().onPressed, isNotNull, reason: word);
    }
    await tester.enterText(
        find.byKey(const Key('delete-account-confirm')), 'SI');
    await tester.pump();
    expect(button().onPressed, isNull);
  });

  testWidgets('oturum bitince üstte açık sayfa kapanır', (tester) async {
    final auth = StreamController<Session?>.broadcast();
    addTearDown(auth.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith((ref) => auth.stream)],
        child: MaterialApp(theme: AppTheme.dark, home: const _Gate()),
      ),
    );
    auth.add(_session('u1'));
    await tester.pump();
    await tester.tap(find.text('ac'));
    await tester.pumpAndSettle();
    expect(find.text('ic-sayfa'), findsOneWidget);

    auth.add(null);
    await tester.pumpAndSettle();
    expect(find.text('ic-sayfa'), findsNothing);
    expect(find.text('ac'), findsOneWidget);
  });
}
