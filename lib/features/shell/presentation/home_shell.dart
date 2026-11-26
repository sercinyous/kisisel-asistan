import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_service.dart'
    show notificationTapPayload, tabForNotificationPayload;
import '../../../core/services/notification_sync.dart';
import '../../../core/widgets/app_bottom_bar.dart';
import '../../ai_quick_add/domain/quick_add_mode.dart';
import '../../ai_quick_add/presentation/ai_consent_sheet.dart';
import '../../ai_quick_add/presentation/ai_quick_add_modal.dart';
import '../../ai_quick_add/presentation/quick_add_mode_sheet.dart';
import '../../health/presentation/health_providers.dart';
import '../../health/presentation/providers/body_providers.dart';
import '../../health/presentation/health_screen.dart';
import '../../health/presentation/providers/targets_providers.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_screen.dart';
import '../../operations/presentation/operations_screen.dart';
import '../../reminders/presentation/reminders_providers.dart';
import '../../reports/presentation/reports_providers.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../friends/presentation/friends_providers.dart';
import '../../stories/presentation/stories_providers.dart';

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

/// Arka arkaya gelen "resumed" olaylarında ağır tazelemenin en kısa aralığı.
const Duration resumeRefreshThrottle = Duration(seconds: 60);

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  /// Uygulama açıkken dakika başında saati ilerletir; gün dönünce "bugün"e
  /// bağlı veriler tazelenir.
  Timer? _clockTimer;

  void _scheduleClockTick() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1));
    _clockTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      _tickClock();
      _scheduleClockTick();
    });
  }

  void _tickClock() {
    final clock = ref.read(kokpitClockProvider.notifier);
    final previous = clock.state;
    final now = DateTime.now();
    if (now.year != previous.year ||
        now.month != previous.month ||
        now.day != previous.day) {
      _refreshForNewMoment();
    } else {
      clock.state = now;
    }
  }

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
    _scheduleClockTick();
    notificationTapPayload.addListener(_openNotificationTarget);
    // Açılışta HealthKit'in son günleri gün sonu değerleriyle tamamlanır
    // (uygulama kapalıyken biten günleri başka okuyan yoktur).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Uygulama bildirime dokunularak açıldıysa ilgili sekme.
      _openNotificationTarget();
      unawaited(
        backfillHealthKit(ProviderScope.containerOf(context, listen: false)),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationTapPayload.removeListener(_openNotificationTarget);
    _clockTimer?.cancel();
    super.dispose();
  }

  /// Uygulama öne geldiğinde gün değişmiş, sunucu yeni rapor yazmış olabilir:
  /// "bugün"e göre hesaplanan ve sunucuda değişmiş olabilecek her şeyi tazele.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Denetim Merkezi, izin uyarısı ya da seçici kapanınca da "resumed"
    // gelir; gün değişmediyse ve son tazelemeden bu yana 60 sn geçmediyse
    // yalnız saat ilerler.
    final now = DateTime.now();
    final last = _lastRefresh;
    if (last != null &&
        now.difference(last) < resumeRefreshThrottle &&
        DateUtils.isSameDay(now, last)) {
      ref.read(kokpitClockProvider.notifier).state = now;
    } else {
      _refreshForNewMoment();
    }
    // Arka planda zamanlayıcı kaymış olabilir; dakika hizası yeniden kurulur.
    _scheduleClockTick();
  }

  DateTime? _lastRefresh;

  /// Dokunulan bildirimin sekmesine geçer (görev/rutin İşler, sağlık Sağlık).
  void _openNotificationTarget() {
    final payload = notificationTapPayload.value;
    if (payload == null || !mounted) return;
    notificationTapPayload.value = null;
    final tab = tabForNotificationPayload(payload);
    if (tab != null && tab != _index) setState(() => _index = tab);
  }

  void _refreshForNewMoment() {
    _lastRefresh = DateTime.now();
    final container = ProviderScope.containerOf(context, listen: false);
    ref.read(kokpitClockProvider.notifier).state = DateTime.now();
    ref.invalidate(todayOccurrencesProvider);
    ref.invalidate(upcomingRemindersProvider);
    // Ölçü/fotoğraf günü satırı ve 09:00 hatırlatması "bugün"e göredir.
    ref.invalidate(checkinTodayProvider);
    // Arkadaş hikâyeleri 24 saatte düşer; yenileri de gelmiş olabilir.
    ref.invalidate(friendStoryGroupsProvider);
    ref
      ..invalidate(friendsLeaderboardProvider)
      ..invalidate(pendingFriendRequestCountProvider);
    // Sağlık sekmesi, Kokpit beslenme özeti ve Ay özeti: pencereleri (son N
    // gün, bu hafta, bugünün öğünleri) ve durum rozetleri bugüne göredir.
    invalidateHealthData(container);
    // HealthKit yeniden okunur, son günler tamamlanır; 7 günlük adım grafiği
    // ve Ay ortalamaları yedekleme bitince tazelenir (önce tazelenirse yeni
    // satırı görmezler).
    unawaited(resyncHealthKit(container));
    // Raporlar sunucuda, uygulama arka plandayken üretilir.
    ref
      ..invalidate(weeklyReportProvider)
      ..invalidate(weeklyReportListProvider)
      ..invalidate(dailyReportProvider)
      ..invalidate(dailyReportListProvider);
  }

  Future<void> _openQuickAdd() async {
    final messenger = ScaffoldMessenger.of(context);
    final mode =
        quickAddModeForTab(_index) ?? await QuickAddModeSheet.show(context);
    if (mode == null || !mounted) return;
    if (!await ensureAiConsent(context, ref) || !mounted) return;
    final saved = await AiQuickAddModal.show(context, mode: mode);
    if (saved == null || saved == 0) return;
    messenger.showSnackBar(SnackBar(content: Text('$saved kayıt eklendi.')));
  }

  @override
  Widget build(BuildContext context) {
    // Bildirim izni + bekleyen bildirimlerin eşitlenmesi (oturum başına bir kez).
    ref.watch(notificationSyncProvider);
    // Bildirimdeki "Yaptım" eylemleri (oturum sahibi denetimiyle).
    ref.watch(reminderActionProcessorProvider);
    // Eski cihaz tercihleri (yağ yakımı hızı, elle harcama) bir kez
    // user_settings'e taşınır.
    ref.watch(legacyFatLossPrefsMigrationProvider);
    // Kokpit kartlarından gelen sekme geçişi isteği.
    ref.listen<int?>(homeTabRequestProvider, (_, next) {
      if (next == null) return;
      setState(() => _index = next);
      ref.read(homeTabRequestProvider.notifier).state = null;
    });

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
