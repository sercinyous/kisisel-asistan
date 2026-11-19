import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../operations/data/tasks_repository.dart';
import '../../operations/domain/task_item.dart';
import '../../routines/domain/routine.dart';
import '../../routines/presentation/routines_providers.dart';
import 'kokpit_format.dart';
import 'kokpit_providers.dart';

// Gün ve Ay görünümlerinin paylaştığı görsel parçalar.

class KokpitSectionHeader extends StatelessWidget {
  const KokpitSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(
              trailing!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class KokpitInlineMessage extends StatelessWidget {
  const KokpitInlineMessage({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class KokpitSkeletonCard extends StatelessWidget {
  const KokpitSkeletonCard({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: EdgeInsets.zero,
      child: SizedBox(height: height, width: double.infinity),
    );
  }
}

class KokpitBar extends StatelessWidget {
  const KokpitBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });

  /// 0..1 aralığına kırpılır.
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (_, animated, __) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          backgroundColor: AppColors.surfaceHigh,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}

/// Rutin ve aylık iş satırlarındaki işaret kutusu.
class KokpitCheckBox extends StatelessWidget {
  const KokpitCheckBox({
    super.key,
    required this.checked,
    required this.color,
    this.enabled = true,
  });

  final bool checked;
  final Color color;

  /// Salt okunur satırda kutu soluk çizilir.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fill = enabled ? color : AppColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: checked ? fill : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: checked
              ? fill
              : enabled
                  ? AppColors.textMuted
                  : AppColors.border,
          width: 1.6,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 18, color: AppColors.onAccent)
          : null,
    );
  }
}

/// Aylık işin durum rozeti: Yapıldı / Bekliyor / Bugün / Gecikti / Yapılmadı.
class KokpitStatusChip extends StatelessWidget {
  const KokpitStatusChip({super.key, required this.status});

  final OccurrenceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = KokpitFormat.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        KokpitFormat.statusLabel(status),
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

/// Tek seferlik görevi tamamlar; Gün ve Ay listelerini, bildirim planını
/// tazeler ve sonucu kullanıcıya bildirir.
Future<void> completeKokpitTask(BuildContext context, TaskItem task) async {
  // Yazma sürerken ekran kapanabilir; await sonrası context kullanılmaz.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(tasksRepositoryProvider).complete(task.id);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Görev güncellenemedi. Tekrar dene.')),
    );
    return;
  }
  container
    ..invalidate(upcomingRemindersProvider)
    ..invalidate(monthOverviewProvider)
    ..invalidate(notificationSyncProvider);
  messenger.showSnackBar(
    SnackBar(content: Text('Tamamlandı: ${task.title}')),
  );
}
