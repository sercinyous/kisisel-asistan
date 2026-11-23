import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/ritim_top/ritim_top.dart';
import '../domain/parsed_entry.dart';
import '../domain/quick_add_mode.dart';
import 'ai_quick_add_controller.dart';
import 'quick_add_mode_sheet.dart';

/// AI giriş alt sayfası; iş ya da sağlık alanında açılır.
///
/// Akış: metni yaz → **Ayrıştır** (Gemini) → önizlemeyi kontrol et →
/// **Kaydet** (tüm tablolar tek transaction). Önizleme adımı, AI'ın yanlış
/// anladığı bir kalemin veritabanına sessizce yazılmasını engeller.
/// Metin diğer alana aitse kayıt üretilmez; kullanıcı metniyle birlikte
/// o alanın girişine yönlendirilir.
class AiQuickAddModal extends ConsumerStatefulWidget {
  const AiQuickAddModal({required this.mode, this.initialText, super.key});

  final QuickAddMode mode;
  final String? initialText;

  /// Kayıt yapıldıysa kaydedilen kalem sayısını döndürür.
  static Future<int?> show(
    BuildContext context, {
    required QuickAddMode mode,
    String? initialText,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => AiQuickAddModal(mode: mode, initialText: initialText),
    );
  }

  @override
  ConsumerState<AiQuickAddModal> createState() => _AiQuickAddModalState();
}

class _AiQuickAddModalState extends ConsumerState<AiQuickAddModal> {
  late final TextEditingController _textController =
      TextEditingController(text: widget.initialText);
  final FocusNode _focusNode = FocusNode();

  late QuickAddMode _mode = widget.mode;

  /// Alan değiştirilmeden önce bu sayfada kaydedilen kalemler.
  int _savedBeforeSwitch = 0;

  /// Bu sayfada kalemleri kaydedilmiş alanlar. Metin aynen taşındığı için
  /// yeni alan o kısmı yine "diğer alan" diye işaretler; aynı kayıtlar ikinci
  /// kez yazılmasın diye o alana geri yönlendirilmez.
  final Set<QuickAddMode> _savedModes = {};

  static const Map<QuickAddMode, List<String>> _examples = {
    QuickAddMode.work: [
      'Yarın 15:00\'te dişçi randevum var',
      'Her ayın 15\'i maaş ödemesi',
      'Her pazartesi 11:00 ekip toplantısı',
    ],
    QuickAddMode.health: [
      'Öğlen 200 gr tavuk göğsü ve 2 dilim tam çavdar ekmeği yedim',
      'Bugün 45 dk ağırlık çalıştım',
      'Sabah 83.9 kiloydum',
    ],
  };

