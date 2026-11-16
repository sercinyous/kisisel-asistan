/// `tasks` tablosundaki bir satır (tek seferlik görev ya da randevu).
class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.status,
    this.description,
    this.assignee,
    this.dueAt,
    this.remindAt,
    this.completedAt,
    this.notify = true,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String priority;
  final String status;
  final String? assignee;
  final DateTime? dueAt;
  final DateTime? remindAt;
  final DateTime? completedAt;

  /// Kapalıysa görev için bildirim planlanmaz (formdaki "Hatırlat").
  final bool notify;

  bool get isDone => status == 'done';

  /// Hatırlatma saati varsa o, yoksa termin.
  DateTime? get effectiveTime => remindAt ?? dueAt;

  /// Takvimde görevin yerleştiği an: termin, yoksa hatırlatma.
  DateTime? get scheduledAt => dueAt ?? remindAt;

  /// Gelecekteki hatırlatma varsa o; hatırlatma geçtiyse termin.
  DateTime? nextTime(DateTime now) {
    final r = remindAt, d = dueAt;
    if (r != null && !r.isBefore(now)) return r;
    if (d != null && !d.isBefore(now)) return d;
    return r ?? d;
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) => TaskItem(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String?,
        category: map['category'] as String? ?? 'Kişisel',
        priority: map['priority'] as String? ?? 'medium',
        status: map['status'] as String? ?? 'todo',
        assignee: map['assignee'] as String?,
        dueAt: _date(map['due_at']),
        remindAt: _date(map['remind_at']),
        completedAt: _date(map['completed_at']),
        notify: map['notify'] as bool? ?? true,
      );

  /// Formdan düzenlenebilen sütunlar. Durum ve tamamlanma zamanı
  /// `complete` / `reopen` ile ayrıca yönetilir.
  Map<String, dynamic> toWriteMap() => {
        'title': title.trim(),
        'description': _blankToNull(description),
        'category': category,
        'priority': priority,
        'assignee': _blankToNull(assignee),
        'due_at': dueAt?.toUtc().toIso8601String(),
        'remind_at': remindAt?.toUtc().toIso8601String(),
        'notify': notify,
      };

  /// `clear*` bayrakları ilgili alanı boşaltır (null vermek "değiştirme" demektir).
  TaskItem copyWith({
    String? title,
    String? description,
    String? category,
    String? priority,
    String? status,
    String? assignee,
    DateTime? dueAt,
    DateTime? remindAt,
    DateTime? completedAt,
    bool? notify,
    bool clearDescription = false,
    bool clearAssignee = false,
    bool clearDueAt = false,
    bool clearRemindAt = false,
    bool clearCompletedAt = false,
  }) =>
      TaskItem(
        id: id,
        title: title ?? this.title,
        description: clearDescription ? null : (description ?? this.description),
        category: category ?? this.category,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        assignee: clearAssignee ? null : (assignee ?? this.assignee),
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        remindAt: clearRemindAt ? null : (remindAt ?? this.remindAt),
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        notify: notify ?? this.notify,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
