import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../kokpit/presentation/kokpit_month_view.dart';
import '../../kokpit/presentation/kokpit_providers.dart';

/// İşler › Takvim: ay takvimi ve seçilen günün görev ve aylık işleri.
/// Her açılışta bugünün ayı gösterilir ve bugün seçilir.
class OpsCalendarScreen extends ConsumerStatefulWidget {
  const OpsCalendarScreen({super.key});

  @override
  ConsumerState<OpsCalendarScreen> createState() => _OpsCalendarScreenState();
}

class _OpsCalendarScreenState extends ConsumerState<OpsCalendarScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final today = AppDates.startOfDay(ref.read(kokpitClockProvider));
      ref.read(kokpitMonthProvider.notifier).state =
          DateTime(today.year, today.month);
      ref.read(kokpitSelectedDayProvider.notifier).state = today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: AppColors.accent),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Takvim')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            8,
            AppSpacing.page,
            120,
          ),
          children: const [KokpitMonthView()],
        ),
      ),
    );
  }
}
