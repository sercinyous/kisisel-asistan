import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/operations/domain/note_item.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';

void main() {
  group('DailyHealthMetric.fromMap', () {
    test('date sütunu yerel güne çevrilir; eksikler sıfır', () {
      final m = DailyHealthMetric.fromMap(const {
        'metric_date': '2026-11-16',
        'steps': 8432,
        'sleep_minutes': 452,
      });
      expect(m.day, DateTime(2026, 11, 16));
      expect(m.steps, 8432);
      expect(m.activeKcal, 0);
      expect(m.sleepMinutes, 452);
    });
  });

  group('WeightEntry.fromMap', () {
    test('numeric ve zaman damgası', () {
      final w = WeightEntry.fromMap(const {
        'id': 'w1',
        'weight_kg': 84,
        'logged_at': '2026-11-16T05:00:00+00:00',
      });
      expect(w.weightKg, 84.0);
      expect(w.loggedAt.isUtc, isFalse);
      expect(w.loggedAt.toUtc(), DateTime.utc(2026, 11, 16, 5));
    });
  });

  group('DailyNutritionTotal.fromLogRows', () {
    test('yerel güne göre toplar ve günleri sıralar', () {
      String at(int day, int hour) =>
          DateTime(2026, 11, day, hour).toUtc().toIso8601String();
      final totals = DailyNutritionTotal.fromLogRows([
        {'eaten_at': at(17, 8), 'calories': 400, 'protein_g': 30},
        {'eaten_at': at(16, 23), 'calories': 150.5, 'protein_g': 10, 'carbs_g': 20, 'fat_g': 3},
        {'eaten_at': at(16, 0), 'calories': 330, 'protein_g': 62.5, 'fat_g': 7.2},
        {'eaten_at': at(16, 13), 'calories': null},
        {'eaten_at': 'bozuk', 'calories': 999},
        {'calories': 999},
      ]);
      expect(totals.map((t) => t.day), [DateTime(2026, 11, 16), DateTime(2026, 11, 17)]);
      expect(totals[0].calories, 480.5);
      expect(totals[0].proteinG, 72.5);
      expect(totals[0].carbsG, 20);
      expect(totals[0].fatG, closeTo(10.2, 1e-9));
      expect(totals[0].entryCount, 3);
      expect(totals[1].calories, 400);
      expect(totals[1].entryCount, 1);
    });

    test('boş liste', () {
      expect(DailyNutritionTotal.fromLogRows(const []), isEmpty);
    });
  });

  group('MonthHealthSummary.from', () {
    test('veri yoksa ortalamalar null', () {
      final s = MonthHealthSummary.from(
        metrics: const [],
        nutrition: const [],
        weights: const [],
      );
      expect(s.avgSteps, isNull);
      expect(s.avgSleepMinutes, isNull);
      expect(s.avgCalories, isNull);
      expect(s.avgProteinG, isNull);
      expect(s.weightStartKg, isNull);
      expect(s.weightEndKg, isNull);
      expect(s.weightChangeKg, isNull);
      expect(s.daysWithData, 0);
    });

    test('ortalamalar yalnızca verisi olan günlerden; kilo ilk → son ölçüm', () {
      final s = MonthHealthSummary.from(
        metrics: [
          DailyHealthMetric(day: DateTime(2026, 11, 1), steps: 10000, sleepMinutes: 420),
          DailyHealthMetric(day: DateTime(2026, 11, 2), steps: 5001),
          DailyHealthMetric(day: DateTime(2026, 11, 3), sleepMinutes: 481),
          DailyHealthMetric(day: DateTime(2026, 11, 4), activeKcal: 300),
          DailyHealthMetric(day: DateTime(2026, 11, 5)),
        ],
        nutrition: [
          DailyNutritionTotal(day: DateTime(2026, 11, 1), calories: 2000, proteinG: 160, entryCount: 4),
          DailyNutritionTotal(day: DateTime(2026, 11, 2), calories: 1800, proteinG: 150, entryCount: 3),
          DailyNutritionTotal(day: DateTime(2026, 11, 3)),
        ],
        weights: [
          WeightEntry(id: 'b', weightKg: 83.2, loggedAt: DateTime(2026, 11, 20, 8)),
          WeightEntry(id: 'a', weightKg: 84.5, loggedAt: DateTime(2026, 11, 1, 8)),
          WeightEntry(id: 'c', weightKg: 83.9, loggedAt: DateTime(2026, 11, 10, 8)),
        ],
      );
      expect(s.avgSteps, 7501); // (10000 + 5001) / 2 = 7500.5 → 7501
      expect(s.avgSleepMinutes, 451); // (420 + 481) / 2 = 450.5 → 451
      expect(s.avgCalories, 1900);
      expect(s.avgProteinG, 155);
      expect(s.weightStartKg, 84.5);
      expect(s.weightEndKg, 83.2);
      expect(s.weightChangeKg, closeTo(-1.3, 1e-9));
      expect(s.daysWithData, 4);
    });

    test('tek ölçüm: başlangıç = bitiş', () {
      final s = MonthHealthSummary.from(
        metrics: const [],
        nutrition: const [],
        weights: [WeightEntry(id: 'a', weightKg: 80, loggedAt: DateTime(2026, 11, 3))],
      );
      expect(s.weightStartKg, 80);
      expect(s.weightEndKg, 80);
      expect(s.weightChangeKg, 0);
    });
  });

  group('TaskItem yazma', () {
    final task = TaskItem(
      id: 't1',
      title: '  Rapor ',
      description: '   ',
      category: 'Pusholder',
      priority: 'high',
      status: 'todo',
      assignee: ' Duhan ',
      dueAt: DateTime(2026, 11, 20, 10),
      remindAt: DateTime(2026, 11, 20, 9, 30),
    );

    test('toWriteMap: kırpar, boşu null yapar, zamanı UTC yazar', () {
      final map = task.toWriteMap();
      expect(map['title'], 'Rapor');
      expect(map['description'], isNull);
      expect(map['assignee'], 'Duhan');
      expect(map['category'], 'Pusholder');
      expect(map['priority'], 'high');
      expect(DateTime.parse(map['due_at'] as String),
          DateTime(2026, 11, 20, 10).toUtc());
      expect(map['remind_at'], endsWith('Z'));
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('id'), isFalse);
    });

    test('notify: varsayılan açık; yazılır, okunur, kopyada korunur', () {
      expect(task.notify, isTrue);
      expect(task.toWriteMap()['notify'], isTrue);

      final off = task.copyWith(notify: false);
      expect(off.toWriteMap()['notify'], isFalse);
      expect(off.copyWith(title: 'x').notify, isFalse);

      const row = {'id': 't9', 'title': 'Eski satır'};
      // Sütunu olmayan (eski) satır bildirimli sayılır.
      expect(TaskItem.fromMap(row).notify, isTrue);
      expect(TaskItem.fromMap({...row, 'notify': false}).notify, isFalse);
    });

    test('scheduledAt: termin, yoksa hatırlatma', () {
      expect(task.scheduledAt, DateTime(2026, 11, 20, 10));
      expect(task.copyWith(clearDueAt: true).scheduledAt,
          DateTime(2026, 11, 20, 9, 30));
      expect(task.copyWith(clearDueAt: true, clearRemindAt: true).scheduledAt,
          isNull);
    });

    test('copyWith: alan değiştirir, clear* boşaltır', () {
      final done = task.copyWith(status: 'done', completedAt: DateTime(2026, 11, 21));
      expect(done.isDone, isTrue);
      expect(done.completedAt, DateTime(2026, 11, 21));
      expect(done.title, task.title);
      final reopened = done.copyWith(status: 'todo', clearCompletedAt: true);
      expect(reopened.completedAt, isNull);
      expect(task.copyWith(clearAssignee: true).assignee, isNull);
      expect(task.copyWith(clearDescription: true).description, isNull);
      expect(task.copyWith().dueAt, task.dueAt);
    });

    test('fromMap completed_at okur', () {
      final t = TaskItem.fromMap(const {
        'id': 't',
        'title': 'x',
        'status': 'done',
        'completed_at': '2026-11-16T12:00:00Z',
      });
      expect(t.completedAt!.toUtc(), DateTime.utc(2026, 11, 16, 12));
    });
  });

  group('NoteItem', () {
    test('fromMap varsayılanları ve tam satır', () {
      final bare = NoteItem.fromMap(const {'id': 'n1', 'title': 'Not'});
      expect(bare.content, '');
      expect(bare.category, 'Kişisel');
      expect(bare.isPinned, isFalse);
      expect(bare.updatedAt, isNull);

      final full = NoteItem.fromMap(const {
        'id': 'n2',
        'title': 'Toplantı',
        'content': 'Gündem',
        'category': 'Toplantı',
        'is_pinned': true,
        'created_at': '2026-11-01T09:00:00Z',
        'updated_at': '2026-11-02T09:00:00Z',
      });
      expect(full.isPinned, isTrue);
      expect(full.updatedAt!.toUtc(), DateTime.utc(2026, 11, 2, 9));
    });

    test('toWriteMap kırpar; copyWith kimliği ve tarihleri korur', () {
      final note = NoteItem(
        id: 'n',
        title: ' Başlık ',
        content: ' içerik\n',
        createdAt: DateTime(2026, 11, 1),
      );
      expect(note.toWriteMap(), {
        'title': 'Başlık',
        'content': 'içerik',
        'category': 'Kişisel',
        'is_pinned': false,
      });
      final pinned = note.copyWith(isPinned: true, category: 'Fikir');
      expect(pinned.id, 'n');
      expect(pinned.isPinned, isTrue);
      expect(pinned.category, 'Fikir');
      expect(pinned.createdAt, DateTime(2026, 11, 1));
    });
  });
}
