import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/health_segment.dart';
import '../../health/presentation/water_providers.dart';
import '../../operations/domain/task_item.dart';
import '../../operations/presentation/operations_providers.dart';
import '../../operations/presentation/routines_view.dart'
    show RoutineRowActions;
import '../../operations/presentation/tasks_view.dart' show TaskRowActions;
import '../../reports/presentation/weekly_checkin_card.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/kokpit_models.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Alt bardaki sekme sırası (bkz. `HomeShell`).
const int _operationsTab = 1;
const int _healthTab = 2;

/// "Bugünün işleri" kartında gösterilen en fazla satır.
const int kokpitTodayMaxRows = 5;

/// Bugün: kalori, günlük işler / adım / uyku, su, bugünün rutinleri ve
/// (Pazar/Pazartesi) haftalık değerlendirme.
class KokpitDayView extends StatelessWidget {
  const KokpitDayView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CalorieSection(),
        SizedBox(height: AppSpacing.m),
        _StatsRow(),
        _HealthStatusMessage(),
        SizedBox(height: AppSpacing.m),
        _WaterCard(),
        SizedBox(height: AppSpacing.xl),
        _TodaySection(),
        SizedBox(height: AppSpacing.l),
        WeeklyCheckinCard(bottomSpacing: 0),
      ],
    );
  }
}

// -------------------------------------------------------------- bugünün işleri

/// Bugünün listesindeki tek satır: rutin ya da bugüne düşen görev.
sealed class KokpitTodayItem {
  const KokpitTodayItem();

  /// Bugünkü saat; saatsiz kayıtta `null`.
  DateTime? get time;
  bool get done;
}

class KokpitRoutineItem extends KokpitTodayItem {
  const KokpitRoutineItem(this.occurrence, this.day);

  final RoutineOccurrence occurrence;
  final DateTime day;

  @override
  DateTime? get time {
    final r = occurrence.routine;
    if (!r.hasTime) return null;
    return DateTime(day.year, day.month, day.day, r.hour!, r.minute!);
  }

  @override
  bool get done => occurrence.completed;
}

class KokpitTaskItem extends KokpitTodayItem {
  const KokpitTaskItem(this.task, this.now);

  final TaskItem task;
  final DateTime now;

  @override
  DateTime? get time => task.scheduledAt ?? task.nextTime(now);

  @override
  bool get done => task.isDone;
}

/// Bugünün rutinleri + bugüne (ya da öncesine) düşen açık görevler.
/// Sıra: saati geçmiş açık kayıtlar önce, sonra saate göre; saatsizler sonda.
List<KokpitTodayItem> kokpitTodayItems({
  required List<RoutineOccurrence> routines,
  required List<TaskItem> tasks,
  required DateTime now,
}) {
  final day = AppDates.startOfDay(now);
  final tomorrow = day.add(const Duration(days: 1));
  final items = <KokpitTodayItem>[
    for (final o in routines) KokpitRoutineItem(o, day),
    for (final t in tasks)
      if (!t.isDone)
        if (KokpitTaskItem(t, now).time case final time?
            when time.isBefore(tomorrow))
          KokpitTaskItem(t, now),
  ];
  bool overdue(KokpitTodayItem i) {
    final t = i.time;
    return !i.done && t != null && t.isBefore(now);
  }

  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final ao = overdue(a.$2), bo = overdue(b.$2);
      if (ao != bo) return ao ? -1 : 1;
      final at = a.$2.time, bt = b.$2.time;
      if (at != null && bt != null) {
        final c = at.compareTo(bt);
        if (c != 0) return c;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Kokpit kartlarının paylaştığı bugünün listesi; ikisi de yüklenene kadar
/// `null`.
List<KokpitTodayItem>? _watchTodayItems(WidgetRef ref) {
  final routines = ref.watch(todayOccurrencesProvider).valueOrNull?.daily;
  final tasks = ref.watch(upcomingRemindersProvider).valueOrNull;
  final now = ref.watch(kokpitClockProvider);
  if (routines == null || tasks == null) return null;
  return kokpitTodayItems(routines: routines, tasks: tasks, now: now);
}

/// İyimser işaretleme; hata olursa notifier geri alır, burada yalnızca
/// kullanıcı bilgilendirilir.
Future<void> _toggleOccurrence(
  BuildContext context,
  WidgetRef ref,
  RoutineOccurrence occurrence,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(todayOccurrencesProvider.notifier);
  unawaited(HapticFeedback.selectionClick());
  try {
    await notifier.toggle(occurrence);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Rutin güncellenemedi. Tekrar dene.')),
    );
  }
}

void _openTab(WidgetRef ref, int index) =>
    ref.read(homeTabRequestProvider.notifier).state = index;

/// Sağlık sekmesini [segment] görünümüyle açar.
void _openHealth(WidgetRef ref, HealthSegment segment) {
  ref.read(healthSegmentProvider.notifier).state = segment;
  _openTab(ref, _healthTab);
}

/// İşler sekmesini açar: gizli satırların çoğu görevse Görevler, değilse
/// Rutinler görünümüyle. Filtreler sıfırlanır ki hiçbir kayıt gizlenmesin.
void _openTodayAll(WidgetRef ref, {required bool tasksFirst}) {
  ref.read(taskCategoryFilterProvider.notifier).state = null;
  ref.read(routineScopeFilterProvider.notifier).state = null;
  ref.read(opsSegmentProvider.notifier).state =
      tasksFirst ? OpsSegment.tasks : OpsSegment.routines;
  _openTab(ref, _operationsTab);
}

// --------------------------------------------------------------------- kalori

class _CalorieSection extends ConsumerWidget {
  const _CalorieSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrition = ref.watch(todayNutritionProvider);
    return nutrition.when(
      skipLoadingOnRefresh: true,
      loading: () => const KokpitSkeletonCard(height: 132),
      error: (_, __) => KokpitInlineMessage(
        icon: Icons.cloud_off_rounded,
        message: 'Beslenme özeti yüklenemedi.',
        actionLabel: 'Tekrar dene',
        onAction: () => ref.invalidate(todayNutritionProvider),
      ),
      data: (summary) => _CalorieCard(summary: summary),
    );
  }
}

