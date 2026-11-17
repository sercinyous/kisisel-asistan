import '../../features/routines/domain/routine.dart';

/// Sabit (rutin) formundaki şablon çipi ve ilk kurulumdaki başlangıç
/// rutinleri. Seçilince form dolar; her alan sonradan düzenlenir.
class RoutineTemplate {
  const RoutineTemplate({
    required this.id,
    required this.label,
    required this.title,
    this.frequency = RoutineFrequency.weekly,
    this.daysOfWeek = Routine.everyDay,
    this.dayOfMonth,
    this.hour,
    this.minute,
    this.category = 'kisisel',
    this.starter = false,
  }) : assert(
          (hour == null) == (minute == null),
          'Saat ve dakika birlikte verilir.',
        );

  /// Kararlı kimlik (ilk kurulum seçimi bununla tutulur).
  final String id;

  /// Çipte görünen kısa ad.
  final String label;
  final String title;
  final RoutineFrequency frequency;

  /// ISO gün numaraları (1 = Pazartesi ... 7 = Pazar); aylıkta yok sayılır.
  final List<int> daysOfWeek;

  /// 1..31; yalnızca aylıkta.
  final int? dayOfMonth;
  final int? hour;
  final int? minute;

  /// `Routine.categories` içinden biri.
  final String category;

  /// İlk kurulumun "başlangıç rutinleri" adımında önerilir.
  final bool starter;

  bool get isMonthly => frequency == RoutineFrequency.monthly;
  bool get hasTime => hour != null && minute != null;

  static const List<String> _dayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static const List<String> _dayShort = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  /// "Her gün · 18:30", "Pazar · 20:00", "Pzt, Çar, Cum · 19:00" ya da
  /// "Her ay · ayın 15. günü".
  String get scheduleLabel {
    final time = hasTime
        ? ' · ${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}'
        : '';
    if (isMonthly) return 'Her ay · ayın $dayOfMonth. günü$time';
    final days = daysOfWeek.toSet().toList()..sort();
    if (days.length == 7) return 'Her gün$time';
    if (days.length == 1) return '${_dayNames[days.first - 1]}$time';
    return '${days.map((d) => _dayShort[d - 1]).join(', ')}$time';
  }

  /// Henüz kaydedilmemiş (`id` boş) kişisel rutin taslağı.
  Routine toRoutine({int sortOrder = 0}) => Routine(
        id: '',
        title: title,
        scope: Routine.scopePersonal,
        category: category,
        frequency: frequency,
        daysOfWeek: isMonthly ? Routine.everyDay : daysOfWeek,
        dayOfMonth: isMonthly ? dayOfMonth : null,
        hour: hour,
        minute: minute,
        sortOrder: sortOrder,
      );
}

/// Türkçe, sabit rutin şablonları (sunucuya gitmez).
abstract final class RoutineTemplates {
  static const List<RoutineTemplate> all = [
    RoutineTemplate(
      id: 'su',
      label: 'Su iç',
      title: 'Su iç',
      category: 'beslenme',
      starter: true,
    ),
    RoutineTemplate(
      id: 'yuruyus',
      label: 'Yürüyüş',
      title: 'Yürüyüş yap',
      hour: 18,
      minute: 30,
      category: 'spor',
      starter: true,
    ),
    RoutineTemplate(
      id: 'vitamin',
      label: 'Vitamin',
      title: 'Vitamin al',
      hour: 9,
      minute: 0,
      category: 'beslenme',
      starter: true,
    ),
    RoutineTemplate(
      id: 'ogun-kaydi',
      label: 'Öğünleri kaydet',
      title: 'Öğünlerini kaydet',
      hour: 21,
      minute: 0,
      category: 'beslenme',
      starter: true,
    ),
    RoutineTemplate(
      id: 'haftalik-plan',
      label: 'Haftalık plan',
      title: 'Haftalık planını yap',
      daysOfWeek: [7],
      hour: 20,
      minute: 0,
      starter: true,
    ),
    RoutineTemplate(
      id: 'antrenman',
      label: 'Antrenman',
      title: 'Antrenman',
      daysOfWeek: [1, 3, 5],
      hour: 19,
      minute: 0,
      category: 'spor',
    ),
    RoutineTemplate(
      id: 'uyku',
      label: 'Uykuya hazırlan',
      title: 'Uykuya hazırlan',
      hour: 22,
      minute: 30,
    ),
    RoutineTemplate(
      id: 'kira',
      label: 'Aylık kira',
      title: 'Kirayı öde',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: 1,
      category: 'finans',
      starter: true,
    ),
    RoutineTemplate(
      id: 'fatura',
      label: 'Aylık fatura',
      title: 'Faturaları öde',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: 15,
      category: 'finans',
      starter: true,
    ),
  ];

  /// İlk kurulumda önerilenler.
  static List<RoutineTemplate> get starters =>
      [for (final t in all) if (t.starter) t];

  /// Kimliğe göre şablon; yoksa `null`.
  static RoutineTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
