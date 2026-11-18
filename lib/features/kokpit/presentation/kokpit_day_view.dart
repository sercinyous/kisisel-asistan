import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/water_card.dart';
import '../../operations/domain/task_item.dart';
import '../../reports/presentation/weekly_checkin_card.dart';
import '../../operations/presentation/routines_view.dart'
    show RoutineRowActions;
import '../../operations/presentation/tasks_view.dart' show TaskRowActions;
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/kokpit_models.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Gün görünümü: makro özeti, adım/uyku, bugünün rutinleri, penceresi açılmış
/// aylık işler ve tek seferlik görev/randevular.
class KokpitDayView extends StatelessWidget {
  const KokpitDayView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayBento(),
        SizedBox(height: 24),
        _RoutinesSection(),
        _MonthlyDueSection(),
        SizedBox(height: 24),
        _RemindersSection(),
        SizedBox(height: AppSpacing.grid),
        WaterSummaryCard(),
        SizedBox(height: AppSpacing.grid),
        WeeklyCheckinCard(bottomSpacing: 0),
      ],
    );
  }
}

/// İyimser işaretleme; hata olursa notifier geri alır, burada yalnızca
/// kullanıcı bilgilendirilir.
Future<void> _toggleOccurrence(
  BuildContext context,
  WidgetRef ref,
  RoutineOccurrence occurrence, {
  required String errorMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(todayOccurrencesProvider.notifier);
  unawaited(HapticFeedback.selectionClick());
  try {
    await notifier.toggle(occurrence);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
  }
}

// ------------------------------------------------------- beslenme + sağlık

class _TodayBento extends ConsumerWidget {
  const _TodayBento();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrition = ref.watch(todayNutritionProvider);
    final health = ref.watch(healthTodayProvider);
    final source = ref.watch(healthSourceProvider);

    return BentoGrid(
      children: [
        BentoCell(
          child: nutrition.when(
            skipLoadingOnRefresh: true,
            loading: () => const KokpitSkeletonCard(height: 172),
            error: (_, __) => KokpitInlineMessage(
              icon: Icons.cloud_off_rounded,
              message: 'Beslenme özeti yüklenemedi.',
              actionLabel: 'Tekrar dene',
              onAction: () => ref.invalidate(todayNutritionProvider),
            ),
            data: (summary) => _NutritionCard(summary: summary),
          ),
        ),
        ...health.when(
          skipLoadingOnRefresh: true,
          loading: () => const [
            BentoCell(child: KokpitSkeletonCard(height: 118)),
          ],
          error: (_, __) => [
            BentoCell(
              child: KokpitInlineMessage(
                icon: Icons.heart_broken_rounded,
                message: '${source.shortLabel} verisi okunamadı.',
                actionLabel: 'Tekrar dene',
                onAction: () => resyncHealthKit(
                  ProviderScope.containerOf(context, listen: false),
                ),
              ),
            ),
          ],
          data: (snapshot) => switch (snapshot.status) {
            HealthStatus.unavailable => [
                BentoCell(
                  child: KokpitInlineMessage(
                    icon: Icons.phonelink_off_rounded,
                    message: snapshot.message ??
                        'Adım, uyku ve aktif kalori yalnızca iPhone\'da '
                            'HealthKit üzerinden okunur.',
                  ),
                ),
              ],
            HealthStatus.denied => [
                BentoCell(
                  child: KokpitInlineMessage(
                    icon: Icons.favorite_border_rounded,
                    message: 'HealthKit erişimi verilmedi. Sağlık uygulaması > '
                        'Paylaşım > Uygulamalar bölümünden izin verebilirsin.',
                    actionLabel: 'Bağlan',
                    onAction: () => resyncHealthKit(
                      ProviderScope.containerOf(context, listen: false),
                    ),
                  ),
                ),
              ],
            HealthStatus.notConnected || HealthStatus.reconnect => [
                BentoCell(
                  child: KokpitInlineMessage(
                    icon: snapshot.status == HealthStatus.reconnect
                        ? Icons.sync_problem_rounded
                        : Icons.link_off_rounded,
                    message: snapshot.message ?? 'Google Health bağlı değil.',
                    actionLabel: snapshot.status == HealthStatus.reconnect
                        ? 'Yeniden bağlan'
                        : 'Bağlan',
                    onAction: () => _connectGoogle(context),
                  ),
                ),
              ],
            HealthStatus.failed => [
                BentoCell(
                  child: KokpitInlineMessage(
                    icon: Icons.cloud_off_rounded,
                    message: snapshot.message ??
                        '${snapshot.source.shortLabel} verisi okunamadı.',
                    actionLabel: 'Tekrar dene',
                    onAction: () => resyncHealthKit(
                      ProviderScope.containerOf(context, listen: false),
                    ),
                  ),
                ),
              ],
            HealthStatus.ok => [
                BentoCell(span: 1, child: _StepsCard(snapshot: snapshot)),
                BentoCell(span: 1, child: _SleepCard(snapshot: snapshot)),
              ],
          },
        ),
      ],
    );
  }

  /// Google giriş penceresi; hata olursa alt çubukta gösterilir.
  static Future<void> _connectGoogle(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final error = await connectGoogleHealth(container);
    if (error == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }
}

class _NutritionCard extends ConsumerWidget {
  const _NutritionCard({required this.summary});

  final NutritionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targets = ref.watch(settingsOrDefaultProvider);
    final remaining = targets.dailyCalories - summary.calories;
    final over = remaining < 0;
    final thousands = KokpitFormat.thousands;

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  size: 18, color: AppColors.nutrition),
              const SizedBox(width: 6),
              Text('Kalori', style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                over
                    ? '${thousands.format(remaining.abs().round())} kcal fazla'
                    : '${thousands.format(remaining.round())} kcal kaldı',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: over ? AppColors.danger : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                thousands.format(summary.calories.round()),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/ ${thousands.format(targets.dailyCalories)} kcal',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          KokpitBar(
            value: summary.calories / targets.dailyCalories,
            color: over ? AppColors.danger : AppColors.nutrition,
            height: 10,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MacroStat(
                  label: 'Protein',
                  value: summary.proteinG,
                  target: targets.dailyProteinG,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MacroStat(
                  label: 'Karbonhidrat',
                  value: summary.carbsG,
                  target: targets.dailyCarbsG,
                  color: AppColors.ops,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MacroStat(
                  label: 'Yağ',
                  value: summary.fatG,
                  target: targets.dailyFatG,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroStat extends StatelessWidget {
  const _MacroStat({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double value;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${value.round()}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: ' / $target g',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        // Hedef 0 ise (ör. yağ hedefi girilmemiş) çubuk boş kalır.
        KokpitBar(
          value: target > 0 ? value / target : 0,
          color: color,
          height: 6,
        ),
      ],
    );
  }
}

/// Yarım genişlikteki kartta büyük değer dar ekranda ya da büyük yazı
/// boyutunda sığmayabilir; satır kırmak yerine küçültülür.
class _FitLeft extends StatelessWidget {
  const _FitLeft({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _StepsCard extends ConsumerWidget {
  const _StepsCard({required this.snapshot});

  final HealthSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stepTarget = ref.watch(
      settingsOrDefaultProvider.select((s) => s.dailySteps),
    );
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.directions_walk_rounded,
            label: 'Adım',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 8),
          _FitLeft(
            child: Text(
              KokpitFormat.thousands.format(snapshot.steps),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _FitLeft(
            child: Text(
              '/ ${KokpitFormat.thousands.format(stepTarget)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          KokpitBar(
            value: snapshot.steps / stepTarget,
            color: AppColors.fitness,
          ),
        ],
      ),
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.snapshot});

  final HealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readAt = snapshot.readAt;
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.bedtime_rounded,
            label: 'Uyku',
            color: AppColors.ops,
          ),
          const SizedBox(height: 8),
          _FitLeft(
            child: Text(
              KokpitFormat.sleep(snapshot.sleepMinutes),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _FitLeft(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${KokpitFormat.thousands.format(snapshot.activeKcal)} kcal',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _FitLeft(
            child: Text(
              readAt == null
                  ? snapshot.source.shortLabel
                  : '${snapshot.source.shortLabel} · '
                      '${AppDates.hourMinute(readAt)}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- rutinler

class _RoutinesSection extends ConsumerWidget {
  const _RoutinesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(todayOccurrencesProvider);
    // Bu bölüm yalnızca günlük/haftalık rutinleri gösterir.
    final list = routines.valueOrNull?.daily;
    final done = list?.where((r) => r.completed).length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KokpitSectionHeader(
          title: 'Bugünün rutinleri',
          trailing:
              list == null || list.isEmpty ? null : '$done / ${list.length}',
        ),
        if (list != null && list.isNotEmpty) ...[
          KokpitBar(
            value: done / list.length,
            color: AppColors.accent,
            height: 6,
          ),
          const SizedBox(height: 12),
        ],
        routines.when(
          skipLoadingOnRefresh: true,
          loading: () => const KokpitSkeletonCard(height: 220),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Rutinler yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(todayOccurrencesProvider),
          ),
          data: (today) => today.daily.isEmpty
              ? const KokpitInlineMessage(
                  icon: Icons.event_available_rounded,
                  message: 'Bugün için tanımlı rutin yok.',
                )
              : BentoCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final (index, occurrence)
                          in today.daily.indexed) ...[
                        if (index > 0) const Divider(indent: 56, endIndent: 16),
                        RoutineRowActions(
                          key: ValueKey(occurrence.completionKey),
                          routine: occurrence.routine,
                          child: _RoutineTile(
                            occurrence: occurrence,
                            onTap: () => _toggleOccurrence(
                              context,
                              ref,
                              occurrence,
                              errorMessage:
                                  'Rutin güncellenemedi. Tekrar dene.',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({required this.occurrence, required this.onTap});

  final RoutineOccurrence occurrence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routine = occurrence.routine;
    final color = AppColors.forRoutineCategory(routine.category);
    final done = occurrence.completed;

    return Semantics(
      checked: done,
      button: true,
      label: routine.title,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              KokpitCheckBox(checked: done, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  routine.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: done ? AppColors.textMuted : AppColors.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
                ),
              ),
              if (routine.timeLabel != null) ...[
                const SizedBox(width: 10),
                Text(
                  routine.timeLabel!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: done ? AppColors.textMuted : color,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- aylık işler

/// Penceresi açılmış ya da gecikmiş aylık işler. Liste boşsa bölüm hiç
/// çizilmez; yükleme ve hata durumunu "Bugünün rutinleri" zaten gösterir.
class _MonthlyDueSection extends ConsumerWidget {
  const _MonthlyDueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthly = ref.watch(
      todayOccurrencesProvider.select((value) => value.valueOrNull?.monthly),
    );
    if (monthly == null || monthly.isEmpty) return const SizedBox.shrink();
    final today = AppDates.startOfDay(ref.watch(kokpitClockProvider));
    final open = monthly.where((o) => !o.completed).length;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KokpitSectionHeader(
            title: 'Yaklaşan aylık işler',
            trailing: open == 0 ? null : '$open açık',
          ),
          BentoCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (index, occurrence) in monthly.indexed) ...[
                  if (index > 0) const Divider(indent: 56, endIndent: 16),
                  RoutineRowActions(
                    // Aynı rutin iki dönemle (bu ay gecikmiş + gelecek ay
                    // yaklaşıyor) listede olabilir; liste kayınca durum
                    // yanlış satıra geçmesin diye kimlik dönemi de içerir.
                    key: ValueKey(occurrence.completionKey),
                    routine: occurrence.routine,
                    child: _MonthlyDueTile(
                      occurrence: occurrence,
                      today: today,
                      onTap: () => _toggleOccurrence(
                        context,
                        ref,
                        occurrence,
                        errorMessage: 'Aylık iş güncellenemedi. Tekrar dene.',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyDueTile extends StatelessWidget {
  const _MonthlyDueTile({
    required this.occurrence,
    required this.today,
    required this.onTap,
  });

  final RoutineOccurrence occurrence;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routine = occurrence.routine;
    final done = occurrence.completed;
    final countdown = KokpitFormat.countdown(occurrence, today);

    return Semantics(
      checked: done,
      button: true,
      label: '${routine.title}, $countdown',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              KokpitCheckBox(
                checked: done,
                color: AppColors.forRoutineCategory(routine.category),
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
              Text(
                countdown,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: KokpitFormat.statusColor(occurrence.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------ görev ve randevular

class _RemindersSection extends ConsumerWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(upcomingRemindersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KokpitSectionHeader(title: 'Bugün ve yaklaşanlar'),
        reminders.when(
          skipLoadingOnRefresh: true,
          loading: () => const KokpitSkeletonCard(height: 150),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Hatırlatmalar yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(upcomingRemindersProvider),
          ),
          data: (tasks) => tasks.isEmpty
              ? const KokpitInlineMessage(
                  icon: Icons.notifications_none_rounded,
                  message: 'Yaklaşan hatırlatma yok. Ortadaki + ile '
                      'tek cümleyle ekleyebilirsin.',
                )
              : Column(
                  children: [
                    for (final (index, task) in tasks.indexed) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.grid),
                      TaskRowActions(
                        key: ValueKey('kokpit-reminder-${task.id}'),
                        task: task,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        child: _ReminderTile(
                          task: task,
                          onComplete: () => completeKokpitTask(context, task),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.task, required this.onComplete});

  final TaskItem task;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppColors.forTaskCategory(task.category);
    final time = task.nextTime(DateTime.now());

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
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
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (time != null) AppDates.relativeDayTime(time),
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
          if (task.priority == 'high')
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.priority_high_rounded,
                  size: 18, color: AppColors.danger),
            ),
          IconButton(
            onPressed: onComplete,
            tooltip: 'Tamamlandı olarak işaretle',
            icon: Icon(Icons.check_circle_outline_rounded,
                color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
