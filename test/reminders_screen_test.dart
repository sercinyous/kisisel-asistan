import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';
import 'package:kisisel_asistan/core/services/supabase_providers.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/demo/demo_reminders.dart';
import 'package:kisisel_asistan/features/reminders/data/reminders_repository.dart';
import 'package:kisisel_asistan/features/reminders/domain/reminder.dart';
import 'package:kisisel_asistan/features/reminders/presentation/reminders_screen.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/fakes.dart';

void main() {
  late MemoryRemindersRepository repo;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(repo),
          notificationServiceProvider
              .overrideWithValue(FakeNotificationService()),
          authSessionProvider
              .overrideWith((ref) => Stream<Session?>.value(null)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RemindersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => repo = MemoryRemindersRepository(userId: 'u1'));

  testWidgets('şablonla ekle, düzenle, Yaptım, sil', (tester) async {
    await pump(tester);
    expect(find.text('Henüz hatırlatıcı yok'), findsOneWidget);

    // Ekle: "Su iç" şablonu tek dokunuşla doldurur.
    await tester.tap(find.byKey(const Key('reminders-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Su iç'));
    await tester.pumpAndSettle();
    expect(find.text('11:00'), findsOneWidget);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(repo.reminders, hasLength(1));
    final created = repo.reminders.single;
    expect(created.title, 'Su iç');
    expect(created.repeat, ReminderRepeat.daily);
    expect(created.time, const TimeOfDayValue(11, 0));
    expect(find.text('Her gün · 11:00'), findsOneWidget);

    // Düzenle: başlık ve tekrar değişir.
    await tester.tap(find.text('Su iç'));
    await tester.pumpAndSettle();
    expect(find.text('Hatırlatıcıyı düzenle'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reminder-title')), 'Bol su iç');
    await tester.tap(find.text('Hafta içi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.reminders.single.title, 'Bol su iç');
    expect(repo.reminders.single.repeat, ReminderRepeat.weekdays);
    expect(find.text('Bol su iç'), findsOneWidget);

    // Kapat.
    await tester.tap(find.byKey(ValueKey('reminder-switch-${created.id}')));
    await tester.pumpAndSettle();
    expect(repo.reminders.single.enabled, isFalse);

    // Sil (onaylı).
    await tester.tap(find.byKey(ValueKey('reminder-delete-${created.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sil').last);
    await tester.pumpAndSettle();
    expect(repo.reminders, isEmpty);
    expect(find.text('Henüz hatırlatıcı yok'), findsOneWidget);
  });

  testWidgets('Yaptım bugünü işaretler ve seri görünür', (tester) async {
    final today = reminderDay(DateTime.now());
    repo.reminders.add(
      const Reminder(
        id: 'r1',
        userId: 'u1',
        title: 'İlacını al',
        time: TimeOfDayValue(9, 0),
        repeat: ReminderRepeat.daily,
      ),
    );
    repo.done['r1'] = {
      today.subtract(const Duration(days: 1)),
      DateTime(today.year, today.month, today.day - 2),
    };
    await pump(tester);
    expect(find.text('2 gün seri'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reminder-done-r1')));
    await tester.pumpAndSettle();
    expect(repo.done['r1'], contains(today));
    expect(find.text('3 gün seri'), findsOneWidget);
    expect(find.text('Yapıldı'), findsOneWidget);
  });
}
