import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/item_actions.dart';
import '../../routines/data/routines_repository.dart';
import '../../reminders/domain/reminder.dart';
import '../../reminders/presentation/reminder_form_sheet.dart';
import '../../reminders/presentation/reminders_providers.dart';
import '../../reminders/presentation/reminders_screen.dart';
import '../../routines/domain/routine.dart';
import 'operations_providers.dart';
import 'operations_screen.dart';
import 'operations_widgets.dart';
import 'routine_form_sheet.dart';

const List<String> opsWeekdayLabels = [
  'Pzt',
  'Sal',
  'Çar',
  'Per',
  'Cum',
  'Cmt',
  'Paz',
];

/// "Her gün · 09:00", "Pzt, Çar · 11:00", "Her ayın 15. günü · 10:00"
String routineScheduleLabel(Routine r) {
  final String days;
  if (r.isMonthly) {
    days = 'Her ayın ${r.dayOfMonth ?? 1}. günü';
  } else if (r.isDaily) {
    days = 'Her gün';
  } else {
    final sorted = r.daysOfWeek.toSet().toList()..sort();
    days = [
      for (final d in sorted)
        if (d >= 1 && d <= 7) opsWeekdayLabels[d - 1],
    ].join(', ');
  }
  final time = r.timeLabel;
  return time == null ? days : '$days · $time';
}

/// Rutin formunu açar (yeni ya da düzenleme) ve sonucu bildirir. Operasyon
/// listesi ile Kokpit satırlarının ortak yoludur; kayıt sonrası sağlayıcıları
/// ve bildirim planını form kendisi tazeler.
Future<void> openRoutineForm(BuildContext context, [Routine? routine]) async {
  final messenger = ScaffoldMessenger.of(context);
  var nextOrder = 0;
  if (routine == null) {
    // Yeni kayıt listenin sonuna gelsin.
    final container = ProviderScope.containerOf(context, listen: false);
    final all =
        container.read(opsRoutinesProvider).valueOrNull ?? const <Routine>[];
    nextOrder = all.fold<int>(
          0,
          (max, r) => r.sortOrder > max ? r.sortOrder : max,
        ) +
        10;
  }
  final saved = await RoutineFormSheet.show(
    context,
    routine: routine,
    nextSortOrder: nextOrder,
  );
  if (!saved) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content:
            Text(routine == null ? 'Rutin eklendi.' : 'Rutin güncellendi.'),
      ),
    );
}

const String routineDeleteTitle = 'Rutin silinsin mi?';

String routineDeleteMessage(Routine routine) =>
    '"${routine.title}" ve tamamlanma geçmişi kalıcı olarak silinecek.';

/// Rutini (ve tamamlanma geçmişini) siler; başarılıysa `true`. Gün/Ay
/// ekranları, haftalık antrenman planı ve bildirim planı tazelenir. [confirm]
/// doğruysa önce onay sorulur; uzun basış ve kaydırma onayı kendisi sorar.
Future<bool> deleteRoutine(
  BuildContext context,
  Routine routine, {
  bool confirm = false,
}) async {
  // Onay ve yazma sürerken ekran kapanabilir; await sonrası context kullanılmaz.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  if (confirm) {
    final confirmed = await confirmDelete(
      context,
      title: routineDeleteTitle,
      message: routineDeleteMessage(routine),
    );
    if (!confirmed) return false;
  }
  try {
    await container.read(routinesRepositoryProvider).delete(routine.id);
    notifyRoutineChange(container.invalidate);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Rutin silinemedi.')),
    );
    return false;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Rutin silindi.')));
  return true;
}

/// Rutin satırına uzun basış menüsü (Düzenle / Sil) ve sola kaydırarak silme
/// ekler; Operasyon listesi ve Kokpit (rutin, aylık iş, ay günü) ortak kullanır.
class RoutineRowActions extends StatelessWidget {
  const RoutineRowActions({
    super.key,
    required this.routine,
    required this.child,
    this.borderRadius,
  });

  final Routine routine;
  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ItemRowActions(
      itemKey: ValueKey('swipe-routine-${routine.id}'),
      title: routine.title,
      confirmTitle: routineDeleteTitle,
      confirmMessage: routineDeleteMessage(routine),
      borderRadius: borderRadius,
      onEdit: () => openRoutineForm(context, routine),
      onDelete: () => deleteRoutine(context, routine),
      child: child,
    );
  }
}

class RoutinesView extends ConsumerWidget {
  const RoutinesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(routineScopeFilterProvider);
    final routines = ref.watch(opsRoutinesProvider);
    final reminders = ref.watch(remindersProvider);

    List<Widget> rows(List<Routine> items) => [
          for (final (index, routine) in items.indexed) ...[
            if (index > 0)
              const Divider(indent: AppSpacing.cardPadding, height: 1),
            RoutineRowActions(
              key: ValueKey('ops-routine-${routine.id}'),
              routine: routine,
              child: _RoutineRow(
                routine: routine,
                onEdit: () => openRoutineForm(context, routine),
              ),
            ),
          ],
        ];

