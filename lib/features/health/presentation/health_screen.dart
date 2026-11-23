import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'body/body_view.dart';
import 'health_providers.dart';
import 'health_segment.dart';
import 'healthkit_card.dart';
import 'plan_view.dart';
import 'providers/body_providers.dart' show invalidateBodyData;
import 'providers/targets_providers.dart' show latestWeightProvider;
import 'providers/week_deficit_providers.dart' show healthDaysProvider;
import 'today/today_view.dart';

export 'health_segment.dart' show HealthSegment, healthSegmentProvider;

/// Sağlık sekmesi: üstte Bugün / Vücut / Plan seçimi. Kaynak (HealthKit /
/// Google Health) yalnızca sorun varken tek satır uyarı olarak görünür.
///
/// Başka bir ekrandan belirli görünümü açmak için `openHealth` kullanılır
/// (Kokpit kartına uzun basış ve Ayarlar > Hedeflerim "Plan'ı gör" Plan'ı
/// açar).
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  Future<void> _refresh(ProviderContainer container) async {
    invalidateHealthData(container);
    invalidateBodyData(container);
    container
      ..invalidate(healthDaysProvider)
      ..invalidate(latestWeightProvider);
    await resyncHealthKit(container);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final segment = ref.watch(healthSegmentProvider);

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
                Text('Sağlık', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 12),
                _SegmentBar(
                  selected: segment,
                  onSelected: (value) =>
                      ref.read(healthSegmentProvider.notifier).state = value,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  _refresh(ProviderScope.containerOf(context, listen: false)),
              child: SingleChildScrollView(
                key: PageStorageKey('health-${segment.name}'),
                physics: const AlwaysScrollableScrollPhysics(),
                // Alt bar içeriğin üstüne bindiği için altta pay bırakılır.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  120,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HealthSourceBanner(),
                    switch (segment) {
                      HealthSegment.today => const TodayView(),
                      HealthSegment.body => const BodyView(),
                      HealthSegment.plan => const PlanView(),
                    },
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kapsül biçimli üçlü seçim; seçili parça vurgu rengiyle doludur.
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.selected, required this.onSelected});

  final HealthSegment selected;
  final ValueChanged<HealthSegment> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final segment in HealthSegment.values)
              Expanded(
                child: Semantics(
                  selected: segment == selected,
                  button: true,
                  child: Material(
                    key: Key('health-segment-${segment.name}'),
                    color: segment == selected
                        ? AppColors.accent
                        : AppColors.surface.withValues(alpha: 0),
                    shape: const StadiumBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSelected(segment),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              segment.label,
                              maxLines: 1,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: segment == selected
                                    ? AppColors.onAccent
                                    : AppColors.textSecondary,
                                fontWeight: segment == selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
