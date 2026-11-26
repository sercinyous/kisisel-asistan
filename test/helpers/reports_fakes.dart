import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_health_extras.dart';
import 'package:kisisel_asistan/features/reports/data/weekly_checkin_repository.dart';
import 'package:kisisel_asistan/features/friends/domain/friends_models.dart';
import 'package:kisisel_asistan/features/friends/presentation/friends_providers.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/operations/presentation/dashboard/task_dashboard_providers.dart';
import 'package:kisisel_asistan/features/operations/presentation/dashboard/task_dashboard_stats.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/presentation/settings_providers.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_providers.dart';
import 'package:kisisel_asistan/features/reports/presentation/reports_screen.dart';

import 'fakes.dart';

/// Sunucunun ürettiği biçimde haftalık `metrics` (taslaktaki sayılar).
/// [elapsedDays] sonrası günler henüz gelmemiş sayılır (oranlar null).
Map<String, dynamic> weeklyMetricsJson(
  DateTime weekStart, {
  int elapsedDays = 7,
  int workRate = 78,
  int formRate = 71,
  double? weightChange = -0.4,
}) =>
    {
      'period': {
        'start': AppDates.ymd(weekStart),
        'end': AppDates.ymd(AppDates.addDays(weekStart, 6)),
      },
      'work': {
        'tasks_total': 12,
        'tasks_done': 9,
        'routines_planned': 11,
        'routines_done': 9,
        'rate': workRate,
      },
      'form': {
        'workouts_planned': 7,
        'workouts_done': 5,
        'protein_days_hit': 5,
        'calorie_days_in_range': 4,
        'rate': formRate,
      },
      'nutrition': {
        'calories': 1960,
        'protein_g': 158,
        'carbs_g': 170,
        'fat_g': 60,
        'days_logged': 6,
      },
      'health': {
        'steps': 8240,
        'sleep_minutes': 425,
        'active_kcal': 430,
        'days_with_data': 7,
      },
      'weight': {
        'start_kg': weightChange == null ? null : 84.0,
        'end_kg': weightChange == null ? null : 84.0 + weightChange,
        'change_kg': weightChange,
      },
      'targets': {
        'calories': 2000,
        'protein_g': 170,
        'steps': 10000,
        'sleep_minutes': 450,
      },
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': AppDates.ymd(AppDates.addDays(weekStart, i)),
            // En geniş etiket (100) da sığmalı.
            'work_rate': i < elapsedDays ? (i.isEven ? 100 : 64) : null,
            'form_rate': i < elapsedDays ? (i.isEven ? 100 : 50) : null,
            'calories': i < elapsedDays ? 1900 + i * 20 : 0,
            'protein_g': i < elapsedDays ? 150 + i : 0,
            'steps': i < elapsedDays ? 8000 + i * 100 : 0,
            'sleep_minutes': i < elapsedDays ? 420 : 0,
            'workouts': i < elapsedDays && i.isEven ? 1 : 0,
          },
      ],
    };

WeeklyReport weeklyReport(
  DateTime weekStart, {
  String? summary = 'Hafta özeti.',
  ReportAiStatus? status,
  int elapsedDays = 7,
  int workRate = 78,
  int formRate = 71,
  double? weightChange = -0.4,
}) =>
    WeeklyReport(
      weekStart: weekStart,
      metrics: ReportMetrics.fromJson(
        weeklyMetricsJson(
          weekStart,
          elapsedDays: elapsedDays,
          workRate: workRate,
          formRate: formRate,
          weightChange: weightChange,
        ),
      ),
      aiSummary: summary,
      aiStatus: status ??
          (summary == null ? ReportAiStatus.failed : ReportAiStatus.ok),
      generatedAt: DateTime(2026, 11, 16, 7),
    );

DailyReport dailyReport(
  DateTime day, {
  String? summary = 'Gün özeti.',
  int workRate = 67,
  int formRate = 50,
}) =>
    DailyReport(
      reportDate: day,
      metrics: ReportMetrics.fromJson({
        'period': {'start': AppDates.ymd(day), 'end': AppDates.ymd(day)},
        'work': {
          'tasks_total': 3,
          'tasks_done': 2,
          'routines_planned': 7,
          'routines_done': 5,
          'rate': workRate,
        },
        'form': {
          'workouts_planned': 1,
          'workouts_done': 1,
          'protein_days_hit': 0,
          'calorie_days_in_range': 1,
          'rate': formRate,
        },
        'nutrition': {
          'calories': 1840,
          'protein_g': 148,
          'carbs_g': 170,
          'fat_g': 60,
          'days_logged': 1,
        },
        'health': {
          'steps': 10240,
          'sleep_minutes': 425,
          'active_kcal': 430,
          'days_with_data': 1,
        },
        'weight': {'start_kg': null, 'end_kg': null, 'change_kg': null},
        'targets': {
          'calories': 2000,
          'protein_g': 170,
          'steps': 10000,
          'sleep_minutes': 450,
        },
      }),
      aiSummary: summary,
      aiStatus: summary == null ? ReportAiStatus.failed : ReportAiStatus.ok,
      generatedAt: day.add(const Duration(hours: 23, minutes: 45)),
    );

/// Raporlar widget testlerinin ortak kurulumu.
class ReportsHarness {
  final FakeReportsRepository reports = FakeReportsRepository();

  /// Arkadaş sıralaması (kendin dahil); boşsa arkadaş satırı gizlenir.
  List<LeaderboardEntry> leaderboard = const [];

  /// Haftalık check-in'ler (ruh hali + not).
  final FakeWeeklyCheckinRepository checkins = FakeWeeklyCheckinRepository();

  /// AI kullanım onayı (`aiConsentProvider`).
  bool aiConsent = true;

  /// Ay görünümünün özeti; `null` ise boş bir ay döner.
  MonthOverview? monthOverview;

  /// Sabit "şimdi": 18 Kasım 2026 Çarşamba; içinde bulunulan hafta 16–22 Kasım.
  static final DateTime now = DateTime(2026, 11, 18, 10);
  static final DateTime today = DateTime(2026, 11, 18);
  static final DateTime thisWeek = DateTime(2026, 11, 16);
  static final DateTime lastWeek = DateTime(2026, 11, 9);

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(375, 667) * 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(reports),
        aiConsentProvider.overrideWith((ref) async => aiConsent),
        weeklyCheckinRepositoryProvider.overrideWithValue(checkins),
        friendsLeaderboardProvider.overrideWith((ref) async => leaderboard),
        monthOverviewProvider.overrideWith(
          (ref, month) async =>
              monthOverview ??
              MonthOverview(
                month: DateTime(month.year, month.month),
                monthly: const [],
                tasks: const [],
                weeklyPlanned: 0,
                weeklyDone: 0,
                health: const MonthHealthSummary(),
              ),
        ),
        taskDashboardProvider.overrideWith(
          (ref) async =>
              computeTaskDashboardStats(const [], now: now, weekCount: 8),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(kokpitClockProvider.notifier).state = now;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: ReportsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Sayfayı baştan sona kaydırır; her adımda taşma (ya da başka bir çizim
  /// hatası) olmadığını doğrular.
  Future<void> expectNoOverflowWhileScrolling(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'kaydırma adımı $i');
    }
  }

  /// Anahtarlı satırı görünür yapıp dokunur.
  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Metni taşıyan düğmeyi görünür yapıp dokunur (çökelmeyi beklemez).
  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }
}
