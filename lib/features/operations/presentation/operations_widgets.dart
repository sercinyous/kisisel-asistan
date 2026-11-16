import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const String opsSaveError =
    'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

/// Veritabanı `char_length` kod noktası sayar; aynı ölçüyle doğrularız.
String? validateTitle(String? value, int max) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'Başlık boş olamaz.';
  if (text.runes.length > max) return 'En fazla $max karakter.';
  return null;
}

/// Bölüm başlığı + "Ekle" eylemi.
class OpsSectionHeader extends StatelessWidget {
  const OpsSectionHeader({super.key, required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Ekle'),
        ),
      ],
    );
  }
}

/// Yatay kaydırılan tek seçimli filtre çipleri.
class OpsFilterChips<T> extends StatelessWidget {
  const OpsFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, (value, label)) in options.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(label),
              showCheckmark: false,
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
          ],
        ],
      ),
    );
  }
}

/// Formlarda alt satıra kırılan tek seçimli çipler.
class OpsChoiceWrap<T> extends StatelessWidget {
  const OpsChoiceWrap({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label),
            showCheckmark: false,
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
      ],
    );
  }
}

class OpsFieldLabel extends StatelessWidget {
  const OpsFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class OpsLoading extends StatelessWidget {
  const OpsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Boş ve hata durumları; [onRetry] verilirse "Tekrar dene" gösterilir.
class OpsMessage extends StatelessWidget {
  const OpsMessage({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Tekrar dene'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Satır sonundaki Düzenle / Sil menüsü.
class OpsItemMenu extends StatelessWidget {
  const OpsItemMenu({super.key, required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Seçenekler',
      icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      onSelected: (edit) => edit ? onEdit() : onDelete(),
      itemBuilder: (context) => const [
        PopupMenuItem(value: true, child: Text('Düzenle')),
        PopupMenuItem(value: false, child: Text('Sil')),
      ],
    );
  }
}

/// Silme onayı; yalnızca "Sil" seçilirse `true`.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Form sayfasını klavyenin üstünde kalan alt sayfa olarak açar.
/// Kayıt yapıldıysa `true`.
Future<bool> showOpsSheet(BuildContext context, Widget sheet) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
    ),
    builder: (context) => sheet,
  );
  return saved ?? false;
}

/// Form iskeleti: başlık, kaydırılan alanlar ve altta sabit "Kaydet".
class OpsSheetFrame extends StatelessWidget {
  const OpsSheetFrame({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.saving,
    required this.onSave,
    this.error,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final bool saving;
  final VoidCallback onSave;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Klavye açılınca içerik ve Kaydet butonu üstünde kalır.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.danger),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: saving ? null : onSave,
                child: saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarih/saat seçici satırı: değer butonu + (varsa) temizle.
class OpsPickerRow extends StatelessWidget {
  const OpsPickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: Icon(icon, size: 20),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (onClear != null)
          IconButton(
            tooltip: 'Temizle',
            onPressed: onClear,
            icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

String formatTimeOfDay(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
