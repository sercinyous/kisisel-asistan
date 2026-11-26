import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../operations/presentation/operations_providers.dart';
import '../../operations/domain/task_item.dart';
import '../../routines/domain/routine.dart';
import 'kokpit_format.dart';
import 'kokpit_motion.dart';

// Gün ve Ay görünümlerinin paylaştığı görsel parçalar.

class KokpitSectionHeader extends StatelessWidget {
  const KokpitSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? trailing;

  /// Bölümün alan rengi (işler sky, sağlık mint…); başlığın önünde nokta.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (accent != null) ...[
            RitimDot(color: accent, size: 8),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: AppType.cardTitle,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(
              trailing!,
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w500,
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
          Icon(icon, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 10),
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
    this.height = 6,
  });

  /// 0..1 aralığına kırpılır.
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reduce = kokpitReduceMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.bar),
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: reduce ? value.clamp(0, 1).toDouble() : 0,
          end: value.clamp(0, 1).toDouble(),
        ),
        duration: reduce ? Duration.zero : KokpitMotion.fill,
        curve: Curves.easeOutCubic,
        builder: (_, animated, __) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          backgroundColor: AppColors.track,
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
      duration: kokpitReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? fill : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked
              ? fill
              : enabled
                  ? AppColors.textMuted
                  : AppColors.border,
          width: 1.4,
        ),
      ),
      child: checked
          ? Icon(Icons.check_outlined, size: 14, color: AppColors.onAccent)
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

/// Kokpit görev satırına dokunma: açık görevi tamamlar (Geri al ile), bugün
/// tamamlanmışı yeniden açar. Yazma [OpsTasksNotifier] üzerinden gider; aynı
/// görev için ikinci dokunuş yok sayılır ve tazeleme oradan yayılır.
Future<void> completeKokpitTask(BuildContext context, TaskItem task) async {
  // Yazma sürerken ekran kapanabilir; await sonrası context kullanılmaz.
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = container.read(opsTasksProvider.notifier);
  void fail() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Görev güncellenemedi. Tekrar dene.')),
    );
  try {
    if (task.isDone) {
      await notifier.reopen(task);
      return;
    }
    if (!await notifier.complete(task)) return;
  } catch (_) {
    fail();
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Tamamlandı: ${task.title}'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () async {
            try {
              await notifier.reopen(task);
            } catch (_) {
              fail();
            }
          },
        ),
      ),
    );
}
