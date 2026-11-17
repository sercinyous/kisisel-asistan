import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/presentation/operations_widgets.dart';

// Sağlık sekmesi bölümlerinin paylaştığı görsel parçalar.

const String healthDeleteError =
    'Silinemedi. Bağlantını kontrol edip tekrar dene.';

/// Dokunma hedeflerinin alt sınırı (pt).
const double healthMinTouch = 44;

/// Bölüm başlığı + sağda tek eylem ("Öğün ekle", "Ekle").
class HealthSectionHeader extends StatelessWidget {
  const HealthSectionHeader({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(healthMinTouch, healthMinTouch),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// Küçük bilgi etiketi ("−0,9 kg bu ay").
class HealthChip extends StatelessWidget {
  const HealthChip(this.text, {super.key, this.color});

  final String text;

  /// Verilirse etiket bu renkle vurgulanır.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            tint == null ? AppColors.surfaceHigh : tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tint ?? AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Yarım genişlikteki kartlar için dikey boş/hata iletisi.
class HealthCompactMessage extends StatelessWidget {
  const HealthCompactMessage({super.key, required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(healthMinTouch, healthMinTouch),
              alignment: Alignment.centerLeft,
            ),
            child: const Text('Tekrar dene'),
          ),
      ],
    );
  }
}

/// Kart içi yükleniyor göstergesi (kart başlığı görünür kalır).
class HealthCardLoading extends StatelessWidget {
  const HealthCardLoading({super.key, this.height = 72});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

/// Liste kartı: satırlar arasında ince ayırıcı.
class HealthListCard extends StatelessWidget {
  const HealthListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            child,
          ],
        ],
      ),
    );
  }
}

/// Liste satırı: renkli ikon, başlık + alt metin, sağda değer ve menü.
class HealthListRow extends StatelessWidget {
  const HealthListRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    Color? color,
    this.value,
    this.valueMuted = false,
    this.trailing,
    this.onTap,
  }) : _color = color;

  /// Boşsa ikon yerine aynı genişlikte girinti bırakılır (alt satır).
  final IconData? icon;
  final Color? _color;

  /// Verilmezse etkin temanın ikincil metin rengi.
  Color get color => _color ?? AppColors.textSecondary;

  final String title;
  final String subtitle;
  final String? value;
  final bool valueMuted;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyph = icon;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: trailing == null ? 16 : 4),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: glyph == null
                    ? null
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: SizedBox(
                          height: 36,
                          child: Icon(glyph, size: 18, color: color),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: glyph == null
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.titleSmall,
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 8),
                Text(
                  value!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: valueMuted
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Yedi günlük kartlarda sütun altı gün kısaltması. Yarım genişlikteki
/// kartta sütun ~19pt olduğundan üç harfli "Pzt" yerine iki harfli kısaltma
/// kullanılır; büyük metin ölçeğinde taşmak yerine küçülür.
class HealthWeekdayLabel extends StatelessWidget {
  const HealthWeekdayLabel(this.day, {super.key, this.highlight = false});

  /// Pazartesi'den Pazar'a.
  static const List<String> _short = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];

  final DateTime day;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _short[day.weekday - 1],
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? AppColors.textPrimary : AppColors.textMuted,
            ),
      ),
    );
  }
}

/// Büyük sayı + küçük birim ("83,6 kg", "3 / 7 bu hafta").
class HealthBigValue extends StatelessWidget {
  const HealthBigValue({
    super.key,
    required this.value,
    required this.unit,
    this.large = false,
    this.singleLine = false,
  });

  final String value;
  final String unit;

  /// Tam genişlikteki kartlarda daha büyük yazılır.
  final bool large;

  /// Tek satır: `FittedBox` içinde içsel yükseklik tek satır ölçülsün. Aksi
  /// halde sarmalanan metin iki satır ölçülür, gerçek yerleşimde tek satır
  /// çizilir ve Bento satırı bir satır fazla yükseklikte kalır.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        large ? theme.textTheme.headlineLarge : theme.textTheme.headlineSmall;
    return Text.rich(
      maxLines: singleLine ? 1 : null,
      softWrap: !singleLine,
      TextSpan(
        text: value,
        style: base?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        children: [
          TextSpan(
            text: ' $unit',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Form alanlarında ondalıklı sayı klavyesi.
const TextInputType healthDecimalKeyboard =
    TextInputType.numberWithOptions(decimal: true);

/// "16 Kas 2026, Pzt"
String healthFormDate(DateTime day) =>
    DateFormat('d MMM y, EEE', AppDates.locale).format(day);

/// Seçilen gün ile saati tek zamana birleştirir.
DateTime combineDateTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);

/// Kayıt zamanı seçimi: (isteğe bağlı) tarih satırı + saat satırı.
/// Geleceğe kayıt girilmediği için takvim bugünde biter.
class HealthWhenPicker extends StatelessWidget {
  const HealthWhenPicker({
    super.key,
    required this.date,
    required this.time,
    required this.onTime,
    this.onDate,
  });

  final DateTime date;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onTime;

  /// Boşsa tarih satırı gösterilmez (yalnızca saat seçilir).
  final ValueChanged<DateTime>? onDate;

  Future<void> _pickDate(BuildContext context) async {
    final today = AppDates.startOfDay(DateTime.now());
    final earliest = DateTime(today.year - 2, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isAfter(today) ? today : date,
      firstDate: date.isBefore(earliest) ? date : earliest,
      lastDate: today,
    );
    if (picked != null) onDate?.call(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked != null) onTime(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onDate != null) ...[
          OpsPickerRow(
            icon: Icons.event_rounded,
            label: healthFormDate(date),
            onTap: () => _pickDate(context),
          ),
          const SizedBox(height: 8),
        ],
        OpsPickerRow(
          icon: Icons.schedule_rounded,
          label: formatTimeOfDay(time),
          onTap: () => _pickTime(context),
        ),
      ],
    );
  }
}
