import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import 'health_widgets.dart';
import 'providers/streaks_providers.dart';
import 'providers/week_deficit_providers.dart';
import 'today/streak_strip.dart' show streakColor, streakIcon;
import 'today/today_common.dart';
import 'trend_providers.dart' show trendClockProvider;

/// Serinin sayılma kuralı (kullanıcıya gösterilen metin).
String streakRule(StreakKind kind) => switch (kind) {
      StreakKind.steps => 'Adım hedefine ulaştığın her gün sayılır.',
      StreakKind.logging => 'En az 2 öğün girdiğin ya da kalori hedefinin '
          'yarısını kaydettiğin gün sayılır.',
      StreakKind.deficit => 'Kayıt günü olup kalori tabanı ile hedefin '
          'arasında kaldığın ve açığın güvenli sınırı aşmadığı gün sayılır. '
          'Aç kalmak seriyi uzatmaz.',
      StreakKind.target => 'Kayıt günü olup aldığın kalorinin hedefinin '
          '±%10\'u içinde kaldığı gün sayılır.',
    };

const String streakGraceNote =
    'Bugün gece yarısına kadar seriyi bozmaz; gün bitince kesinleşir.';

/// Seri detayı: her serinin şimdiki/en iyi değeri, 30 günlük nokta takvimi,
/// kural ve son 8 haftanın açığı.
class StreakDetailScreen extends ConsumerWidget {
  const StreakDetailScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const StreakDetailScreen()),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider);
    final weeks = ref.watch(pastWeekDeficitsProvider(8));
    final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
    return Scaffold(
      appBar: AppBar(title: const Text('Seriler')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 120),
        children: [
          streaks.when(
            skipLoadingOnReload: true,
            loading: () => const HealthCardLoading(height: 200),
            error: (_, __) => BentoGrid(children: [
              BentoCell(
                child: BentoCard(
                  child: HealthCompactMessage(
                    text: 'Seriler yüklenemedi.',
                    onRetry: () => ref.invalidate(streaksProvider),
                  ),
                ),
              ),
            ]),
            data: (state) => BentoGrid(children: [
              for (final s in state.streaks)
                BentoCell(child: _StreakCard(status: s, today: today)),
            ]),
          ),
          const SizedBox(height: AppSpacing.grid),
          BentoGrid(children: [
            BentoCell(
              child: BentoCard(
                key: const Key('streak-weeks-card'),
                child: weeks.when(
                  skipLoadingOnReload: true,
                  loading: () => const HealthCardLoading(height: 160),
                  error: (_, __) => HealthCompactMessage(
                    text: 'Haftalık açık yüklenemedi.',
                    onRetry: () => ref.invalidate(pastWeekDeficitsProvider(8)),
                  ),
                  data: (list) => _WeeksBody(weeks: list),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            streakGraceNote,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.status, required this.today});

  final StreakStatus status;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = streakColor(status.kind);
    final first = AppDates.addDays(today, -29);
    return BentoCard(
      key: Key('streak-card-${status.kind.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: streakIcon(status.kind),
            label: status.kind.semanticLabel,
            color: color,
            trailing: status.today == StreakToday.done
                ? 'bugün tamam'
                : 'bugün bekleniyor',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Şimdi',
                  value: '${status.current} gün',
                  semantics: status.semantics,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'En iyi',
                  value: '${status.best} gün',
                  semantics: 'En iyi ${status.best} gün',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Son 30 gün: '
                '${status.days.entries.where((e) => !e.key.isBefore(first) && e.value).length} '
                'gün sayıldı',
            excludeSemantics: true,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < 30; i++)
                  _Dot(
                    color: color,
                    state: () {
                      final day = AppDates.addDays(first, i);
                      if (day == today) {
                        return status.today == StreakToday.done
                            ? _DotState.done
                            : _DotState.pending;
                      }
                      return (status.days[day] ?? false)
                          ? _DotState.done
                          : _DotState.missed;
                    }(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            streakRule(status.kind),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.semantics,
  });

  final String label;
  final String value;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppColors.textSecondary)),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DotState { done, missed, pending }

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.state});

  final Color color;
  final _DotState state;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (state) {
              _DotState.done => color,
              _DotState.missed => AppColors.surfaceHigh,
              _DotState.pending => color.withValues(alpha: 0),
            },
            border: state == _DotState.pending
                ? Border.all(color: color, width: 1.5)
                : null,
          ),
        ),
      );
}

class _WeeksBody extends StatelessWidget {
  const _WeeksBody({required this.weeks});

  final List<WeekDeficit> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = weeks.isEmpty ? 0 : weeks.last.targetKcal;
    final surplus = weeks.isNotEmpty && weeks.last.surplusGoal;
    final met = weeks
        .take(weeks.length - 1)
        .where((w) => w.targetKcal > 0 && w.balanceKcal >= w.targetKcal)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoLabel(
          icon: Icons.calendar_view_week_outlined,
          label: surplus ? 'Haftalık fazla' : 'Haftalık açık',
          color: AppColors.fitness,
          trailing: 'son 8 hafta',
        ),
        const SizedBox(height: 12),
        DayBarChart(
          values: [for (final w in weeks) w.balanceKcal],
          color: AppColors.accent,
          labels: [
            for (final w in weeks)
              '${w.weekStart.day}.${w.weekStart.month.toString().padLeft(2, '0')}',
          ],
          highlightIndex: weeks.length - 1,
          target: target > 0 ? target.toDouble() : null,
          height: 130,
          semanticsLabel: surplus
              ? 'Son 8 haftanın kalori fazlası'
              : 'Son 8 haftanın kalori açığı',
        ),
        const SizedBox(height: 8),
        if (weeks.isNotEmpty)
          Text(
            'Bu hafta ${TodayFormat.weekTotal(weeks.last)}'
            '${target > 0 ? ' / ${TodayFormat.weekTarget(target, surplus: surplus)}' : ''}'
            ' · ${TodayFormat.weekKg(weeks.last)}',
            key: const Key('streak-weeks-current'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (target > 0)
          Text(
            'Geçen 7 haftanın $met tanesinde hedefe ulaştın.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }
}
