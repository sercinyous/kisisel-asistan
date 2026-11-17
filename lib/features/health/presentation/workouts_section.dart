import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/item_actions.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'workout_form_sheet.dart';

IconData _workoutIcon(String workoutType) => switch (workoutType) {
      'weights' => Icons.fitness_center_rounded,
      'kickboxing' => Icons.sports_mma_rounded,
      'running' => Icons.directions_run_rounded,
      'football' => Icons.sports_soccer_rounded,
      _ => Icons.bolt_rounded,
    };

const String _deleteTitle = 'Antrenman silinsin mi?';

String _deleteMessage(WorkoutLog workout) =>
    '"${HealthFormat.workoutTitle(workout)}" günlükten kaldırılacak.';

/// Antrenman günlüğü: son [recentWorkoutsDays] günün kayıtları, yeniden eskiye.
class WorkoutsSection extends ConsumerStatefulWidget {
  const WorkoutsSection({super.key});

  @override
  ConsumerState<WorkoutsSection> createState() => _WorkoutsSectionState();
}

class _WorkoutsSectionState extends ConsumerState<WorkoutsSection> {
  /// Kapalıyken gösterilen satır sayısı.
  static const int _collapsedCount = 5;

  bool _showAll = false;

  /// Antrenmanı siler; başarılıysa `true`. [confirm] doğruysa önce onay
  /// sorulur (üç nokta menüsü); uzun basış ve kaydırma onayı kendisi sorar.
  Future<bool> _delete(WorkoutLog workout, {bool confirm = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    if (confirm) {
      final confirmed = await confirmDelete(
        context,
        title: _deleteTitle,
        message: _deleteMessage(workout),
      );
      if (!confirmed) return false;
    }
    try {
      await container.read(healthRepositoryProvider).deleteWorkout(workout.id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text(healthDeleteError)));
      return false;
    }
    invalidateHealthData(container);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final workouts = ref.watch(recentWorkoutsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthSectionHeader(
          title: 'Antrenman günlüğü',
          actionLabel: 'Ekle',
          onAction: () => WorkoutFormSheet.show(context),
        ),
        workouts.when(
          skipLoadingOnRefresh: true,
          loading: () => const KokpitSkeletonCard(height: 112),
          error: (_, __) => KokpitInlineMessage(
            icon: Icons.cloud_off_rounded,
            message: 'Antrenmanlar yüklenemedi.',
            actionLabel: 'Tekrar dene',
            onAction: () => ref.invalidate(recentWorkoutsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const KokpitInlineMessage(
                icon: Icons.fitness_center_rounded,
                message: 'Son $recentWorkoutsDays günde antrenman kaydı yok.',
              );
            }
            final visible =
                _showAll ? items : items.take(_collapsedCount).toList();
            return HealthListCard(
              children: [
                for (final workout in visible)
                  ItemRowActions(
                    key: ValueKey('workout-actions-${workout.id}'),
                    itemKey: ValueKey('swipe-workout-${workout.id}'),
                    title: HealthFormat.workoutTitle(workout),
                    confirmTitle: _deleteTitle,
                    confirmMessage: _deleteMessage(workout),
                    onEdit: () =>
                        WorkoutFormSheet.show(context, workout: workout),
                    onDelete: () => _delete(workout),
                    child: _WorkoutTile(
                      workout: workout,
                      onEdit: () =>
                          WorkoutFormSheet.show(context, workout: workout),
                      onDelete: () => _delete(workout, confirm: true),
                    ),
                  ),
                if (items.length > _collapsedCount)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(healthMinTouch),
                    ),
                    child: Text(
                      _showAll
                          ? 'Daha az göster'
                          : 'Tümünü göster (${items.length})',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile({
    required this.workout,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkoutLog workout;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final burned = workout.caloriesBurned;
    return HealthListRow(
      key: ValueKey('workout-${workout.id}'),
      icon: _workoutIcon(workout.workoutType),
      color: AppColors.fitness,
      title: HealthFormat.workoutTitle(workout),
      subtitle: HealthFormat.workoutDetail(workout),
      value: burned == null ? null : HealthFormat.kcal(burned),
      onTap: onEdit,
      trailing: OpsItemMenu(onEdit: onEdit, onDelete: onDelete),
    );
  }
}
