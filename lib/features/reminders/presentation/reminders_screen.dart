import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/presentation/operations_widgets.dart';
import '../domain/reminder.dart';
import 'reminder_form_sheet.dart';
import 'reminders_providers.dart';

/// Ayarlar > Hatırlatıcılar: liste, aç/kapat, düzenle, sil, "Yaptım".
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('İşlem yapılamadı. Bağlantını kontrol et.'),
          ),
        );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    final ok = await confirmDelete(
      context,
      title: 'Hatırlatıcı silinsin mi?',
      message: '"${reminder.title}" ve "Yaptım" geçmişi silinecek.',
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => ref.read(remindersControllerProvider).delete(reminder.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);
    final done = ref.watch(reminderDoneProvider).valueOrNull ?? const {};
    final today = reminderDay(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hatırlatıcılar'),
        actions: [
          IconButton(
            key: const Key('reminders-add'),
            tooltip: 'Hatırlatıcı ekle',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => ReminderFormSheet.show(context),
          ),
        ],
      ),
      body: reminders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: OpsMessage(
            icon: Icons.cloud_off_rounded,
            text: 'Hatırlatıcılar yüklenemedi.',
            onRetry: () => ref.invalidate(remindersProvider),
          ),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(remindersProvider)
              ..invalidate(reminderDoneProvider);
            await ref.read(remindersProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              120,
            ),
            children: [
              if (items.isEmpty)
                BentoCard(
                  onTap: () => ReminderFormSheet.show(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BentoLabel(
                        icon: Icons.alarm_add_rounded,
                        label: 'Henüz hatırlatıcı yok',
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Su içmek, ilaç, yürüyüş gibi alışkanlıklar için '
                        'hatırlatıcı ekle. Hazır şablonlarla tek dokunuşta.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              for (final r in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.grid),
                  child: _ReminderCard(
                    reminder: r,
                    doneToday: done[r.id]?.contains(today) ?? false,
                    streak: r.streak(done[r.id] ?? const {}, today),
                    onEdit: () => ReminderFormSheet.show(context, reminder: r),
                    onDelete: () => _delete(context, ref, r),
                    onToggle: (value) => _run(
                      context,
                      () => ref
                          .read(remindersControllerProvider)
                          .setEnabled(r.id, value),
                    ),
                    onDone: (value) => _run(
                      context,
                      () => ref
                          .read(remindersControllerProvider)
                          .setDone(r.id, today, value),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.doneToday,
    required this.streak,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onDone,
  });

  final Reminder reminder;
  final bool doneToday;
  final int streak;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reminder;
    final scheduledToday = r.isScheduledOn(DateTime.now());
    return BentoCard(
      key: ValueKey('reminder-${r.id}'),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.alarm_rounded,
                color: r.enabled ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: r.enabled
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.scheduleLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: ValueKey('reminder-switch-${r.id}'),
                value: r.enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (r.isRepeating) ...[
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 18,
                  color: streak > 0 ? AppColors.warning : AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  streak > 0 ? '$streak gün seri' : 'Seri yok',
                  key: ValueKey('reminder-streak-${r.id}'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              const Spacer(),
              if (scheduledToday)
                doneToday
                    ? TextButton.icon(
                        key: ValueKey('reminder-undo-${r.id}'),
                        onPressed: () => onDone(false),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        icon: Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.accent,
                        ),
                        label: const Text('Yapıldı'),
                      )
                    : FilledButton.tonalIcon(
                        key: ValueKey('reminder-done-${r.id}'),
                        onPressed: () => onDone(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Yaptım'),
                      ),
              IconButton(
                key: ValueKey('reminder-delete-${r.id}'),
                tooltip: 'Sil',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