    final reminderGroup = OpsGroupCard(
      key: const ValueKey('ops-group-reminders'),
      title: 'Hatırlatıcılar',
      count: reminders.valueOrNull?.length ?? 0,
      action: IconButton(
        key: const ValueKey('ops-reminder-add'),
        tooltip: 'Hatırlatıcı ekle',
        icon: Icon(Icons.add_rounded, color: AppColors.ops),
        onPressed: () => ReminderFormSheet.show(context),
      ),
      children: reminders.when(
        skipLoadingOnRefresh: true,
        loading: () => const [OpsLoading()],
        error: (_, __) => [
          OpsMessage(
            icon: Icons.cloud_off_rounded,
            text: 'Hatırlatıcılar yüklenemedi.',
            onRetry: () => ref.invalidate(remindersProvider),
          ),
        ],
        data: (items) => [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                12,
                AppSpacing.cardPadding,
                8,
              ),
              child: Text(
                'Su, ilaç, yürüyüş gibi alışkanlıklar için + ile '
                'hatırlatıcı ekle.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          for (final (index, reminder) in items.indexed) ...[
            if (index > 0)
              const Divider(indent: AppSpacing.cardPadding, height: 1),
            _ReminderRow(
              key: ValueKey('ops-reminder-${reminder.id}'),
              reminder: reminder,
              onTap: () => ReminderFormSheet.show(context, reminder: reminder),
            ),
          ],
          if (items.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton(
                  key: const ValueKey('ops-reminders-all'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RemindersScreen(),
                    ),
                  ),
                  child: const Text('Tümünü yönet'),
                ),
              ),
            ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(opsRoutinesProvider)
          ..invalidate(remindersProvider);
        try {
          await ref.read(opsRoutinesProvider.future);
        } catch (_) {
          // Hata durumu ekranda zaten gösterilir.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: opsListPadding,
        children: [
          ...routines.when(
            loading: () => const [OpsLoading()],
            error: (_, __) => [
              OpsMessage(
                icon: Icons.cloud_off_rounded,
                text: 'Rutinler yüklenemedi.',
                onRetry: () => ref.invalidate(opsRoutinesProvider),
              ),
            ],
            data: (all) {
              final visible = [
                for (final r in all)
                  if (filter == null || r.scope == filter) r,
              ];
              if (visible.isEmpty) {
                return [
                  OpsMessage(
                    icon: Icons.repeat_rounded,
                    text: filter == null
                        ? 'Henüz rutin yok. + ile tekrarlayan iş oluştur.'
                        : '$filter kapsamında rutin yok.',
                  ),
                ];
              }
              final weekday = DateTime.now().weekday;
              final today = [
                for (final r in visible)
                  if (!r.isMonthly && r.daysOfWeek.contains(weekday)) r,
              ];
              final otherDays = [
                for (final r in visible)
                  if (!r.isMonthly && !r.daysOfWeek.contains(weekday)) r,
              ];
              final monthly = visible.where((r) => r.isMonthly).toList()
                ..sort(
                  (a, b) => (a.dayOfMonth ?? 1).compareTo(b.dayOfMonth ?? 1),
                );
              final groups = [
                if (today.isNotEmpty)
                  OpsGroupCard(
                    key: const ValueKey('ops-group-routines-today'),
                    title: 'Bugün',
                    count: today.length,
                    children: rows(today),
                  ),
                if (otherDays.isNotEmpty)
                  OpsGroupCard(
                    key: const ValueKey('ops-group-routines-week'),
                    title: 'Haftanın diğer günleri',
                    count: otherDays.length,
                    children: rows(otherDays),
                  ),
                if (monthly.isNotEmpty)
                  OpsGroupCard(
                    key: const ValueKey('ops-group-routines-monthly'),
                    title: 'Aylık',
                    count: monthly.length,
                    children: rows(monthly),
                  ),
              ];
              return [
                for (final (index, group) in groups.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.grid),
                  group,
                ],
              ];
            },
          ),
          const SizedBox(height: AppSpacing.grid),
          reminderGroup,
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.routine, required this.onEdit});

  final Routine routine;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = routine.isActive;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 6,
              color: active
                  ? AppColors.forRoutineCategory(routine.category)
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: active ? null : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      routine.scope,
                      routineScheduleLabel(routine),
                      if (!active) 'Pasif',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (!routine.notify)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({super.key, required this.reminder, required this.onTap});

  final Reminder reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = reminder.enabled;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(
              Icons.alarm_rounded,
              size: 18,
              color: enabled ? AppColors.ops : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: enabled ? null : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [reminder.scheduleLabel, if (!enabled) 'Kapalı']
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
