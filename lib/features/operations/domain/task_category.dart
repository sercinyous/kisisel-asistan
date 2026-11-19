import '../../../core/config/app_targets.dart';

/// Kullanıcının yönettiği görev kategorisi (`user_settings.task_categories`
/// jsonb dizisinin bir öğesi). Simge ve renk arayüz katmanında çözülen
/// anahtarlardır ([TaskCategory.iconKeys], [TaskCategory.colorKeys]); renk
/// anahtarı bir `AppColors` rol adıdır.
class TaskCategory {
  const TaskCategory({
    required this.name,
    required this.icon,
    required this.color,
    this.enabled = true,
    this.custom = false,
  });

  /// Görev satırına yazılan değer (`tasks.category`).
  final String name;
  final String icon;
  final String color;

  /// Kapalıysa seçicilerde, filtrelerde ve AI önerilerinde görünmez; mevcut
  /// görevler kategorisini korur.
  final bool enabled;

  /// Kullanıcının eklediği (taslak ya da özel) kategori: yeniden adlandırılır
  /// ve silinir. Yerleşik dört kategori yalnızca açılıp kapatılır.
  final bool custom;

  /// Ad sınırı; supabase/schema.sql'deki `tasks_category_check` ile aynıdır.
  static const int nameMax = 40;

  /// En çok bu kadar kategori saklanır (schema.sql'deki check ile aynı).
  static const int maxCount = 40;

  static const List<String> iconKeys = [
    'work',
    'group',
    'payments',
    'person',
    'school',
    'sport',
    'home',
    'health',
    'project',
    'shopping',
    'family',
    'growth',
    'travel',
    'idea',
    'pet',
    'car',
  ];

  static const List<String> colorKeys = [
    'ops',
    'accent',
    'fitness',
    'nutrition',
    'warning',
    'danger',
    'textSecondary',
  ];

  /// Yerleşik kategoriler (eski sabit liste); renkleri
  /// `AppColors.forTaskCategory` ile aynıdır.
  static const List<TaskCategory> defaults = [
    TaskCategory(name: AppTargets.workCategory, icon: 'work', color: 'ops'),
    TaskCategory(name: 'Ekip', icon: 'group', color: 'accent'),
    TaskCategory(name: 'Finans', icon: 'payments', color: 'warning'),
    TaskCategory(name: 'Kişisel', icon: 'person', color: 'fitness'),
  ];

  /// "Kategori Taslakları": tek dokunuşla eklenen hazır kategoriler.
  static const List<TaskCategory> templates = [
    TaskCategory(name: 'Okul', icon: 'school', color: 'accent', custom: true),
    TaskCategory(name: 'Spor', icon: 'sport', color: 'fitness', custom: true),
    TaskCategory(name: 'Ev', icon: 'home', color: 'nutrition', custom: true),
    TaskCategory(name: 'Finans', icon: 'payments', color: 'warning'),
    TaskCategory(name: 'Sağlık', icon: 'health', color: 'danger', custom: true),
    TaskCategory(name: 'Proje', icon: 'project', color: 'ops', custom: true),
    TaskCategory(
      name: 'Alışveriş',
      icon: 'shopping',
      color: 'warning',
      custom: true,
    ),
    TaskCategory(
        name: 'Aile', icon: 'family', color: 'nutrition', custom: true),
    TaskCategory(
      name: 'Kişisel gelişim',
      icon: 'growth',
      color: 'accent',
      custom: true,
    ),
  ];

  static bool isBuiltIn(String name) =>
      defaults.any((d) => foldName(d.name) == foldName(name));

  /// Türkçe i/ı ve büyük/küçük harf farkını yok sayan karşılaştırma anahtarı.
  static String foldName(String text) => text
      .trim()
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase();

  /// Kırpılmış, tek boşluklu ad; geçersizse `null`. Eski iş adı 'İş'e eşlenir.
  static String? cleanName(Object? value) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || text.runes.length > nameMax) return null;
    if (foldName(text) == foldName(AppTargets.legacyWorkCategory)) {
      return AppTargets.workCategory;
    }
    return text;
  }

  static TaskCategory? fromMap(Object? value) {
    if (value is! Map) return null;
    final name = cleanName(value['name']);
    if (name == null) return null;
    final icon = value['icon'];
    final color = value['color'];
    return TaskCategory(
      name: name,
      icon: icon is String && iconKeys.contains(icon) ? icon : 'idea',
      color: color is String && colorKeys.contains(color) ? color : 'accent',
      enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      custom: !isBuiltIn(name) && value['custom'] != false,
    );
  }

  /// jsonb dizisini okur. `null` ya da bozuk değer → yerleşik liste. Yinelenen
  /// adlar atlanır. Yerleşik kategoriler silinemez: listede yoksa açık hâlleriyle
  /// sona eklenir. Hiç açık kategori kalmazsa ilk kategori açılır.
  static List<TaskCategory> parseList(Object? value) {
    if (value is! List) return defaults;
    final result = <TaskCategory>[];
    final seen = <String>{};
    for (final item in value) {
      final category = fromMap(item);
      if (category == null || !seen.add(foldName(category.name))) continue;
      result.add(category);
      if (result.length >= maxCount) break;
    }
    for (final d in defaults) {
      if (seen.add(foldName(d.name))) result.add(d);
    }
    return ensureActive(result);
  }

  static List<TaskCategory> ensureActive(List<TaskCategory> list) {
    if (list.isEmpty) return defaults;
    if (list.any((c) => c.enabled)) return List.unmodifiable(list);
    return List.unmodifiable([
      list.first.copyWith(enabled: true),
      ...list.skip(1),
    ]);
  }

  static List<Map<String, dynamic>> toJsonList(List<TaskCategory> list) =>
      [for (final c in list) c.toMap()];

  /// Açık kategorilerin adları (seçici, filtre, AI).
  static List<String> activeNames(List<TaskCategory> list) => [
        for (final c in list)
          if (c.enabled) c.name
      ];

  /// [name]'in tanımı; listede yoksa `null` (silinmiş özel kategori).
  static TaskCategory? find(List<TaskCategory> list, String name) {
    final key = foldName(AppTargets.normalizeWork(name));
    for (final c in list) {
      if (foldName(c.name) == key) return c;
    }
    return null;
  }

  /// Görev oluştururken varsayılan: açıksa 'Kişisel', değilse ilk açık.
  static String defaultName(List<TaskCategory> list) {
    final active = activeNames(list);
    if (active.contains('Kişisel')) return 'Kişisel';
    return active.isEmpty ? 'Kişisel' : active.first;
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'icon': icon,
        'color': color,
        'enabled': enabled,
        'custom': custom,
      };

  TaskCategory copyWith({
    String? name,
    String? icon,
    String? color,
    bool? enabled,
  }) =>
      TaskCategory(
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        enabled: enabled ?? this.enabled,
        custom: custom,
      );

  @override
  bool operator ==(Object other) =>
      other is TaskCategory &&
      other.name == name &&
      other.icon == icon &&
      other.color == color &&
      other.enabled == enabled &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(name, icon, color, enabled, custom);
}
