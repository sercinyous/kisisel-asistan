import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/presentation/routines_view.dart'
    show RoutineRowActions;
import '../../operations/presentation/tasks_view.dart' show TaskRowActions;
import '../../routines/presentation/routines_providers.dart';
import '../domain/month_calendar.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Ay takvimi ve seçilen günün görev ve aylık işleri (İşler › Takvim).
class KokpitMonthView extends ConsumerWidget {
  const KokpitMonthView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(kokpitMonthProvider);
    final today = AppDates.startOfDay(ref.watch(kokpitClockProvider));
    final currentMonth = DateTime(today.year, today.month);
    final selected = ref.watch(kokpitSelectedDayProvider);
    final overview = ref.watch(monthOverviewProvider(month));

    void showMonth(DateTime value, {DateTime? select}) {
      ref.read(kokpitMonthProvider.notifier).state =
          DateTime(value.year, value.month);
      ref.read(kokpitSelectedDayProvider.notifier).state = select;
    }

    void selectDay(DateTime day) {
      final selection = ref.read(kokpitSelectedDayProvider.notifier);
      // Seçili güne yeniden dokunmak seçimi kaldırır.
      selection.state = selection.state == day ? null : day;
    }

    final data = overview.valueOrNull;
    final marks =
        data == null ? null : dayMarksFor(month, data.monthly, data.tasks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthSwitcher(
          month: month,
          isCurrent: month == currentMonth,
          onPrevious: () => showMonth(DateTime(month.year, month.month - 1)),
          onNext: () => showMonth(DateTime(month.year, month.month + 1)),
          onToday: () => showMonth(currentMonth, select: today),
        ),
        const SizedBox(height: 8),
        if (overview.hasError && data == null) ...[
          KokpitInlineMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Ay verisi yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(monthOverviewProvider(month)),
          ),
          const SizedBox(height: 8),
        ],
        _CalendarCard(
          month: month,
          today: today,
          selected: selected,
          marks: marks,
          onSelect: selectDay,
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
          icon: const Icon(Icons.chevron_left_outlined),
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
              'Bu tarihte görev ya da aylık iş yok. Günlük rutinler Rutinler sekmesinde.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            )
          else if (marks != null) ...[
            for (final occurrence in marks.monthly)
              RoutineRowActions(
                key: ValueKey('kokpit-day-routine-${occurrence.routine.id}'),
                routine: occurrence.routine,
                child: _DayLine(
                  color: AppColors.warning,
                  title: occurrence.routine.title,
                  struck: occurrence.completed,
                  trailing: KokpitStatusChip(status: occurrence.status),
                ),
              ),
            for (final task in marks.tasks)
              TaskRowActions(
                key: ValueKey('kokpit-day-task-${task.id}'),
                task: task,
                child: _DayLine(
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
                    color: struck ? AppColors.textMuted : AppColors.textPrimary,
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
