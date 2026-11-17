import '../config/app_targets.dart';

/// Görev formundaki şablon çipi: seçilince başlık, kategori ve öncelik dolar.
/// Tarih ve saat kullanıcıya bırakılır; her alan sonradan düzenlenir.
class TaskTemplate {
  const TaskTemplate({
    required this.label,
    required this.title,
    this.category = 'Kişisel',
    this.priority = 'medium',
    this.description,
  });

  /// Çipte görünen kısa ad.
  final String label;

  /// Forma yazılan başlık (kullanıcı devam edip tamamlar).
  final String title;

  /// `AppTargets.taskCategories` içinden biri.
  final String category;

  /// 'low' | 'medium' | 'high'
  final String priority;
  final String? description;
}

/// Türkçe, sabit görev şablonları (sunucuya gitmez).
abstract final class TaskTemplates {
  static const List<TaskTemplate> all = [
    TaskTemplate(label: 'Randevu', title: 'Randevu', priority: 'high'),
    TaskTemplate(
      label: 'Ödeme',
      title: 'Ödeme yap',
      category: 'Finans',
      priority: 'high',
    ),
    TaskTemplate(
      label: 'Fatura',
      title: 'Faturayı öde',
      category: 'Finans',
      priority: 'high',
    ),
    TaskTemplate(label: 'Telefon', title: 'Telefonla ara'),
    TaskTemplate(
      label: 'Alışveriş',
      title: 'Alışveriş',
      priority: 'low',
      description: 'Liste:',
    ),
    TaskTemplate(label: 'Doktor', title: 'Doktor randevusu', priority: 'high'),
    TaskTemplate(label: 'Evrak', title: 'Evrak işlemi'),
    TaskTemplate(
      label: 'Toplantı',
      title: 'Toplantı',
      category: AppTargets.workCategory,
    ),
    TaskTemplate(
      label: 'E-posta',
      title: 'E-postayı yanıtla',
      category: AppTargets.workCategory,
      priority: 'low',
    ),
    TaskTemplate(
      label: 'Teklif',
      title: 'Teklif hazırla',
      category: AppTargets.workCategory,
    ),
  ];
}
