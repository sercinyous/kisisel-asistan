import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// HealthKit durumu: bağlantı, son eşitleme ve yeniden bağlanma.
class HealthKitCard extends ConsumerWidget {
  const HealthKitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final health = ref.watch(healthTodayProvider);
    final snapshot = health.valueOrNull;
    final readAt = snapshot?.readAt;

    final (String message, String? action) = health.when(
      skipLoadingOnRefresh: true,
      loading: () => ('HealthKit okunuyor…', null),
      error: (_, __) => ('HealthKit verisi okunamadı.', 'Tekrar dene'),
      data: (data) => switch (data.status) {
        HealthStatus.unavailable => (
            'Adım, uyku ve aktif kalori yalnızca iPhone\'da HealthKit '
                'üzerinden okunur.',
            null,
          ),
        HealthStatus.denied => (
            'HealthKit erişimi verilmedi. Sağlık uygulaması > Paylaşım > '
                'Uygulamalar bölümünden izin verebilirsin.',
            'Yeniden bağlan',
          ),
        HealthStatus.ok => (
            data.hasData
                ? 'Adım, uyku ve aktif kalori Sağlık uygulamasından okunuyor. '
                    'Dün gece uyku: ${KokpitFormat.sleep(data.sleepMinutes)}.'
                : 'Bağlı, ancak bugün için veri gelmedi. Saatin ya da '
                    'telefonun Sağlık uygulamasına yazdığından emin ol.',
            'Yeniden bağlan',
          ),
      },
    );

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.favorite_rounded,
            label: 'HealthKit',
            color: AppColors.danger,
            trailing: health.isLoading || readAt == null
                ? null
                : 'son eşitleme ${AppDates.hourMinute(readAt)}',
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: health.isLoading
                    ? null
                    : () => resyncHealthKit(
                          ProviderScope.containerOf(context, listen: false),
                        ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(healthMinTouch, healthMinTouch),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }
}
