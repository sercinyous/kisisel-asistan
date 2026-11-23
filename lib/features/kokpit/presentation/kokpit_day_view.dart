import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../health/presentation/body/checkin_flow.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/providers/body_providers.dart';
import '../../operations/domain/task_item.dart';
import '../../operations/presentation/operations_providers.dart';
import '../../operations/presentation/routines_view.dart'
    show RoutineRowActions;
import '../../operations/presentation/tasks_view.dart' show TaskRowActions;
import '../../reports/presentation/weekly_checkin_card.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import 'kokpit_health_card.dart';
import 'kokpit_providers.dart';
import 'kokpit_widgets.dart';

/// Alt bardaki sekme sırası (bkz. `HomeShell`).
const int _operationsTab = 1;

/// "Bugünün işleri" kartında gösterilen en fazla satır.
const int kokpitTodayMaxRows = 5;

/// Bugün: Sağlık kartı (kalan kalori, adım, seriler), günlük işler + su,
/// bugünün listesi (ölçü günü satırı dahil) ve (Pazar/Pazartesi) haftalık
/// değerlendirme.
class KokpitDayView extends StatelessWidget {
  const KokpitDayView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KokpitHealthCard(),
        _HealthStatusMessage(),
        SizedBox(height: AppSpacing.m),
        _StatsRow(),
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

/// Ölçü ve fotoğraf günü sistem satırı. Görev değildir; Kontrol akışını
/// açar. O gün ölçü ya da fotoğraf kaydedildiyse tamamlanmış görünür.
class KokpitCheckinItem extends KokpitTodayItem {
  const KokpitCheckinItem({required this.done});

  static const String title = 'Ölçü ve fotoğraf günü · ~3 dk';

  @override
  final bool done;

  @override
  DateTime? get time => null;
}

/// Bugünün rutinleri + bugüne (ya da öncesine) düşen açık görevler.
/// Sıra: saati geçmiş açık kayıtlar önce, sonra saate göre; saatsizler sonda.
/// [checkin] verilirse (bugün ölçü günü) en başa sistem satırı eklenir.
List<KokpitTodayItem> kokpitTodayItems({
  required List<RoutineOccurrence> routines,
  required List<TaskItem> tasks,
  required DateTime now,
  KokpitCheckinItem? checkin,
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
  return [
    if (checkin != null) checkin,
    for (final e in indexed) e.$2,
  ];
}

/// Kokpit kartlarının paylaştığı bugünün listesi; ikisi de yüklenene kadar
/// `null`.
List<KokpitTodayItem>? _watchTodayItems(WidgetRef ref) {
  final routines = ref.watch(todayOccurrencesProvider).valueOrNull?.daily;
  final tasks = ref.watch(upcomingRemindersProvider).valueOrNull;
  final now = ref.watch(kokpitClockProvider);
  if (routines == null || tasks == null) return null;
  // Ölçü günü satırı listeyi bekletmez: yüklenemezse yalnızca görünmez.
  final checkin = ref.watch(checkinTodayProvider).valueOrNull;
  return kokpitTodayItems(
    routines: routines,
    tasks: tasks,
    now: now,
    checkin: checkin != null && checkin.isCheckinDay
        ? KokpitCheckinItem(done: checkin.done)
        : null,
  );
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

/// İşler sekmesini açar: gizli satırların çoğu görevse Görevler, değilse
/// Rutinler görünümüyle. Filtreler sıfırlanır ki hiçbir kayıt gizlenmesin.
void _openTodayAll(WidgetRef ref, {required bool tasksFirst}) {
  ref.read(taskCategoryFilterProvider.notifier).state = null;
  ref.read(routineScopeFilterProvider.notifier).state = null;
  ref.read(opsSegmentProvider.notifier).state =
      tasksFirst ? OpsSegment.tasks : OpsSegment.routines;
  _openTab(ref, _operationsTab);
}

// ------------------------------------------------------------- işler + su

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        _watchTodayItems(ref)?.where((i) => i is! KokpitCheckinItem).toList();
    final done = items?.where((i) => i.done).length ?? 0;
    final total = items?.length ?? 0;
    final left = total - done;

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
          const Expanded(child: KokpitWaterTile()),
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
      final countable = items.where((i) => i is! KokpitCheckinItem).length;
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
                KokpitCheckinItem() => _TodayTile(
                    key: const ValueKey('kokpit-checkin'),
                    title: KokpitCheckinItem.title,
                    time: null,
                    now: now,
                    done: item.done,
                    color: AppColors.accent,
                    icon: Icons.straighten_rounded,
                    onTap: () => CheckinFlowScreen.open(context),
                  ),
              },
            ],
            if (items.length > shown.length) ...[
              const Divider(height: 1),
              TextButton(
                key: const ValueKey('kokpit-today-all'),
                onPressed: () => _openTodayAll(ref, tasksFirst: tasksFirst),
                style: TextButton.styleFrom(foregroundColor: AppColors.ops),
                child: Text('Tümünü gör ($countable)'),
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
    super.key,
    required this.title,
    required this.time,
    required this.now,
    required this.done,
    required this.color,
    required this.onTap,
    this.icon,
  });

  final String title;
  final DateTime? time;
  final DateTime now;
  final bool done;
  final Color color;
  final VoidCallback onTap;

  /// Sistem satırında işaret kutusu yerine gösterilen simge.
  final IconData? icon;

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
      checked: icon == null ? done : null,
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (icon != null && !done)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 15, color: color),
                  ),
                )
              else
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
