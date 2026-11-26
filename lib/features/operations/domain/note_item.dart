import '../../../core/config/app_targets.dart';
import '../../../core/text_limits.dart';

/// `notes` tablosundaki bir satır.
class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    this.content = '',
    this.category = 'Kişisel',
    this.isPinned = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final String category;
  final bool isPinned;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NoteItem.fromMap(Map<String, dynamic> map) => NoteItem(
        id: map['id'] as String,
        title: map['title'] as String,
        content: map['content'] as String? ?? '',
        category:
            AppTargets.normalizeWork(map['category'] as String? ?? 'Kişisel'),
        isPinned: map['is_pinned'] as bool? ?? false,
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
      );

  /// Formdan düzenlenebilen sütunlar.
  Map<String, dynamic> toWriteMap() => {
        'title': title.trim(),
        'content': clipText(content.trim(), TextLimits.noteContent),
        'category': category,
        'is_pinned': isPinned,
      };

  NoteItem copyWith({
    String? title,
    String? content,
    String? category,
    bool? isPinned,
  }) =>
      NoteItem(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        category: category ?? this.category,
        isPinned: isPinned ?? this.isPinned,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