  static const Map<QuickAddMode, String> _hints = {
    QuickAddMode.work: 'Örn. Yarın 15:00\'te dişçi randevum var, her ayın '
        '15\'i maaş ödemesi',
    QuickAddMode.health: 'Örn. Öğlen 200 gr tavuk yedim, akşam 45 dk '
        'ağırlık çalıştım',
  };

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    _focusNode.unfocus();
    await ref
        .read(quickAddControllerProvider(_mode).notifier)
        .parse(_textController.text);
  }

  /// [thenSwitch]: karışık metinde bu alanın kalemleri kaydedildikten sonra
  /// sayfa kapanmaz, metinle birlikte diğer alana geçilir.
  Future<void> _save({bool thenSwitch = false}) async {
    final provider = quickAddControllerProvider(_mode);
    final ok = await ref.read(provider.notifier).save();
    if (!ok || !mounted) return;
    final saved = ref.read(provider).savedCount;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    if (thenSwitch) {
      setState(() {
        _savedBeforeSwitch += saved;
        _savedModes.add(_mode);
        _mode = _mode.other;
      });
      return;
    }
    // Kayıt sürerken sayfa kapatıldıysa (çıkış animasyonu sürüyor olabilir)
    // gecikmiş pop alttaki rotayı kapatmasın.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    Navigator.of(context).pop(_savedBeforeSwitch + saved);
  }

  /// Metin aynen taşınır; eski alanın akışı izlenmediği için kendiliğinden
  /// kapanır, yeni alan boş başlar.
  void _switchMode() {
    setState(() => _mode = _mode.other);
    _focusNode.requestFocus();
  }

  void _close() => Navigator.of(context)
      .pop(_savedBeforeSwitch > 0 ? _savedBeforeSwitch : null);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quickAddControllerProvider(_mode));
    final controller = ref.read(quickAddControllerProvider(_mode).notifier);
    final inPreview = state.entry != null &&
        (state.status == QuickAddStatus.preview ||
            state.status == QuickAddStatus.saving ||
            state.status == QuickAddStatus.saved);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    final Widget? otherDomainBanner =
        !state.otherDomain || _savedModes.contains(_mode.other)
            ? null
            : _OtherDomainBanner(
                target: _mode.other,
                mixed: inPreview,
                summary: state.otherDomainSummary,
                onSwitch: state.isBusy
                    ? null
                    : inPreview
                        ? () => _save(thenSwitch: true)
                        : _switchMode,
              );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Header(
                    mode: _mode,
                    inPreview: inPreview,
                    onClose: state.isBusy ? null : _close,
                  ),
                  const SizedBox(height: 16),
                  if (inPreview)
                    Flexible(
                      child: _PreviewList(
                        entry: state.entry!,
                        enabled: !state.isBusy,
                        onRemove: controller.remove,
                        header: otherDomainBanner,
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: _InputSection(
                          controller: _textController,
                          focusNode: _focusNode,
                          enabled: !state.isBusy,
                          hint: _hints[_mode]!,
                          examples: _examples[_mode]!,
                          notice: otherDomainBanner ??
                              (_savedBeforeSwitch > 0
                                  ? _SavedNotice(count: _savedBeforeSwitch)
                                  : null),
                          onExample: (text) {
                            _textController.text = text;
                            _textController.selection =
                                TextSelection.collapsed(offset: text.length);
                          },
                        ),
                      ),
                    ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: state.errorMessage!),
                  ],
                  const SizedBox(height: 16),
                  if (inPreview)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                state.isBusy ? null : controller.backToEdit,
                            child: const Text('Düzenle'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: state.isBusy ? null : _save,
                            icon: state.status == QuickAddStatus.saving
                                ? const _ButtonSpinner()
                                : const Icon(Icons.check_outlined),
                            label: Text(
                              state.status == QuickAddStatus.saving
                                  ? 'Kaydediliyor…'
                                  : '${state.entry!.totalCount} kaydı kaydet',
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    if (state.status == QuickAddStatus.parsing) ...[
                      const Center(child: RitimTop(size: 40)),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed:
                          state.isBusy || _textController.text.trim().isEmpty
                              ? null
                              : _parse,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        state.status == QuickAddStatus.parsing
                            ? 'Ayrıştırılıyor…'
                            : 'Ayrıştır',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.mode,
    required this.inPreview,
    required this.onClose,
  });

  final QuickAddMode mode;
  final bool inPreview;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = mode.color;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadii.inner),
          ),
          child: Icon(mode.icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inPreview ? 'Bunları anladım' : mode.title,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                inPreview
                    ? 'Kontrol et, yanlış olanı çıkar, sonra kaydet.'
                    : '${mode.scopeHint} Tek cümleyle yaz.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          tooltip: 'Kapat',
          icon: Icon(Icons.close_outlined, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Metnin (bir kısmının) diğer giriş alanına ait olduğunu söyler ve oraya
/// geçiş düğmesi sunar.
class _OtherDomainBanner extends StatelessWidget {
  const _OtherDomainBanner({
    required this.target,
    required this.mixed,
    required this.summary,
    required this.onSwitch,
  });

  /// Metnin ait olduğu alan.
  final QuickAddMode target;

  /// Bu alanın kalemleri de var (önizleme); geçişten önce onlar kaydedilir.
  final bool mixed;
  final String? summary;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.swap_horiz_outlined,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mixed
                          ? 'Metnin bir kısmı ${target.recordNoun} gibi görünüyor.'
                          : 'Bu bir ${target.recordNoun} gibi görünüyor.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onSwitch,
              child: Text(
                mixed ? target.saveAndSwitchLabel : target.switchLabel,
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alan değiştirildikten sonra, önceki alanda kaydedilenleri hatırlatır.
class _SavedNotice extends StatelessWidget {
  const _SavedNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_outlined,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count kayıt eklendi. Metnin kalan kısmını buradan '
              'ayrıştırabilirsin.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hint,
    required this.examples,
    required this.notice,
    required this.onExample,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hint;
  final List<String> examples;

  /// Metin alanının hemen altında gösterilen uyarı/bilgi bandı.
  final Widget? notice;
  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
        if (notice != null) ...[
          const SizedBox(height: 12),
          notice!,
        ],
        const SizedBox(height: 14),
        Text('Örnekler', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        for (final example in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadii.inner),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.inner),
                onTap: enabled ? () => onExample(example) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.north_west_outlined,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          example,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({
    required this.entry,
    required this.enabled,
    required this.onRemove,
    required this.header,
  });

  final ParsedEntry entry;
  final bool enabled;
  final void Function(ParsedKind kind, int index) onRemove;

  /// Kalemlerle birlikte kayan üst bant (diğer alan uyarısı).
  final Widget? header;

  static String _num(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (header != null) header!,
      for (final (i, n) in entry.nutrition.indexed)
        _PreviewTile(
          icon: Icons.restaurant_outlined,
          color: AppColors.nutrition,
          tag: 'Beslenme · ${n.mealLabel}',
          title: n.quantityText == null
              ? n.foodName
              : '${n.foodName} · ${n.quantityText}',
          subtitle: '${_num(n.calories)} kcal · P ${_num(n.proteinG)} g · '
              'K ${_num(n.carbsG)} g · Y ${_num(n.fatG)} g'
              '${n.eatenAt == null ? '' : '\n${AppDates.relativeDayTime(n.eatenAt!)}'}',
          onRemove: enabled ? () => onRemove(ParsedKind.nutrition, i) : null,
        ),
      for (final (i, t) in entry.tasks.indexed)
        _PreviewTile(
          icon: Icons.task_alt_outlined,
          color: AppColors.forTaskCategory(t.category),
          tag: 'Görev · ${t.category}'
              '${t.priority == 'high' ? ' · Yüksek öncelik' : ''}',
          title: t.title,
          subtitle: [
            if (t.assignee != null) 'İlgili: ${t.assignee}',
            if (t.dueAt != null) AppDates.relativeDayTime(t.dueAt!),
            if (t.dueAt != null || t.remindAt != null) 'Hatırlatma açık',
            if (t.dueAt == null && t.assignee == null) 'Tarihsiz görev',
          ].join(' · '),
          onRemove: enabled ? () => onRemove(ParsedKind.task, i) : null,
        ),
      for (final (i, r) in entry.routines.indexed)
        _PreviewTile(
          icon: Icons.event_repeat_outlined,
          color: AppColors.forRoutineCategory(r.category),
          tag: '${r.isMonthly ? 'Aylık iş' : 'Tekrarlayan iş'} · ${r.scope}'
              ' · ${r.categoryLabel}',
          title: r.title,
          subtitle: r.scheduleLabel,
          onRemove: enabled ? () => onRemove(ParsedKind.routine, i) : null,
        ),
      for (final (i, r) in entry.reminders.indexed)
        _PreviewTile(
          icon: Icons.alarm_outlined,
          color: AppColors.accent,
          tag: 'Hatırlatıcı',
          title: r.title,
          subtitle: r.scheduleLabel,
          onRemove: enabled ? () => onRemove(ParsedKind.reminder, i) : null,
        ),
      for (final (i, w) in entry.workouts.indexed)
        _PreviewTile(
          icon: Icons.fitness_center_outlined,
          color: AppColors.fitness,
          tag: 'Antrenman · ${w.typeLabel}',
          title: w.title,
          subtitle: [
            if (w.durationMin != null) '${w.durationMin} dk',
            if (w.distanceKm != null) '${_num(w.distanceKm!)} km',
            if (w.caloriesBurned != null) '${w.caloriesBurned} kcal',
            if (w.performedAt != null) AppDates.relativeDayTime(w.performedAt!),
          ].join(' · '),
          onRemove: enabled ? () => onRemove(ParsedKind.workout, i) : null,
        ),
      for (final (i, w) in entry.weights.indexed)
        _PreviewTile(
          icon: Icons.monitor_weight_outlined,
          color: AppColors.accent,
          tag: 'Kilo',
          title: '${w.weightKg.toStringAsFixed(1)} kg',
          subtitle: w.measuredAt == null
              ? 'Şimdi'
              : AppDates.relativeDayTime(w.measuredAt!),
          onRemove: enabled ? () => onRemove(ParsedKind.weight, i) : null,
        ),
      for (final (i, n) in entry.notes.indexed)
        _PreviewTile(
          icon: Icons.sticky_note_2_outlined,
          color: AppColors.warning,
          tag: 'Not · ${n.category}',
          title: n.title,
          subtitle: n.content,
          onRemove: enabled ? () => onRemove(ParsedKind.note, i) : null,
        ),
    ];

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: tiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => tiles[index],
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.icon,
    required this.color,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });

  final IconData icon;
  final Color color;
  final String tag;
  final String title;
  final String subtitle;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(title, style: theme.textTheme.titleSmall),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Bu kaydı çıkar',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.inner),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_outlined, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.2),
    );
  }
}
