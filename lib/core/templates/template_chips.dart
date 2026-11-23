import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Formların başındaki "Şablondan başla" çip satırı. Çipe dokunmak yalnızca
/// [onSelected]'i çağırır; formu doldurmak çağıranın işidir (alanlar sonra
/// düzenlenir). Yeni kayıt formlarında gösterilir, düzenlemede gösterilmez.
class TemplateChips<T> extends StatelessWidget {
  const TemplateChips({
    super.key,
    required this.templates,
    required this.labelOf,
    required this.onSelected,
    this.title = 'Şablondan başla',
    this.hint,
  });

  final List<T> templates;
  final String Function(T template) labelOf;
  final ValueChanged<T> onSelected;
  final String title;

  /// Çiplerin altında küçük açıklama (ör. "Değerler yaklaşıktır").
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (index, template) in templates.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      right: index == templates.length - 1 ? 0 : 8,
                    ),
                    child: ActionChip(
                      key: Key('template-$index'),
                      avatar: const Icon(Icons.add_outlined, size: 16),
                      label: Text(labelOf(template)),
                      onPressed: () => onSelected(template),
                    ),
                  ),
              ],
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                hint!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
