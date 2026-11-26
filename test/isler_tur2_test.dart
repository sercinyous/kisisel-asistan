import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/features/operations/data/tasks_repository.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';
import 'package:kisisel_asistan/features/operations/presentation/operations_providers.dart';
import 'package:kisisel_asistan/features/operations/presentation/tasks_view.dart';
import 'package:kisisel_asistan/features/reminders/domain/reminder.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart'
    show TimeOfDayValue;

TaskItem _task(String id, String title, {DateTime? due}) => TaskItem(
      id: id,
      title: title,
      category: 'Kişisel',
      priority: 'medium',
      status: 'todo',
      dueAt: due,
    );

void main() {
  setUpAll(() => initializeDateFormatting(AppDates.locale));

  test('hesap değişince önceki hesabın tamamlananları listede kalmaz', () async {
    final a = FakeTasksRepository(tasks: [_task('a1', 'A gizli')]);
    final b = FakeTasksRepository(tasks: [_task('b1', 'B isi')]);
    final current = StateProvider<TasksRepository>((ref) => a);
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWith((ref) => ref.watch(current)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(opsTasksProvider, (_, __) {});
    addTearDown(sub.close);

    final first = await container.read(opsTasksProvider.future);
    await container.read(opsTasksProvider.notifier).complete(first.single);
    expect(
      container.read(opsTasksProvider).value!.map((t) => t.id),
      ['a1'],
    );

    container.read(current.notifier).state = b;
    final after = await container.read(opsTasksProvider.future);
    expect(after.map((t) => t.id), ['b1']);
  });

  test('tarihsiz görev kendi grubunda, Sonra ileri tarihliler', () {
    final now = DateTime(2026, 11, 26, 10);
    final groups = groupTasks([
      _task('u', 'Süt al'),
      _task('t', 'Bugün', due: DateTime(2026, 11, 26, 15)),
      _task('l', 'İleri', due: DateTime(2026, 12, 20, 9)),
    ], now);
    expect(groups.undated.map((t) => t.id), ['u']);
    expect(groups.today.map((t) => t.id), ['t']);
    expect(groups.later.map((t) => t.id), ['l']);
    expect(groups.week, isEmpty);
  });

  test('takvim günü farkı saatten bağımsız', () {
    expect(
      AppDates.calendarDaysBetween(
        DateTime(2026, 3, 28, 23, 30),
        DateTime(2026, 3, 29, 0, 10),
      ),
      1,
    );
    expect(
      AppDates.relativeDayTime(
        DateTime(2026, 3, 30, 9),
        now: DateTime(2026, 3, 29, 23),
      ),
      startsWith('Yarın'),
    );
  });

  group('bir kezlik hatırlatıcı', () {
    final now = DateTime(2026, 11, 26, 14);
    ReminderDraft draft(int hour) => ReminderDraft(
          title: 'İlaç',
          time: TimeOfDayValue(hour, 0),
          repeat: ReminderRepeat.once,
          onDate: DateTime(2026, 11, 26),
        );

    test('geçmiş saat reddedilir, gelecek saat geçer', () {
      expect(draft(9).validationErrorAt(now), 'Geçmiş bir saat seçtin.');
      expect(draft(18).validationErrorAt(now), isNull);
    });
  });
}
