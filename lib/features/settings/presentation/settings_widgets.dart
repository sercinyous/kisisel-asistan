import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../domain/user_settings.dart';
import 'settings_providers.dart';

/// Sayı alanı sınırları; supabase/schema.sql (user_settings) check'leriyle aynı.
abstract final class SettingsLimits {
  static const double weightMin = 30, weightMax = 250;
  static const int caloriesMin = 800, caloriesMax = 6000;
  static const int proteinMin = 0, proteinMax = 500;
  static const int carbsMin = 0, carbsMax = 800;
  static const int fatMin = 0, fatMax = 400;
  static const int stepsMin = 1000, stepsMax = 60000;
  static const int sleepMin = 180, sleepMax = 900;
  static const int heightMin = UserSettings.heightCmMin;
  static const int heightMax = UserSettings.heightCmMax;
  static const int birthYearMin = UserSettings.birthYearMin;

  /// Doğum yılı üst sınırı: bu yıl − 13 (Kullanım koşullarındaki en küçük yaş).
  static const int birthYearMinAge = 13;
  static const int leadDaysMin = 0, leadDaysMax = 14;
  static const int eventMinutesMin = 0, eventMinutesMax = 1440;
  static const int teamMax = 12;
  static const int teamNameMaxLength = 24;
}

/// Alt sayfaların ortak iskeleti: ayarlar yüklenene kadar bekler, hata olursa
/// yeniden deneme gösterir; yüklenince [builder] ile içeriği çizer.
class SettingsPageScaffold extends ConsumerWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.builder,
  });

  final String title;
  final Widget Function(UserSettings settings) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        bottom: false,
        child: settings.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => SettingsLoadError(
            onRetry: () => ref.invalidate(userSettingsProvider),
          ),
          data: builder,
        ),
      ),
    );
  }
}

class SettingsLoadError extends StatelessWidget {
  const SettingsLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Hesap bilgileri yüklenemedi.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

/// Alt sayfanın altındaki kendi Kaydet düğmesi.
class SettingsSaveBar extends StatelessWidget {
  const SettingsSaveBar({
    super.key,
    required this.enabled,
    required this.saving,
    required this.onSave,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.grid,
          AppSpacing.page,
          AppSpacing.grid,
        ),
        child: FilledButton(
          onPressed: enabled && !saving ? onSave : null,
          child: saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ),
    );
  }
}

/// Kaydedilmemiş değişiklik varken geri çıkışta sorulan soru.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Kaydedilmemiş değişiklikler'),
      content: const Text('Çıkarsan yaptığın değişiklikler kaybolacak.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Düzenlemeye dön'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Vazgeç ve çık'),
        ),
      ],
    ),
  );
  return leave == true;
}

/// Kaydetme sonucunu bildiren kısa mesaj.
void showSettingsSnack(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Alt sayfalarda kaydırılan liste için ortak dolgu (alt barın arkası boş kalır).
const EdgeInsets settingsListPadding = EdgeInsets.fromLTRB(
  AppSpacing.page,
  AppSpacing.grid,
  AppSpacing.page,
  120,
);

/// Başlıklı bölüm kartı.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
              icon: icon, label: title, color: color, trailing: trailing),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Yan yana iki alan; hata metinleri hizayı bozmasın diye üstten hizalanır.
class SettingsFieldRow extends StatelessWidget {
  const SettingsFieldRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpacing.grid),
          Expanded(child: right),
        ],
      ),
    );
  }
}

String _showNumber(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Sayı alanı denetimi; hata yoksa `null`. [optional] ise boş metin geçerlidir.
String? validateSettingsNumber(
  String? text, {
  required num min,
  required num max,
  bool decimal = false,
  bool optional = false,
}) {
  final raw = (text ?? '').trim();
  final range = '${_showNumber(min)}–${_showNumber(max)} arası olmalı';
  if (raw.isEmpty) return optional ? null : range;
  final num? value =
      decimal ? double.tryParse(raw.replaceAll(',', '.')) : int.tryParse(raw);
  if (value == null || value.isNaN || value < min || value > max) {
    return range;
  }
  return null;
}

class SettingsNumberField extends StatelessWidget {
  const SettingsNumberField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.decimal = false,
    this.optional = false,
    this.helper,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final num min;
  final num max;
  final bool decimal;

  /// Boş bırakılabilir (profil alanları); dolu ise yine aralık denetlenir.
  final bool optional;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
        LengthLimitingTextInputFormatter(decimal ? 6 : 5),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) => validateSettingsNumber(
        text,
        min: min,
        max: max,
        decimal: decimal,
        optional: optional,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorMaxLines: 2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class SettingsTimeRow extends StatelessWidget {
  const SettingsTimeRow({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final TimeOfDayValue value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.schedule_outlined, size: 18),
          label: Text(
            value.format(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsStatusRow extends StatelessWidget {
  const SettingsStatusRow({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.actionLabel,
    required this.onAction,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final String status;
  final Color statusColor;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title, style: theme.textTheme.bodyLarge),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing!,
                      ],
                    ],
                  ),
                  Text(
                    status,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: statusColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}

class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}
