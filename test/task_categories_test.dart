import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/operations/domain/task_category.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  group('TaskCategory', () {
    test('boş sütun yerleşik listeye düşer ve yazılmaz', () {
      final s = UserSettings.fromMap(const {});
      expect(s.activeTaskCategories, ['İş', 'Ekip', 'Finans', 'Kişisel']);
      expect(s.toMap().containsKey('task_categories'), isFalse);
    });

    test('liste okunur; kapalılar aktif değildir; yerleşikler eksikse eklenir',
        () {
      final s = UserSettings.fromMap({
        'task_categories': [
          {'name': 'Okul', 'icon': 'school', 'color': 'accent', 'custom': true},
          {'name': 'Ekip', 'enabled': false},
          {'name': 'okul'},
          {'name': ''},
        ],
      });
      final names = [for (final c in s.taskCategories) c.name];
      expect(names, ['Okul', 'Ekip', 'İş', 'Finans', 'Kişisel']);
      expect(s.activeTaskCategories, isNot(contains('Ekip')));
      expect(s.taskCategories.first.custom, isTrue);
      expect(s.taskCategories[1].custom, isFalse);
      expect(s.toMap()['task_categories'], hasLength(5));
    });

    test("'Pusholder' adı 'İş'e eşlenir", () {
      expect(TaskCategory.cleanName('pusholder'), 'İş');
      expect(TaskCategory.find(TaskCategory.defaults, 'Pusholder')?.name, 'İş');
    });

    test('hepsi kapalıysa ilki açılır', () {
      final list = TaskCategory.ensureActive([
        for (final c in TaskCategory.defaults) c.copyWith(enabled: false),
      ]);
      expect(TaskCategory.activeNames(list), ['İş']);
    });

    test('copyWith kategorileri değiştirir', () {
      final s = const UserSettings.defaults().copyWith(
        taskCategories: [...TaskCategory.defaults, TaskCategory.templates.first],
      );
      expect(s.activeTaskCategories, contains('Okul'));
    });
  });

  group('AI yalnızca açık kategorileri önerir', () {
    test('kapalı kategori geri dönüş değerine düşer', () {
      final t = ParsedTask.fromJson(
        {'title': 'x', 'category': 'Ekip', 'priority': 'low'},
        allowed: ['Okul', 'Kişisel'],
      );
      expect(t!.category, 'Kişisel');
    });

    test('özel kategori kabul edilir; Pusholder açık İş\'e eşlenir', () {
      final entry = ParsedEntry.fromJson({
        'tasks': [
          {'title': 'a', 'category': 'okul'},
          {'title': 'b', 'category': 'Pusholder'},
        ],
      }, taskCategories: ['İş', 'Okul']);
      expect([for (final t in entry.tasks) t.category], ['Okul', 'İş']);
    });
  });
}
