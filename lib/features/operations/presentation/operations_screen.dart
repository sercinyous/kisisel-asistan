import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'notes_view.dart';
import 'operations_providers.dart';
import 'routines_view.dart';
import 'tasks_view.dart';

/// Operasyon sekmesi: Görevler, Sabitler (tekrarlayan işler) ve Notlar.
class OperationsScreen extends ConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(opsSegmentProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              12,
              AppSpacing.page,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Operasyon',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<OpsSegment>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: OpsSegment.tasks,
                      label: Text('Görevler'),
                    ),
                    ButtonSegment(
                      value: OpsSegment.routines,
                      label: Text('Sabitler'),
                    ),
                    ButtonSegment(
                      value: OpsSegment.notes,
                      label: Text('Notlar'),
                    ),
                  ],
                  selected: {segment},
                  onSelectionChanged: (selection) => ref
                      .read(opsSegmentProvider.notifier)
                      .state = selection.first,
                ),
              ],
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
    );
  }
}

/// Bölüm listelerinin ortak kenar boşluğu; alt bar içeriğin üstüne bindiği
/// için altta pay bırakılır.
const EdgeInsets opsListPadding =
    EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 120);
