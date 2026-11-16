import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../routines/data/routines_repository.dart';
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

class RoutinesView extends ConsumerWidget {
  const RoutinesView({super.key});

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, [
    Routine? routine,
  ]) async {
    final messenger = ScaffoldMessenger.of(context);
    // Yeni kayıt listenin sonuna gelsin.
    final all = ref.read(opsRoutinesProvider).valueOrNull ?? const <Routine>[];
    final nextOrder = all.fold<int>(
          0,
          (max, r) => r.sortOrder > max ? r.sortOrder : max,
        ) +
        10;
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
              Text(routine == null ? 'Sabit eklendi.' : 'Sabit güncellendi.'),
        ),
      );
  }

  Future<void> _delete(BuildContext context, Routine routine) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await confirmDelete(
      context,
      title: 'Sabit silinsin mi?',
      message: '"${routine.title}" ve tamamlanma geçmişi kalıcı olarak '
          'silinecek.',
    );
    if (!confirmed) return;
    try {
      await container.read(routinesRepositoryProvider).delete(routine.id);
      notifyRoutineChange(container.invalidate);
      messenger.showSnackBar(const SnackBar(content: Text('Sabit silindi.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sabit silinemedi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(routineScopeFilterProvider);
    final routines = ref.watch(opsRoutinesProvider);

    Widget group(String title, IconData icon, List<Routine> items) => BentoCard(
          padding: const EdgeInsets.only(top: AppSpacing.cardPadding, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.cardPadding,
                ),
                child: BentoLabel(
                  icon: icon,
                  label: title,
                  trailing: '${items.length}',
                ),
              ),
              const SizedBox(height: 4),
              for (final (index, routine) in items.indexed) ...[
                if (index > 0) const Divider(indent: AppSpacing.cardPadding),
                _RoutineRow(
                  routine: routine,
                  onEdit: () => _openForm(context, ref, routine),
                  onDelete: () => _delete(context, routine),
                ),
              ],
            ],
          ),
        );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(opsRoutinesProvider);
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
          OpsSectionHeader(
            title: 'Sabitler',
            onAdd: () => _openForm(context, ref),
          ),
          OpsFilterChips<String?>(
            options: [
              (null, 'Tümü'),
              for (final s in Routine.scopes) (s, s),
            ],
            selected: filter,
            onSelected: (value) =>
                ref.read(routineScopeFilterProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          ...routines.when(
            loading: () => const [OpsLoading()],
            error: (_, __) => [
              OpsMessage(
                icon: Icons.cloud_off_rounded,
                text: 'Sabitler yüklenemedi.',
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
                        ? 'Henüz sabit yok. "Ekle" ile tekrarlayan iş oluştur.'
                        : '$filter kapsamında sabit yok.',
                  ),
                ];
              }
              final weekly = visible.where((r) => !r.isMonthly).toList();
              final monthly = visible.where((r) => r.isMonthly).toList()
                ..sort(
                  (a, b) => (a.dayOfMonth ?? 1).compareTo(b.dayOfMonth ?? 1),
                );
              return [
                if (weekly.isNotEmpty)
                  group('Günlük ve haftalık', Icons.repeat_rounded, weekly),
                if (weekly.isNotEmpty && monthly.isNotEmpty)
                  const SizedBox(height: AppSpacing.grid),
                if (monthly.isNotEmpty)
                  group('Aylık', Icons.calendar_month_rounded, monthly),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    required this.routine,
    required this.onEdit,
    required this.onDelete,
  });

  final Routine routine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = routine.isActive;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.cardPadding, 8, 0, 8),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 10,
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
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            if (!routine.notify)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            OpsItemMenu(onEdit: onEdit, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}
