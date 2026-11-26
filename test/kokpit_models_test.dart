import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/operations/domain/task_item.dart';

void main() {
  group('NutritionSummary.fromRows', () {
    test('boş liste -> sıfırlar', () {
      final s = NutritionSummary.fromRows(const []);
      expect([s.calories, s.proteinG, s.carbsG, s.fatG], [0, 0, 0, 0]);
      expect(s.entryCount, 0);
    });

    test('int, double ve null karışık satırlar toplanır', () {
      final s = NutritionSummary.fromRows([
        {'calories': 330, 'protein_g': 62.5, 'carbs_g': 0, 'fat_g': 7.2},
        {'calories': 150.5, 'protein_g': null, 'carbs_g': 30, 'fat_g': null},
        {'calories': null},
      ]);
      expect(s.calories, 480.5);
      expect(s.proteinG, 62.5);
      expect(s.carbsG, 30);
      expect(s.fatG, closeTo(7.2, 1e-9));
      expect(s.entryCount, 3);
    });
  });

  group('TaskItem.fromMap', () {
    test('tam satır', () {
      final t = TaskItem.fromMap(const {
        'id': 't1',
        'title': 'Vardiya çizelgesi',
        'description': 'Gelecek hafta',
        'category': 'Ekip',
        'priority': 'high',
        'status': 'in_progress',
        'assignee': 'Ayşe',
        'due_at': '2026-11-17T12:00:00+00:00',
        'remind_at': '2026-11-17T11:30:00+00:00',
      });
      expect(t.category, 'Ekip');
      expect(t.priority, 'high');
      expect(t.isDone, isFalse);
      expect(t.assignee, 'Ayşe');
      expect(t.dueAt!.isUtc, isFalse);
      expect(t.dueAt!.toUtc(), DateTime.utc(2026, 11, 17, 12));
      expect(t.remindAt!.toUtc(), DateTime.utc(2026, 11, 17, 11, 30));
    });

    test('varsayılanlar ve eksik tarihler', () {
      final t = TaskItem.fromMap(const {'id': 't2', 'title': 'Not'});
      expect(t.category, 'Kişisel');
      expect(t.priority, 'medium');
      expect(t.status, 'todo');
      expect(t.dueAt, isNull);
      expect(t.remindAt, isNull);
    });

    test('bozuk tarih null', () {
      final t = TaskItem.fromMap(const {
        'id': 't3',
        'title': 'x',
        'status': 'done',
        'due_at': '2026-11-20T18:00:00Z',
        'remind_at': 'bozuk',
      });
      expect(t.isDone, isTrue);
      expect(t.remindAt, isNull);
      expect(t.dueAt!.toUtc(), DateTime.utc(2026, 11, 20, 18));
    });
  });
}
