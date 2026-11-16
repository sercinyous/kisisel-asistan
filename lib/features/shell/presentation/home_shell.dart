import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_sync.dart';
import '../../../core/widgets/app_bottom_bar.dart';
import '../../ai_quick_add/domain/quick_add_mode.dart';
import '../../ai_quick_add/presentation/ai_quick_add_modal.dart';
import '../../ai_quick_add/presentation/quick_add_mode_sheet.dart';
import '../../health/presentation/health_screen.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_screen.dart';
import '../../operations/presentation/operations_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../routines/presentation/routines_providers.dart';

/// + butonunun sekmeye göre açacağı giriş alanı. `null`: sekme bir alana
/// bağlı değildir (Kokpit, Raporlar), kullanıcıya sorulur.
QuickAddMode? quickAddModeForTab(int index) => switch (index) {
      1 => QuickAddMode.work,
      2 => QuickAddMode.health,
      _ => null,
    };

/// 4 sekme + ortada "AI Hızlı Giriş" butonu.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const List<Widget> _tabs = [
    KokpitScreen(),
    OperationsScreen(),
    HealthScreen(),
    ReportsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Uygulama öne geldiğinde gün değişmiş olabilir: Kokpit'i tazele.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(kokpitClockProvider.notifier).state = DateTime.now();
    ref.invalidate(todayOccurrencesProvider);
    ref.invalidate(upcomingRemindersProvider);
    ref.invalidate(todayNutritionProvider);
    ref.invalidate(healthTodayProvider);
  }

  Future<void> _openQuickAdd() async {
    final messenger = ScaffoldMessenger.of(context);
    final mode =
        quickAddModeForTab(_index) ?? await QuickAddModeSheet.show(context);
    if (mode == null || !mounted) return;
    final saved = await AiQuickAddModal.show(context, mode: mode);
    if (saved == null || saved == 0) return;
    messenger.showSnackBar(SnackBar(content: Text('$saved kayıt eklendi.')));
  }

  @override
  Widget build(BuildContext context) {
    // Bildirim izni + bekleyen bildirimlerin eşitlenmesi (oturum başına bir kez).
    ref.watch(notificationSyncProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: AppBottomBar(
        currentIndex: _index,
        onSelect: (index) => setState(() => _index = index),
        onCreate: _openQuickAdd,
      ),
    );
  }
}
