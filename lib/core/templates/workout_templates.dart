/// Antrenman formundaki şablon çipi: seçilince tür, başlık ve süre dolar.
/// Mesafe ve kalori kullanıcıya bırakılır.
class WorkoutTemplate {
  const WorkoutTemplate({
    required this.label,
    required this.workoutType,
    required this.title,
    required this.durationMin,
  });

  /// Çipte görünen ad (süreyi de taşır; tür seçim çipleriyle karışmasın).
  final String label;

  /// `WorkoutLog.workoutTypes` içinden biri.
  final String workoutType;
  final String title;
  final int durationMin;
}

/// Türkçe, sabit antrenman şablonları (sunucuya gitmez).
abstract final class WorkoutTemplates {
  static const List<WorkoutTemplate> all = [
    WorkoutTemplate(
      label: 'Yürüyüş · 30 dk',
      workoutType: 'other',
      title: 'Yürüyüş',
      durationMin: 30,
    ),
    WorkoutTemplate(
      label: 'Ağırlık · 45 dk',
      workoutType: 'weights',
      title: 'Ağırlık antrenmanı',
      durationMin: 45,
    ),
    WorkoutTemplate(
      label: 'Koşu · 30 dk',
      workoutType: 'running',
      title: 'Koşu',
      durationMin: 30,
    ),
    WorkoutTemplate(
      label: 'Yoga · 30 dk',
      workoutType: 'other',
      title: 'Yoga',
      durationMin: 30,
    ),
    WorkoutTemplate(
      label: 'Bisiklet · 45 dk',
      workoutType: 'other',
      title: 'Bisiklet',
      durationMin: 45,
    ),
    WorkoutTemplate(
      label: 'Kickboks · 60 dk',
      workoutType: 'kickboxing',
      title: 'Kickboks',
      durationMin: 60,
    ),
    WorkoutTemplate(
      label: 'Halı saha · 60 dk',
      workoutType: 'football',
      title: 'Halı saha maçı',
      durationMin: 60,
    ),
  ];
}
