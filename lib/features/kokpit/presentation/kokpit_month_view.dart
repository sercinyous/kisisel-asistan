import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/domain/task_item.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/month_calendar.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Ay görünümü: takvim, aylık sabitler, ayın randevuları ve ay özeti.
class KokpitMonthView extends ConsumerStatefulWidget {
  const KokpitMonthView({super.key});

  @override
  ConsumerState<KokpitMonthView> createState() => _KokpitMonthViewState();
}

class _KokpitMonthViewState extends ConsumerState<KokpitMonthView> {
  /// Yazması süren işaretlemeler (dönem → hedef durum). Sunucudan yeni veri
  /// gelene kadar ekranda bu durum gösterilir; aynı kaleme ikinci dokunuş
  /// yok sayılır.
  final Map<RoutineCompletionKey, bool> _pending = {};

  void _showMonth(DateTime month, {DateTime? select}) {
    ref.read(kokpitMonthProvider.notifier).state =
        DateTime(month.year, month.month);
    ref.read(kokpitSelectedDayProvider.notifier).state = select;
  }

  void _selectDay(DateTime day) {
    final selection = ref.read(kokpitSelectedDayProvider.notifier);
    // Seçili güne yeniden dokunmak seçimi kaldırır.
    selection.state = selection.state == day ? null : day;
  }

  Future<void> _toggle(RoutineOccurrence occurrence) async {
    final key = occurrence.completionKey;
    if (_pending.containsKey(key)) return;
    // Yazma sürerken ekran kapanabilir; await sonrası context/ref kullanılmaz.
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pending[key] = !occurrence.completed);
    unawaited(HapticFeedback.selectionClick());

