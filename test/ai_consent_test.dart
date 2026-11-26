// AI hızlı eklemeden önce bir kez açık onay istenir.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_consent_sheet.dart';
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

Future<bool?> _run(WidgetTester tester, FakeSettingsRepository repo,
    {String? tap}) async {
  bool? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  result = await ensureAiConsent(context, ref),
              child: const Text('ekle'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ekle'));
  await tester.pumpAndSettle();
  if (tap != null) {
    await tester.tap(find.byKey(Key(tap)));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  testWidgets('onay varsa sayfa açılmaz', (tester) async {
    final repo = FakeSettingsRepository();
    expect(await _run(tester, repo), isTrue);
    expect(find.byType(AiConsentSheet), findsNothing);
  });

  testWidgets('Kabul onayı kaydeder', (tester) async {
    final repo = FakeSettingsRepository(aiConsent: false);
    expect(await _run(tester, repo, tap: 'ai-consent-accept'), isTrue);
    expect(repo.aiConsent, isTrue);
  });

  testWidgets('Vazgeç onay vermez', (tester) async {
    final repo = FakeSettingsRepository(aiConsent: false);
    expect(await _run(tester, repo, tap: 'ai-consent-decline'), isFalse);
    expect(repo.aiConsent, isFalse);
  });
}
