import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_targets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../routines/domain/routine.dart';
import '../../settings/presentation/settings_providers.dart';
import 'calendar_screen.dart';
import 'notes_view.dart';
import 'operations_providers.dart';
import 'operations_widgets.dart';
import 'routines_view.dart';
import 'tasks_view.dart';

/// İşler sekmesi: Görevler, Rutinler (tekrarlayan işler + hatırlatıcılar) ve
/// Notlar. Tek başlık; takvim, filtre ve ekle eylemleri başlık satırındadır.
class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  /// Etkin bölümün filtre seçenekleri ve seçili değer sağlayıcısı.
  (StateProvider<String?>, List<String>) _filterOf(
    WidgetRef ref,
    OpsSegment segment,
  ) =>
      switch (segment) {
        OpsSegment.tasks => (
            taskCategoryFilterProvider,
            ref.watch(activeTaskCategoryNamesProvider),
          ),
        OpsSegment.routines => (routineScopeFilterProvider, Routine.scopes),
        OpsSegment.notes => (
            noteCategoryFilterProvider,
            AppTargets.noteCategories,
          ),
      };

  void _add(BuildContext context, OpsSegment segment) {
    switch (segment) {
      case OpsSegment.tasks:
        openTaskForm(context);
      case OpsSegment.routines:
        openRoutineForm(context);
      case OpsSegment.notes:
        openNoteForm(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(opsSegmentProvider);
    final (filterProvider, options) = _filterOf(ref, segment);
    final selected = ref.watch(filterProvider);
    // Kapatılan kategori filtrede kalmışsa filtre yok sayılır.
    final filter = options.contains(selected) ? selected : null;
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: AppColors.accent),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                12,
                AppSpacing.page - 8,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'İşler',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('ops-calendar'),
                    tooltip: 'Takvim',
                    icon: const Icon(Icons.calendar_month_outlined),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OpsCalendarScreen(),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('ops-filter'),
                    tooltip: 'Filtre',
                    icon: Icon(
                      filter == null
                          ? Icons.filter_list_outlined
                          : Icons.filter_alt_outlined,
                    ),
                    color: filter == null
                        ? AppColors.textSecondary
                        : AppColors.accent,
                    onPressed: () async {
                      final picked = await showOpsFilterSheet(
                        context,
                        options: options,
                        selected: filter,
                      );
                      if (picked == null) return;
                      ref.read(filterProvider.notifier).state = picked.value;
                    },
                  ),
                  IconButton(
                    key: const ValueKey('ops-add'),
                    tooltip: 'Ekle',
                    icon: const Icon(Icons.add_outlined),
                    color: AppColors.textPrimary,
                    onPressed: () => _add(context, segment),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                8,
                AppSpacing.page,
                12,
              ),
              child: RitimSegmented<OpsSegment>(
                segments: const {
                  OpsSegment.tasks: 'Görevler',
                  OpsSegment.routines: 'Rutinler',
                  OpsSegment.notes: 'Notlar',
                },
                selected: segment,
                onChanged: (value) => ref
                    .read(opsSegmentProvider.notifier)
                    .state = value,
              ),
            ),
            if (filter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  12,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    key: const ValueKey('ops-filter-chip'),
                    label: Text(filter),
                    deleteButtonTooltipMessage: 'Filtreyi kaldır',
                    onDeleted: () =>
                        ref.read(filterProvider.notifier).state = null,
                  ),
                ),
              ),
            Expanded(
              child: switch (segment) {
                OpsSegment.tasks => const TasksView(),
                OpsSegment.routines => const RoutinesView(),
                OpsSegment.notes => const NotesView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Bölüm listelerinin ortak kenar boşluğu; alt bar içeriğin üstüne bindiği
/// için altta pay bırakılır.
const EdgeInsets opsListPadding =
    EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 120);