class _CalorieCard extends ConsumerWidget {
  const _CalorieCard({required this.summary});

  final NutritionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = ref.watch(
      settingsOrDefaultProvider.select((s) => s.dailyCalories),
    );
    final remaining = target - summary.calories;
    final over = remaining < 0;
    final thousands = KokpitFormat.thousands;

    return BentoCard(
      onTap: () => _openHealth(ref, HealthSegment.nutrition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.local_fire_department_rounded,
            label: 'Kalori',
            color: AppColors.nutrition,
          ),
          const SizedBox(height: AppSpacing.s),
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
              Flexible(
                child: Text(
                  '/ ${thousands.format(target)} kcal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          KokpitBar(
            value: target > 0 ? summary.calories / target : 0,
            color: over ? AppColors.danger : AppColors.nutrition,
            height: 8,
          ),
          const SizedBox(height: AppSpacing.s),
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
    );
  }
}

// ------------------------------------------------------------- üçlü istatistik

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _watchTodayItems(ref);
    final health = ref.watch(healthTodayProvider).valueOrNull;
    final ok = health?.status == HealthStatus.ok;
    final settings = ref.watch(settingsOrDefaultProvider);
    final thousands = KokpitFormat.thousands;

    final done = items?.where((i) => i.done).length ?? 0;
    final total = items?.length ?? 0;
    final left = total - done;
    final steps = ok ? health!.steps : null;
    final sleep = ok ? health!.sleepMinutes : null;
    final sleepTarget = settings.sleepMinutes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.checklist_rounded,
              label: 'Günlük işler',
              color: AppColors.ops,
              value: items == null ? '—' : '$done / $total',
              caption: items == null
                  ? ''
                  : left == 0
                      ? 'hepsi bitti'
                      : '$left iş kaldı',
              progress: total == 0 ? null : done / total,
              onTap: () => _openTab(ref, _operationsTab),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _StatCard(
              icon: Icons.directions_walk_rounded,
              label: 'Adım',
              color: AppColors.fitness,
              value: steps == null ? '—' : thousands.format(steps),
              caption: 'hedef ${thousands.format(settings.dailySteps)}',
              progress: steps == null || settings.dailySteps <= 0
                  ? null
                  : steps / settings.dailySteps,
              onTap: () => _openHealth(ref, HealthSegment.movement),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _StatCard(
              icon: Icons.bedtime_rounded,
              label: 'Uyku',
              color: AppColors.sleep,
              value: KokpitFormat.sleep(sleep),
              caption: sleepTarget > 0
                  ? 'hedef ${KokpitFormat.hours(sleepTarget)} sa'
                  : '',
              progress: sleep == null || sleepTarget <= 0
                  ? null
                  : sleep / sleepTarget,
              onTap: () => _openHealth(ref, HealthSegment.movement),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.caption,
    required this.progress,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String value;
  final String caption;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Semantics(
        label: '$label: $value${caption.isEmpty ? '' : ', $caption'}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.s),
              KokpitBar(value: progress!, color: color, height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sağlık kaynağı okunamıyorsa adım/uyku kartlarının altında açıklama.
class _HealthStatusMessage extends ConsumerWidget {
  const _HealthStatusMessage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthTodayProvider);
    final source = ref.watch(healthSourceProvider);
    void resync() =>
        resyncHealthKit(ProviderScope.containerOf(context, listen: false));

    final Widget? message = health.when(
      skipLoadingOnRefresh: true,
      loading: () => null,
      error: (_, __) => KokpitInlineMessage(
        icon: Icons.heart_broken_rounded,
        message: '${source.shortLabel} verisi okunamadı.',
        actionLabel: 'Tekrar dene',
        onAction: resync,
      ),
      data: (snapshot) => switch (snapshot.status) {
        HealthStatus.ok => null,
        HealthStatus.unavailable => KokpitInlineMessage(
            icon: Icons.phonelink_off_rounded,
            message: snapshot.message ??
                'Adım, uyku ve aktif kalori yalnızca iPhone\'da '
                    'HealthKit üzerinden okunur.',
          ),
        HealthStatus.denied => KokpitInlineMessage(
            icon: Icons.favorite_border_rounded,
            message: 'HealthKit erişimi verilmedi. Sağlık uygulaması > '
                'Paylaşım > Uygulamalar bölümünden izin verebilirsin.',
            actionLabel: 'Bağlan',
            onAction: resync,
          ),
        HealthStatus.notConnected ||
        HealthStatus.reconnect =>
          KokpitInlineMessage(
            icon: snapshot.status == HealthStatus.reconnect
                ? Icons.sync_problem_rounded
                : Icons.link_off_rounded,
            message: snapshot.message ?? 'Google Health bağlı değil.',
            actionLabel: snapshot.status == HealthStatus.reconnect
                ? 'Yeniden bağlan'
                : 'Bağlan',
            onAction: () => _connectGoogle(context),
          ),
        HealthStatus.failed => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: snapshot.message ??
                '${snapshot.source.shortLabel} verisi okunamadı.',
            actionLabel: 'Tekrar dene',
            onAction: resync,
          ),
      },
    );
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.m),
      child: message,
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

// ------------------------------------------------------------------------- su

/// "0,25" — litre, en fazla iki ondalık, birimsiz.
String _liters(int ml) {
  final liters = ml / 1000;
  if (liters == liters.roundToDouble()) return liters.toStringAsFixed(0);
  return liters
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0$'), '')
      .replaceAll('.', ',');
}

class _WaterCard extends ConsumerWidget {
  const _WaterCard();

  static const int _stepMl = 250;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String error,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(HapticFeedback.selectionClick());
    try {
      await action();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final water = ref.watch(waterTodayProvider);
    final theme = Theme.of(context);
    final today = water.valueOrNull;
    final notifier = ref.read(waterTodayProvider.notifier);

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BentoLabel(
                  icon: Icons.water_drop_rounded,
                  label: 'Su',
                  color: AppColors.water,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  today == null
                      ? (water.hasError ? 'Yüklenemedi' : '—')
                      : '${_liters(today.totalMl)} / '
                          '${_liters(today.targetMl)} L',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (today == null && water.hasError)
            TextButton(
              onPressed: () => ref.invalidate(waterTodayProvider),
              child: const Text('Tekrar dene'),
            )
          else ...[
            IconButton.outlined(
              tooltip: 'Son su kaydını geri al',
              onPressed: today == null || today.logs.isEmpty
                  ? null
                  : () => _run(
                        context,
                        notifier.undo,
                        'Su kaydı geri alınamadı.',
                      ),
              icon: const Icon(Icons.remove_rounded),
              color: AppColors.water,
              style: IconButton.styleFrom(
                side: BorderSide(color: AppColors.border),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            FilledButton.tonal(
              onPressed: today == null
                  ? null
                  : () => _run(
                        context,
                        () => notifier.add(_stepMl),
                        'Su kaydı eklenemedi.',
                      ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.water.withValues(alpha: 0.16),
                foregroundColor: AppColors.water,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              child: const Text('+ 250 ml'),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- bugünün listesi

class _TodaySection extends ConsumerWidget {
  const _TodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(todayOccurrencesProvider);
    final tasks = ref.watch(upcomingRemindersProvider);
    final items = _watchTodayItems(ref);
    final now = ref.watch(kokpitClockProvider);

    final Widget body;
    if (routines.hasError && routines.valueOrNull == null) {
      body = KokpitInlineMessage(
        icon: Icons.cloud_off_rounded,
        message: 'Rutinler yüklenemedi.',
        actionLabel: 'Tekrar dene',
        onAction: () => ref.invalidate(todayOccurrencesProvider),
      );
    } else if (tasks.hasError && tasks.valueOrNull == null) {
      body = KokpitInlineMessage(
        icon: Icons.cloud_off_rounded,
        message: 'Görevler yüklenemedi.',
        actionLabel: 'Tekrar dene',
        onAction: () => ref.invalidate(upcomingRemindersProvider),
      );
    } else if (items == null) {
      body = const KokpitSkeletonCard(height: 220);
    } else if (items.isEmpty) {
      body = const KokpitInlineMessage(
        icon: Icons.event_available_rounded,
        message: 'Bugün için rutin ya da görev yok. Ortadaki + ile '
            'tek cümleyle ekleyebilirsin.',
      );
    } else {
      // Açık kayıtlar önce: tamamlananlar ilk satırlarda açıkları gizlemesin.
      final ordered = [
        ...items.where((i) => !i.done),
        ...items.where((i) => i.done),
      ];
      final shown = ordered.take(kokpitTodayMaxRows).toList();
      final hidden = ordered.skip(shown.length);
      final hiddenTasks = hidden.whereType<KokpitTaskItem>().length;
      final tasksFirst = hiddenTasks * 2 > hidden.length;
      body = BentoCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, item) in shown.indexed) ...[
              if (index > 0) const Divider(indent: 56, endIndent: 16),
              switch (item) {
                KokpitRoutineItem(:final occurrence) => RoutineRowActions(
                    key: ValueKey(occurrence.completionKey),
                    routine: occurrence.routine,
                    child: _TodayTile(
                      title: occurrence.routine.title,
                      time: item.time,
                      now: now,
                      done: item.done,
                      color: AppColors.forRoutineCategory(
                        occurrence.routine.category,
                      ),
                      onTap: () => _toggleOccurrence(context, ref, occurrence),
                    ),
                  ),
                KokpitTaskItem(:final task) => TaskRowActions(
                    key: ValueKey('kokpit-task-${task.id}'),
                    task: task,
                    child: _TodayTile(
                      title: task.title,
                      time: item.time,
                      now: now,
                      done: false,
                      color: AppColors.forTaskCategory(task.category),
                      onTap: () => completeKokpitTask(context, task),
                    ),
                  ),
              },
            ],
            if (items.length > shown.length) ...[
              const Divider(height: 1),
              TextButton(
                key: const ValueKey('kokpit-today-all'),
                onPressed: () => _openTodayAll(ref, tasksFirst: tasksFirst),
                style: TextButton.styleFrom(foregroundColor: AppColors.ops),
                child: Text('Tümünü gör (${items.length})'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KokpitSectionHeader(title: 'Bugünün işleri'),
        body,
      ],
    );
  }
}

class _TodayTile extends StatelessWidget {
  const _TodayTile({
    required this.title,
    required this.time,
    required this.now,
    required this.done,
    required this.color,
    required this.onTap,
  });

  final String title;
  final DateTime? time;
  final DateTime now;
  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = time;
    final overdue = !done && t != null && t.isBefore(now);
    final timeText = t == null
        ? null
        : AppDates.startOfDay(t) == AppDates.startOfDay(now)
            ? AppDates.hourMinute(t)
            : AppDates.relativeDayTime(t);

    return Semantics(
      checked: done,
      button: true,
      label: title,
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
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: done ? AppColors.textMuted : AppColors.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
                ),
              ),
              if (timeText != null) ...[
                const SizedBox(width: 10),
                Text(
                  timeText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: done
                        ? AppColors.textMuted
                        : overdue
                            ? AppColors.danger
                            : AppColors.textSecondary,
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
