import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/goal_rules.dart';
import 'health_format.dart';
import 'health_widgets.dart';
import 'trend_chart.dart';
import 'trend_providers.dart';

/// Adım, uyku ve kalori için hafta/ay trendi: hedef tutturma sayısı, yüzde,
/// ortalama, seri ve günlük çubuk grafik. Verisi olmayan gün hiçbir yerde
/// "tutturamadı" sayılmaz ([TrendStats]).
class TrendScreen extends ConsumerStatefulWidget {
  const TrendScreen({super.key, this.initialMetric = TrendMetric.steps});

  final TrendMetric initialMetric;

  /// Ekranı açar. Önbellekteki dönem sonuçları açılışta boşaltılır: kart
  /// görüntülendikten sonra eklenen öğün ya da eşitlenen adım eski sayıyla
  /// görünmesin.
  static Future<void> open(BuildContext context, TrendMetric metric) {
    invalidateTrendData(ProviderScope.containerOf(context, listen: false));
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrendScreen(initialMetric: metric),
      ),
    );
  }

  @override
  ConsumerState<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends ConsumerState<TrendScreen>
    with WidgetsBindingObserver {
  late TrendMetric _metric = widget.initialMetric;
  TrendPeriod _period = TrendPeriod.week;
  late DateTime _today;
  late DateTime _anchor;

  DateTime _readToday() =>
      AppDates.startOfDay(ref.read(trendClockProvider)());

  TrendQuery get _query =>
      TrendQuery(metric: _metric, period: _period, anchor: _anchor);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = _readToday();
    _anchor = _today;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Arka plandan dönüşte sonuçlar yeniden okunur; gece yarısı geçmişse ve
  /// kullanıcı geçerli dönemdeyse görünüm yeni güne taşınır (bugün/dün).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = _readToday();
    invalidateTrendData(ProviderScope.containerOf(context, listen: false));
    if (today == _today) return;
    setState(() {
      final wasCurrent = _query.isCurrent(_today);
      _today = today;
      if (wasCurrent) _anchor = today;
    });
  }

  /// Geçerli döneme gelinince çapa bugüne alınır ki hafta/ay anahtarı ile
  /// "bugün" tutarlı kalsın.
  void _select({TrendMetric? metric, TrendPeriod? period, DateTime? anchor}) {
    setState(() {
      _metric = metric ?? _metric;
      _period = period ?? _period;
      _anchor = anchor ?? _anchor;
      if (_query.isCurrent(_today)) _anchor = _today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query;
    final isCurrent = query.isCurrent(_today);

    return Scaffold(
      appBar: AppBar(title: const Text('Trend')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            8,
            AppSpacing.page,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<TrendMetric>(
                key: const Key('trend-metric'),
                showSelectedIcon: false,
                segments: [
                  for (final m in TrendMetric.values)
                    ButtonSegment(value: m, label: Text(trendMetricLabel(m))),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => _select(metric: s.first),
                style: _segmentStyle(),
              ),
              const SizedBox(height: 10),
              SegmentedButton<TrendPeriod>(
                key: const Key('trend-period'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TrendPeriod.week, label: Text('Hafta')),
                  ButtonSegment(value: TrendPeriod.month, label: Text('Ay')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => _select(period: s.first),
                style: _segmentStyle(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    key: const Key('trend-prev'),
                    tooltip: 'Önceki dönem',
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: AppColors.textSecondary,
                    onPressed: () =>
                        _select(anchor: query.shifted(-1).anchor),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel(query),
                      key: const Key('trend-period-label'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('trend-next'),
                    tooltip: 'Sonraki dönem',
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: AppColors.textSecondary,
                    // Gelecek döneme gidilmez.
                    onPressed: isCurrent
                        ? null
                        : () => _select(anchor: query.shifted(1).anchor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _TrendBody(query: query, today: _today),
            ],
          ),
        ),
      ),
    );
  }
}

ButtonStyle _segmentStyle() => SegmentedButton.styleFrom(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textSecondary,
      selectedBackgroundColor: AppColors.surfaceHigh,
      selectedForegroundColor: AppColors.accent,
      side: BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.inner),
      ),
    );

/// "16–22 Kas 2026", "30 Kas – 6 Ara 2026", "Kasım 2026".
String _periodLabel(TrendQuery query) {
  if (query.period == TrendPeriod.month) {
    return DateFormat('MMMM y', AppDates.locale).format(query.from);
  }
  final from = query.from;
  final to = query.to;
  final withYear = DateFormat('d MMM y', AppDates.locale);
  final noYear = DateFormat('d MMM', AppDates.locale);
  if (from.year != to.year) {
    return '${withYear.format(from)} – ${withYear.format(to)}';
  }
  if (from.month != to.month) {
    return '${noYear.format(from)} – ${withYear.format(to)}';
  }
  return '${from.day}–${withYear.format(to)}';
}

class _TrendBody extends ConsumerWidget {
  const _TrendBody({required this.query, required this.today});

  final TrendQuery query;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(trendStatsProvider(query));
    return stats.when(
      skipLoadingOnRefresh: true,
      loading: () => const BentoCard(child: HealthCardLoading(height: 260)),
      error: (_, __) => BentoCard(
        child: HealthCompactMessage(
          text: 'Trend verisi yüklenemedi.',
          onRetry: () => invalidateTrendData(
            ProviderScope.containerOf(context, listen: false),
          ),
        ),
      ),
      data: (data) => _TrendData(query: query, stats: data, today: today),
    );
  }
}

class _TrendData extends ConsumerWidget {
  const _TrendData({
    required this.query,
    required this.stats,
    required this.today,
  });

  final TrendQuery query;
  final TrendStats stats;
  final DateTime today;

  TrendMetric get _metric => query.metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasValues = stats.days.any((d) => d.value != null);
    if (!hasValues) return _EmptyCard(metric: _metric);

    final settings = ref.watch(settingsOrDefaultProvider);
    final target = trendTarget(_metric, settings);
    final color = trendMetricColor(_metric);
    final past = stats.currentStreak == null;

    return BentoGrid(
      children: [
        BentoCell(
          child: _SummaryCard(query: query, stats: stats, today: today),
        ),
        BentoCell(
          child: _ChartCard(
            stats: stats,
            metric: _metric,
            target: target,
            today: today,
          ),
        ),
        BentoCell(
          span: 1,
          child: _AverageCard(query: query, stats: stats),
        ),
        BentoCell(
          span: 1,
          child: _StatCard(
            icon: Icons.bolt_rounded,
            label: 'Seri',
            valueKey: const Key('trend-streak'),
            value: stats.dataDays == 0
                ? KokpitFormat.none
                : '${past ? stats.longestStreak : stats.currentStreak} gün',
            captions: [
              if (stats.dataDays == 0)
                'Henüz değerlendirilen gün yok'
              else if (past)
                'Bu dönemin en uzun serisi'
              else
                'Mevcut seri · en uzun ${stats.longestStreak} gün',
            ],
            color: color,
          ),
        ),
        // Protein hedefi 0 = takip yok: satır hiç çıkmaz. Aksi halde hedefsiz
        // "0/N gün" yazardı; Raporlar ise aynı günleri tutmuş sayardı.
        if (_metric == TrendMetric.calories && settings.dailyProteinG > 0)
          BentoCell(child: _ProteinCard(query: query)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.metric});

  final TrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: trendMetricIcon(metric),
            label: trendMetricLabel(metric),
            color: trendMetricColor(metric),
          ),
          const SizedBox(height: 12),
          Text('Bu dönemde veri yok', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            metric == TrendMetric.calories
                ? 'Öğün ekledikçe günlük kalori burada görünür.'
                : 'Adım ve uyku verisi Apple Health ya da Google Health '
                    'bağlıyken uygulama açıldıkça eşitlenir.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.query,
    required this.stats,
    required this.today,
  });

  final TrendQuery query;
  final TrendStats stats;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metric = query.metric;
    final color = trendMetricColor(metric);
    final percent = stats.percent;
    final pastNoData = stats.days
        .where((d) => d.status == DayStatus.noData && d.day != today)
        .length;
    final inProgress = stats.days.any((d) => d.status == DayStatus.inProgress);
    final notes = [
      if (stats.dataDays == 0) 'Henüz değerlendirilen gün yok.',
      if (inProgress) 'Bugün devam ediyor, hesaba girmedi.',
      if (pastNoData > 0) '$pastNoData gün veri yok, hesaba girmedi.',
    ];

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: trendMetricIcon(metric),
            label: 'Hedefi tutturma',
            color: color,
            trailing: trendMetricLabel(metric),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HealthBigValue(
                key: const Key('trend-hit-count'),
                value: stats.dataDays == 0
                    ? KokpitFormat.none
                    : '${stats.hitDays}/${stats.dataDays}',
                unit: 'gün hedefte',
                large: true,
              ),
              if (percent != null)
                HealthChip(
                  '%${(percent * 100).round()}',
                  key: const Key('trend-percent'),
                  color: color,
                ),
            ],
          ),
          for (final note in notes) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.stats,
    required this.metric,
    required this.target,
    required this.today,
  });

  final TrendStats stats;
  final TrendMetric metric;
  final int target;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = trendMetricColor(metric);
    final muted =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted);
    final hasInProgress =
        stats.days.any((d) => d.status == DayStatus.inProgress);

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(icon: Icons.bar_chart_rounded, label: 'Günlük'),
          const SizedBox(height: 10),
          TrendBarChart(
            stats: stats,
            target: target,
            metric: metric,
            today: today,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _LegendItem(color: color, label: 'Hedefte'),
              _LegendItem(
                color: color.withValues(alpha: 0.35),
                label: 'Hedef dışı',
              ),
              if (hasInProgress)
                _LegendItem(color: color, label: 'Devam ediyor', ring: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(trendGoalCaption(metric, target), style: muted),
          Text('Boş sütun: veri yok ya da gelecek gün.', style: muted),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.ring = false,
  });

  final Color color;
  final String label;

  /// Dolu nokta yerine içi boş halka (bugün, henüz değerlendirilmiyor).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring ? null : color,
            border: ring ? Border.all(color: color, width: 1.5) : null,
          ),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AverageCard extends ConsumerWidget {
  const _AverageCard({required this.query, required this.stats});

  final TrendQuery query;
  final TrendStats stats;

  /// "+820", "−1 sa 5 dk", "+120 kcal"; tipografik eksi (U+2212).
  String _signed(TrendMetric metric, double delta) {
    final sign = delta < 0 ? '−' : '+';
    final magnitude = delta.abs();
    return switch (metric) {
      TrendMetric.steps => '$sign${HealthFormat.count(magnitude)}',
      TrendMetric.sleep => '$sign${_sleepDelta(magnitude.round())}',
      TrendMetric.calories => '$sign${HealthFormat.count(magnitude)} kcal',
    };
  }

  /// "22 dk", "1 sa", "1 sa 5 dk" (süre farkı; başa "0 sa" yazılmaz).
  String _sleepDelta(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest dk';
    return rest == 0 ? '$hours sa' : '$hours sa $rest dk';
  }

  String? _comparison(double? average, double? previous) {
    if (average == null || previous == null) return null;
    final delta = average - previous;
    final week = query.period == TrendPeriod.week;
    if (delta.abs().round() == 0) {
      return week ? 'Önceki haftayla aynı' : 'Önceki ayla aynı';
    }
    final label = week ? 'haftaya' : 'aya';
    return 'Önceki $label göre ${_signed(query.metric, delta)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final average = stats.average;
    final previous =
        ref.watch(trendStatsProvider(query.shifted(-1))).valueOrNull?.average;
    final comparison = _comparison(average, previous);

    return _StatCard(
      icon: Icons.show_chart_rounded,
      label: 'Ortalama',
      valueKey: const Key('trend-average'),
      value: average == null
          ? KokpitFormat.none
          : formatTrendValue(query.metric, average),
      captions: [
        'Veri olan günlerin ortalaması',
        if (comparison != null) comparison,
      ],
      color: trendMetricColor(query.metric),
    );
  }
}

class _ProteinCard extends ConsumerWidget {
  const _ProteinCard({required this.query});

  final TrendQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final protein = ref.watch(trendProteinStatsProvider(query));
    final settings = ref.watch(settingsOrDefaultProvider);

    final value = protein.when(
      skipLoadingOnRefresh: true,
      loading: () => KokpitFormat.none,
      error: (_, __) => KokpitFormat.none,
      data: (s) => s.dataDays == 0
          ? KokpitFormat.none
          : '${s.hitDays}/${s.dataDays} gün',
    );

    return BentoCard(
      child: Row(
        children: [
          Icon(Icons.egg_alt_rounded, size: 16, color: AppColors.nutrition),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protein hedefi', style: theme.textTheme.titleSmall),
                Text(
                  'Günlük ${settings.dailyProteinG} g hedefin en az '
                  '%${GoalRules.proteinMinPercent}\'ı',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            key: const Key('trend-protein-days'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Küçük bilgi kartı: etiket, büyük değer, altında açıklama satırları.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.captions,
    required this.color,
    this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> captions;
  final Color color;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: icon, label: label, color: color),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          for (final caption in captions) ...[
            const SizedBox(height: 4),
            Text(
              caption,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