    try {
      await toggleMonthly(ref, occurrence);
    } catch (_) {
      if (mounted) setState(() => _pending.remove(key));
      messenger.showSnackBar(
        const SnackBar(content: Text('Aylık iş güncellenemedi. Tekrar dene.')),
      );
      return;
    }
    try {
      // İyimser durum, tazelenen veri gelene kadar kalır (eski duruma
      // geri sıçrama olmasın).
      await container.read(monthOverviewProvider(occurrence.periodKey).future);
    } catch (_) {
      // Okuma hatası bölümün kendi hata durumunda gösterilir.
    }
    if (mounted) setState(() => _pending.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(kokpitMonthProvider);
    final today = AppDates.startOfDay(ref.watch(kokpitClockProvider));
    final currentMonth = DateTime(today.year, today.month);
    final selected = ref.watch(kokpitSelectedDayProvider);
    final overview = ref.watch(monthOverviewProvider(month));
    final readOnly = month.isBefore(currentMonth);

    List<RoutineOccurrence> effective(List<RoutineOccurrence> monthly) => [
          for (final occurrence in monthly)
            if (_pending[occurrence.completionKey] case final target?)
              withCompletion(occurrence, target, today)
            else
              occurrence,
        ];

    final data = overview.valueOrNull;
    final monthly = data == null ? null : effective(data.monthly);
    final marks = data == null
        ? null
        : dayMarksFor(month, monthly!, data.tasks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthSwitcher(
          month: month,
          isCurrent: month == currentMonth,
          onPrevious: () => _showMonth(DateTime(month.year, month.month - 1)),
          onNext: () => _showMonth(DateTime(month.year, month.month + 1)),
          onToday: () => _showMonth(currentMonth, select: today),
        ),
        const SizedBox(height: 8),
        _CalendarCard(
          month: month,
          today: today,
          selected: selected,
          marks: marks,
          onSelect: _selectDay,
        ),
        const SizedBox(height: 24),
        overview.when(
          skipLoadingOnRefresh: true,
          loading: () => const KokpitSkeletonCard(height: 220),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Ay verisi yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(monthOverviewProvider(month)),
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MonthlySection(
                monthly: effective(value.monthly),
                readOnly: readOnly,
                onToggle: _toggle,
              ),
              const SizedBox(height: 24),
              _MonthTasksSection(
                tasks: value.tasks,
                done: value.tasksDone,
                readOnly: readOnly,
              ),
              const SizedBox(height: 24),
              _SummarySection(overview: value),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ay değiştirici

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Oklar iki uçta sabit durur: art arda dokunurken ay adının uzunluğu ya da
    // "Bugün" kısayolu okların yerini değiştirmez.
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: 'Önceki ay',
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  KokpitFormat.monthTitle(month),
                  key: const ValueKey('kokpit-month-title'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (!isCurrent)
                TextButton(
                  onPressed: onToday,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Bugün'),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: 'Sonraki ay',
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- takvim

const List<String> _weekdayLabels = [
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.today,
    required this.selected,
    required this.marks,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selected;

  /// Ay verisi gelene kadar `null`: ızgara noktasız çizilir.
  final Map<int, DayMarks>? marks;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = monthGrid(month.year, month.month);
    // Hücre yüksekliği yazı boyutuyla büyür; rakam ve noktalar hep sığar.
    final cellHeight = MediaQuery.textScalerOf(context).scale(14) + 28;
    final selectedDay = selected;
    final marks = this.marks;

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (weekIndex, week) in weeks.indexed)
            Row(
              children: [
                for (final (column, day) in week.indexed)
                  Expanded(
                    child: day == null
                        ? SizedBox(
                            key: ValueKey('kokpit-blank-$weekIndex-$column'),
                            height: cellHeight,
                          )
                        : _DayCell(
                            key: ValueKey('kokpit-day-${AppDates.ymd(day)}'),
                            day: day,
                            height: cellHeight,
                            isToday: day == today,
                            isSelected: day == selectedDay,
                            marks: marks?[day.day] ?? DayMarks.empty,
                            onTap: () => onSelect(day),
                          ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const _CalendarLegend(),
          if (selectedDay != null &&
              selectedDay.year == month.year &&
              selectedDay.month == month.month) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(),
            ),
            _SelectedDayPanel(
              day: selectedDay,
              marks: marks == null
                  ? null
                  : marks[selectedDay.day] ?? DayMarks.empty,
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color, this.faded = false});

  final Color color;

  /// O günün kayıtlarının hepsi kapandıysa nokta soluklaşır.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: faded ? color.withValues(alpha: 0.35) : color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.height,
    required this.isToday,
    required this.isSelected,
    required this.marks,
    required this.onTap,
  });

  final DateTime day;
  final double height;
  final bool isToday;
  final bool isSelected;
  final DayMarks marks;
  final VoidCallback onTap;

  String get _semanticsLabel => [
        AppDates.longDay(day),
        if (isToday) 'bugün',
        if (marks.hasMonthly) '${marks.monthly.length} aylık iş',
        if (marks.hasTasks) '${marks.tasks.length} görev',
      ].join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppRadii.chip);
    final isWeekend = day.weekday >= DateTime.saturday;
    final numberColor = isToday
        ? AppColors.accent
        : isWeekend
            ? AppColors.textSecondary
            : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: _semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: height - 4,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.surfaceHigh
                    : isToday
                        ? AppColors.accent.withValues(alpha: 0.10)
                        : Colors.transparent,
                borderRadius: radius,
                border: Border.all(
                  color: isToday
                      ? AppColors.accent
                      : isSelected
                          ? AppColors.textSecondary
                          : Colors.transparent,
                  width: 1.4,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.1,
                      color: numberColor,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Noktasız günlerde de aynı yükseklik: rakamlar hizalı kalır.
                  SizedBox(
                    height: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (marks.hasMonthly)
                          _Dot(
                            key: ValueKey('kokpit-dot-monthly-${day.day}'),
                            color: AppColors.warning,
                            faded: marks.monthlyAllDone,
                          ),
                        if (marks.hasMonthly && marks.hasTasks)
                          const SizedBox(width: 3),
                        if (marks.hasTasks)
                          _Dot(
                            key: ValueKey('kokpit-dot-task-${day.day}'),
                            color: AppColors.ops,
                            faded: marks.tasksAllDone,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: AppColors.textMuted);

    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: color),
            const SizedBox(width: 6),
            Text(label, style: style),
          ],
        );

    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          item(AppColors.warning, 'Aylık iş'),
          item(AppColors.ops, 'Randevu / görev'),
        ],
      ),
    );
  }
}

/// Takvimde seçilen günün kayıtları.
class _SelectedDayPanel extends StatelessWidget {
  const _SelectedDayPanel({required this.day, required this.marks});

  final DateTime day;

  /// Ay verisi henüz yoksa `null`: yalnızca tarih başlığı çizilir.
  final DayMarks? marks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = this.marks;
    return Padding(
      key: const ValueKey('kokpit-selected-day'),
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppDates.longDay(day), style: theme.textTheme.titleSmall),
          if (marks != null) const SizedBox(height: 8),
          if (marks != null && marks.isEmpty)
            Text(
              'Bu gün için kayıt yok.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            )
          else if (marks != null) ...[
            for (final occurrence in marks.monthly)
              _DayLine(
                color: AppColors.warning,
                title: occurrence.routine.title,
                struck: occurrence.completed,
                trailing: KokpitStatusChip(status: occurrence.status),
              ),
            for (final task in marks.tasks)
              _DayLine(
                color: AppColors.ops,
                title: task.title,
                struck: task.isDone,
                trailing: Text(
                  AppDates.hourMinute(task.scheduledAt!),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DayLine extends StatelessWidget {
  const _DayLine({
    required this.color,
    required this.title,
    required this.struck,
    required this.trailing,
  });

  final Color color;
  final String title;
  final bool struck;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _Dot(color: color, faded: struck),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        struck ? AppColors.textMuted : AppColors.textPrimary,
                    decoration: struck ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- aylık sabitler

class _MonthlySection extends StatelessWidget {
  const _MonthlySection({
    required this.monthly,
    required this.readOnly,
    required this.onToggle,
  });

  final List<RoutineOccurrence> monthly;

  /// Geçmiş ay kapanmıştır: işaret değiştirilemez.
  final bool readOnly;
  final ValueChanged<RoutineOccurrence> onToggle;

  @override
  Widget build(BuildContext context) {
    final done = monthly.where((o) => o.completed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KokpitSectionHeader(
          title: 'Aylık sabitler',
          trailing: monthly.isEmpty ? null : '$done / ${monthly.length}',
        ),
        if (monthly.isEmpty)
          const KokpitInlineMessage(
            icon: Icons.event_repeat_rounded,
            message: 'Bu ay için aylık sabit yok.',
          )
        else
          BentoCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (index, occurrence) in monthly.indexed) ...[
                  if (index > 0) const Divider(indent: 56, endIndent: 16),
                  _MonthlyTile(
                    key: ValueKey(occurrence.completionKey),
                    occurrence: occurrence,
                    onTap: readOnly ? null : () => onToggle(occurrence),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthlyTile extends StatelessWidget {
  const _MonthlyTile({super.key, required this.occurrence, this.onTap});

  final RoutineOccurrence occurrence;

  /// `null` ise satır salt okunurdur.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routine = occurrence.routine;
    final done = occurrence.completed;
    final status = KokpitFormat.statusLabel(occurrence.status);

    return Semantics(
      checked: done,
      button: onTap != null,
      enabled: onTap != null,
      label: '${routine.title}, $status',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              KokpitCheckBox(
                checked: done,
                color: AppColors.forRoutineCategory(routine.category),
                enabled: onTap != null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color:
                            done ? AppColors.textMuted : AppColors.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        KokpitFormat.dayMonth(occurrence.dueDate),
                        if (routine.timeLabel != null) routine.timeLabel!,
                        routine.scope,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              KokpitStatusChip(status: occurrence.status),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- ayın randevuları

class _MonthTasksSection extends StatelessWidget {
  const _MonthTasksSection({
    required this.tasks,
    required this.done,
    required this.readOnly,
  });

  final List<TaskItem> tasks;
  final int done;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KokpitSectionHeader(
          title: 'Bu ayın randevuları',
          trailing: tasks.isEmpty ? null : '$done / ${tasks.length}',
        ),
        if (tasks.isEmpty)
          const KokpitInlineMessage(
            icon: Icons.event_busy_rounded,
            message: 'Bu ay için randevu ya da görev yok.',
          )
        else
          BentoCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (index, task) in tasks.indexed) ...[
                  if (index > 0) const Divider(indent: 16, endIndent: 16),
                  _MonthTaskTile(
                    key: ValueKey('kokpit-month-task-${task.id}'),
                    task: task,
                    onComplete: readOnly || task.isDone
                        ? null
                        : () => completeKokpitTask(context, task),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthTaskTile extends StatelessWidget {
  const _MonthTaskTile({super.key, required this.task, this.onComplete});

  final TaskItem task;

  /// `null` ise görev tamamlanmıştır ya da ay salt okunurdur.
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = task.scheduledAt!;
    final done = task.isDone;
    final color = done
        ? AppColors.textMuted
        : AppColors.forTaskCategory(task.category);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          // Tarih bloğu: gün rakamı + kısa gün adı.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${at.day}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  KokpitFormat.weekdayShort(at),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: done ? AppColors.textMuted : AppColors.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    AppDates.hourMinute(at),
                    task.category,
                    if (task.assignee != null) task.assignee!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (done)
            const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.check_circle_rounded,
                color: AppColors.accent,
                semanticLabel: 'Tamamlandı',
              ),
            )
          else if (onComplete != null)
            IconButton(
              onPressed: onComplete,
              tooltip: 'Tamamlandı olarak işaretle',
              icon: const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.textSecondary),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ay özeti

class _SummarySection extends ConsumerWidget {
  const _SummarySection({required this.overview});

  final MonthOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(settingsOrDefaultProvider);
    final health = overview.health;
    final thousands = KokpitFormat.thousands;

    final routinePercent =
        completionPercent(overview.weeklyDone, overview.weeklyPlanned);
    final taskCount = overview.tasks.length;
    final taskPercent = completionPercent(overview.tasksDone, taskCount);
    final avgCalories = health.avgCalories;
    final weightChange = health.weightChangeKg;
    final hasHealth = health.avgSteps != null ||
        health.avgSleepMinutes != null ||
        avgCalories != null ||
        weightChange != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KokpitSectionHeader(title: 'Ay özeti'),
        BentoGrid(
          children: [
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.repeat_rounded,
                color: AppColors.accent,
                label: 'Rutinler',
                value: routinePercent == null
                    ? KokpitFormat.none
                    : KokpitFormat.percent(routinePercent),
                caption: routinePercent == null
                    ? 'Planlanan rutin yok'
                    : '${overview.weeklyDone} / ${overview.weeklyPlanned} tamamlandı',
              ),
            ),
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.task_alt_rounded,
                color: AppColors.ops,
                label: 'Görevler',
                value: taskPercent == null
                    ? KokpitFormat.none
                    : KokpitFormat.percent(taskPercent),
                caption: taskPercent == null
                    ? 'Görev yok'
                    : '${overview.tasksDone} / $taskCount tamamlandı',
              ),
            ),
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.directions_walk_rounded,
                color: AppColors.fitness,
                label: 'Ort. adım',
                value: health.avgSteps == null
                    ? KokpitFormat.none
                    : thousands.format(health.avgSteps),
                caption: 'Hedef ${thousands.format(targets.dailySteps)}',
              ),
            ),
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.bedtime_rounded,
                color: AppColors.ops,
                label: 'Ort. uyku',
                value: KokpitFormat.sleep(health.avgSleepMinutes),
                caption: 'Hedef ${KokpitFormat.sleep(targets.sleepMinutes)}',
              ),
            ),
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.nutrition,
                label: 'Ort. kalori',
                value: avgCalories == null
                    ? KokpitFormat.none
                    : '${thousands.format(avgCalories.round())} kcal',
                caption:
                    'Hedef ${thousands.format(targets.dailyCalories)} kcal',
              ),
            ),
            BentoCell(
              span: 1,
              child: _StatCard(
                icon: Icons.monitor_weight_outlined,
                color: AppColors.warning,
                label: 'Kilo değişimi',
                value: weightChange == null
                    ? KokpitFormat.none
                    : KokpitFormat.weightChange(weightChange),
                caption: weightChange == null
                    ? 'Ölçüm yok'
                    : '${KokpitFormat.kg(health.weightStartKg!)} → '
                        '${KokpitFormat.kg(health.weightEndKg!)} kg',
              ),
            ),
          ],
        ),
        if (!hasHealth)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Bu ay için sağlık ve beslenme verisi yok.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: BentoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BentoLabel(icon: icon, label: label, color: color),
            const SizedBox(height: 10),
            // Yarım genişlikte uzun değer satır kırmak yerine küçülür.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                caption,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
