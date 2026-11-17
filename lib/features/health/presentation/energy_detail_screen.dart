import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/settings_providers.dart';
import 'energy_providers.dart';
import 'health_format.dart';
import 'health_widgets.dart';
import 'trend_providers.dart';

/// "−410", "+300", "0": tipografik eksi (U+2212), binlik ayraçlı.
String formatEnergyNet(double net) {
  final rounded = net.round();
  if (rounded == 0) return '0';
  final sign = rounded < 0 ? '−' : '+';
  return '$sign${HealthFormat.count(rounded.abs())}';
}

/// "−0,05 kg", "+0,3 kg"; yuvarlanınca sıfırsa "0 kg".
String _formatFatKg(double kg) {
  final rounded = (kg * 100).round() / 100;
  if (rounded == 0) return '0 kg';
  final sign = rounded < 0 ? '−' : '+';
  return '$sign${HealthFormat.plain(rounded.abs())} kg';
}

/// Grafiğin iki görünümü: günlük net çubuklar ya da alınan/yakılan çizgileri.
enum _EnergyView { net, lines }

/// Enerji dengesinin hafta/ay detayı: toplam net ve tahmini yağ değişimi
/// ("N gün üzerinden"), günlük net çubuk grafiği (sıfır çizgisi; açık mint
/// aşağı, fazla amber yukarı) ve "Alınan / Yakılan" çizgi görünümü.
///
/// Yalnızca öğünü olan günler sayılır; öğünsüz gün boş kalır, gelecek günler
/// hesaba girmez. Yağ değişimi bir tahmindir.
class EnergyDetailScreen extends ConsumerStatefulWidget {
  const EnergyDetailScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EnergyDetailScreen()),
      );

  @override
  ConsumerState<EnergyDetailScreen> createState() => _EnergyDetailScreenState();
}

class _EnergyDetailScreenState extends ConsumerState<EnergyDetailScreen>
    with WidgetsBindingObserver {
  TrendPeriod _period = TrendPeriod.week;
  _EnergyView _view = _EnergyView.net;
  late DateTime _today;
  late DateTime _anchor;

  DateTime _readToday() =>
      AppDates.startOfDay(ref.read(trendClockProvider)());

  // Dönem günleri için ortak pencere hesabı; metrik yalnızca zorunlu alandır.
  TrendQuery get _window => TrendQuery(
        metric: TrendMetric.calories,
        period: _period,
        anchor: _anchor,
      );

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
  /// kullanıcı geçerli dönemdeyse görünüm yeni güne taşınır (bugün/dün,
  /// bazal oranı).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final today = _readToday();
    invalidateEnergyData(ProviderScope.containerOf(context, listen: false));
    if (today == _today) return;
    setState(() {
      final wasCurrent = _window.isCurrent(_today);
      _today = today;
      if (wasCurrent) _anchor = today;
    });
  }

  /// Geçerli döneme gelinince çapa bugüne alınır ki hafta/ay anahtarı ile
  /// "bugün" tutarlı kalsın.
  void _select({TrendPeriod? period, DateTime? anchor}) {
    setState(() {
      _period = period ?? _period;
      _anchor = anchor ?? _anchor;
      if (_window.isCurrent(_today)) _anchor = _today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = _window;
    final isCurrent = window.isCurrent(_today);

    return Scaffold(
      appBar: AppBar(title: const Text('Enerji dengesi')),
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
              SegmentedButton<TrendPeriod>(
                key: const Key('energy-period'),
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
                    key: const Key('energy-prev'),
                    tooltip: 'Önceki dönem',
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: AppColors.textSecondary,
                    onPressed: () =>
                        _select(anchor: window.shifted(-1).anchor),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel(window),
                      key: const Key('energy-period-label'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const Key('energy-next'),
                    tooltip: 'Sonraki dönem',
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: AppColors.textSecondary,
                    // Gelecek döneme gidilmez.
                    onPressed: isCurrent
                        ? null
                        : () => _select(anchor: window.shifted(1).anchor),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _DetailBody(
                window: window,
                today: _today,
                view: _view,
                onView: (view) => setState(() => _view = view),
              ),
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

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.window,
    required this.today,
    required this.view,
    required this.onView,
  });

  final TrendQuery window;
  final DateTime today;
  final _EnergyView view;
  final ValueChanged<_EnergyView> onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userSettingsProvider).valueOrNull;
    if (profile != null && !profile.profileComplete) {
      return const _NoticeCard(
        title: 'Profil eksik',
        text: 'Dengeyi hesaplamak için boy, yaş ve cinsiyet gerekli. '
            'Ayarlar > Profil bölümünden doldurabilirsin.',
      );
    }
    final energy =
        ref.watch(energyRangeProvider((from: window.from, to: window.to)));
    return energy.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const BentoCard(child: HealthCardLoading(height: 260)),
      error: (_, __) => BentoCard(
        child: HealthCompactMessage(
          text: 'Enerji dengesi yüklenemedi.',
          onRetry: () {
            ref
              ..invalidate(userSettingsProvider)
              ..invalidate(energyRangeProvider);
          },
        ),
      ),
      data: (days) => _DetailData(
        window: window,
        today: today,
        days: days,
        view: view,
        onView: onView,
      ),
    );
  }
}

class _DetailData extends StatelessWidget {
  const _DetailData({
    required this.window,
    required this.today,
    required this.days,
    required this.view,
    required this.onView,
  });

  final TrendQuery window;
  final DateTime today;
  final List<EnergyDay> days;
  final _EnergyView view;
  final ValueChanged<_EnergyView> onView;

  @override
  Widget build(BuildContext context) {
    final summary = summarize(days);
    if (summary.days == 0) {
      return const _NoticeCard(
        title: 'Bu dönemde öğün girilmiş gün yok',
        text: 'Öğün ekledikçe günlük denge burada görünür.',
      );
    }

    final byDay = {for (final d in days) d.day: d};
    final underAge = days.any((d) => d.verdict == EnergyVerdict.underAge);
    final hasVeryHigh =
        days.any((d) => d.verdict == EnergyVerdict.veryHighDeficit);
    return BentoGrid(
      children: [
        BentoCell(
          child: _SummaryCard(
            window: window,
            days: days,
            summary: summary,
            underAge: underAge,
            hasVeryHigh: hasVeryHigh,
          ),
        ),
        BentoCell(
          child: _ChartCard(
            window: window,
            today: today,
            byDay: byDay,
            underAge: underAge,
            hasVeryHigh: hasVeryHigh,
            view: view,
            onView: onView,
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.bolt_rounded,
            label: 'Enerji dengesi',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            text,
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
    required this.window,
    required this.days,
    required this.summary,
    required this.underAge,
    required this.hasVeryHigh,
  });

  final TrendQuery window;
  final List<EnergyDay> days;
  final EnergyRangeSummary summary;
  final bool underAge;

  /// Dönemde çok yüksek kalori açığı olan gün var: yağ tahmini övülmez.
  final bool hasVeryHigh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fat = summary.estimatedFatKg;
    final fatRounded = (fat * 100).round();
    // Çok yüksek açık günü olan dönemde eksi yağ tahmini mint (olumlu) boyanmaz.
    final fatColor = hasVeryHigh
        ? null
        : fatRounded < 0
            ? AppColors.accent
            : fatRounded > 0
                ? AppColors.warning
                : null;
    final todayCounted = days.any((d) => d.isToday && d.net != null);
    final uncounted = days
        .where((d) => d.verdict == EnergyVerdict.noMeals && !d.isToday)
        .length;
    final notes = [
      if (underAge)
        'Yorum ve yağ tahmini 18 yaşın altında gösterilmez.'
      else
        'Tahmindir: ${HealthFormat.count(EnergyBands.kcalPerKgFat)} kcal '
            '≈ 1 kg yağ varsayımıyla hesaplanır.',
      if (!underAge && hasVeryHigh)
        'Çok yüksek açık günleri var: yeterince yediğinden emin ol.',
      if (todayCounted) 'Bugün şu ana kadarki değerle sayıldı.',
      if (uncounted > 0) '$uncounted gün öğün girilmediği için sayılmadı.',
    ];

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.swap_vert_rounded,
            label: 'Toplam net',
            color: AppColors.fitness,
            trailing: window.period == TrendPeriod.week ? 'Hafta' : 'Ay',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HealthBigValue(
                key: const Key('energy-sum-net'),
                value: formatEnergyNet(summary.sumNet),
                unit: 'kcal',
                large: true,
              ),
              if (!underAge)
                HealthChip(
                  'Tahmini yağ: ${_formatFatKg(fat)}',
                  key: const Key('energy-fat'),
                  color: fatColor,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.days} gün üzerinden',
            key: const Key('energy-sum-days'),
            style: theme.textTheme.titleSmall,
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
    required this.window,
    required this.today,
    required this.byDay,
    required this.underAge,
    required this.hasVeryHigh,
    required this.view,
    required this.onView,
  });

  final TrendQuery window;
  final DateTime today;
  final Map<DateTime, EnergyDay> byDay;
  final bool underAge;
  final bool hasVeryHigh;
  final _EnergyView view;
  final ValueChanged<_EnergyView> onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted);
    final days = window.days;
    final todayHasValue = byDay[today]?.net != null;
    final isNet = view == _EnergyView.net;

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(icon: Icons.bar_chart_rounded, label: 'Günlük'),
          const SizedBox(height: 10),
          SegmentedButton<_EnergyView>(
            key: const Key('energy-view'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _EnergyView.net, label: Text('Net')),
              ButtonSegment(
                value: _EnergyView.lines,
                label: Text('Alınan / Yakılan', maxLines: 1),
              ),
            ],
            selected: {view},
            onSelectionChanged: (s) => onView(s.first),
            style: _segmentStyle(),
          ),
          const SizedBox(height: 14),
          if (isNet)
            _NetChart(
              days: days,
              byDay: byDay,
              today: today,
              neutral: underAge,
            )
          else
            _LinesChart(days: days, byDay: byDay, today: today),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (isNet && !underAge) ...[
                _LegendItem(color: AppColors.accent, label: 'Açık'),
                _LegendItem(color: AppColors.warning, label: 'Fazla'),
                if (hasVeryHigh)
                  _LegendItem(
                    color: AppColors.warning,
                    label: 'Çok yüksek açık',
                  ),
              ] else if (isNet)
                _LegendItem(color: AppColors.textMuted, label: 'Net'),
              if (!isNet) ...[
                _LegendItem(color: AppColors.nutrition, label: 'Alınan'),
                _LegendItem(color: AppColors.fitness, label: 'Yakılan'),
              ],
              if (isNet && todayHasValue)
                _LegendItem(
                  color: underAge ? AppColors.textMuted : AppColors.accent,
                  label: 'Bugün, şu ana kadar',
                  ring: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isNet
                ? 'Sıfır çizgisi: alınan = yakılan. Boş sütun: öğün '
                    'girilmemiş ya da gelecek gün.'
                : 'Çizgiler yalnızca öğünü olan günleri gösterir.',
            style: muted,
          ),
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

  /// Dolu nokta yerine içi boş halka (bugün, henüz tamamlanmadı).
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

/// Grafik sütunlarının altındaki gün etiketi: haftada gün kısaltması, ayda
/// 1, 5, 10, ... (31 sütunun etiketi sığmaz).
Widget _dayTitle(
  BuildContext context,
  List<DateTime> days,
  DateTime today,
  double value,
  TitleMeta meta,
) {
  final index = value.round();
  if (index < 0 || index >= days.length) return const SizedBox.shrink();
  final day = days[index];
  final highlight = day == today;
  if (days.length <= 7) {
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: HealthWeekdayLabel(day, highlight: highlight),
    );
  }
  if (day.day != 1 && day.day % 5 != 0) return const SizedBox.shrink();
  return SideTitleWidget(
    meta: meta,
    space: 6,
    child: Text(
      '${day.day}',
      maxLines: 1,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: highlight ? AppColors.textPrimary : AppColors.textMuted,
          ),
    ),
  );
}

FlTitlesData _titles(
  BuildContext context,
  List<DateTime> days,
  DateTime today,
) =>
    FlTitlesData(
      show: true,
      leftTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      topTitles: const AxisTitles(),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: 1,
          getTitlesWidget: (value, meta) =>
              _dayTitle(context, days, today, value, meta),
        ),
      ),
    );

String _tooltipDate(DateTime day) =>
    DateFormat('d MMM EEE', AppDates.locale).format(day);

/// Günlük net: sıfır çizgisinin altı açık (mint), üstü fazla (amber). Bugünün
/// çubuğu içi boş çerçevedir ("şu ana kadar"); öğünsüz ve gelecek günler boş.
class _NetChart extends StatelessWidget {
  const _NetChart({
    required this.days,
    required this.byDay,
    required this.today,
    required this.neutral,
  });

  static const double _height = 200;

  final List<DateTime> days;
  final Map<DateTime, EnergyDay> byDay;
  final DateTime today;

  /// 18 yaş altı: açık/fazla anlamı verilmez, tek nötr renk kullanılır.
  final bool neutral;

  double? _net(DateTime day) => byDay[day]?.net;

  /// Çok yüksek açık da uyarı rengidir (kartla aynı): mint "iyi gidiyor"
  /// anlamı taşır, aşırı kısıtlama övülmez. Yönü çubuğun aşağı/yukarı oluşu
  /// ayırır.
  Color _color(DateTime day, double net) => neutral
      ? AppColors.textMuted
      : byDay[day]?.verdict == EnergyVerdict.veryHighDeficit
          ? AppColors.warning
          : net < 0
              ? AppColors.accent
              : AppColors.warning;

  String get _semanticsLabel {
    final entries = [
      for (final day in days)
        if (_net(day) case final net?)
          '${DateFormat('d MMMM EEEE', AppDates.locale).format(day)} '
              'net ${formatEnergyNet(net)} kcal'
              '${day == today ? ', şu ana kadar' : ''}',
    ];
    return 'Günlük net enerji grafiği. '
        '${entries.isEmpty ? 'Veri yok.' : entries.join('. ')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMonth = days.length > 7;
    final barWidth = isMonth ? 6.0 : 18.0;
    final radius = BorderRadius.circular(barWidth / 3);

    var high = 0.0;
    var low = 0.0;
    for (final day in days) {
      final net = _net(day);
      if (net == null) continue;
      high = math.max(high, net);
      low = math.min(low, net);
    }
    final pad = high - low == 0 ? 1.0 : (high - low) * 0.12;
    final maxY = high + pad;
    final minY = low - pad;

    BarChartRodData rod(DateTime day) {
      final net = _net(day);
      if (net == null) {
        return BarChartRodData(
          toY: 0,
          width: barWidth,
          color: AppColors.textMuted.withValues(alpha: 0),
        );
      }
      final color = _color(day, net);
      if (day == today) {
        return BarChartRodData(
          fromY: 0,
          toY: net,
          width: barWidth,
          borderRadius: radius,
          color: color.withValues(alpha: 0.12),
          borderSide:
              BorderSide(color: color.withValues(alpha: 0.8), width: 1.5),
        );
      }
      return BarChartRodData(
        fromY: 0,
        toY: net,
        width: barWidth,
        borderRadius: radius,
        color: color,
      );
    }

    return Semantics(
      label: _semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: _height,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: minY,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: _titles(context, days, today),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: AppColors.textSecondary,
                    strokeWidth: 1,
                  ),
                ],
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => AppColors.inverseSurface,
                  getTooltipItem: (group, _, __, ___) {
                    final day = days[group.x];
                    if (day.isAfter(today)) return null;
                    final net = _net(day);
                    final text = net == null
                        ? '${_tooltipDate(day)}\nöğün yok'
                        : '${_tooltipDate(day)}\n'
                            'Net ${formatEnergyNet(net)} kcal'
                            '${day == today ? ' · şu ana kadar' : ''}';
                    return BarTooltipItem(
                      text,
                      TextStyle(
                        color: AppColors.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final (index, day) in days.indexed)
                  BarChartGroupData(x: index, barRods: [rod(day)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alınan ve yakılan kcal çizgileri. Yalnızca öğünü olan günler çizilir;
/// aradaki öğünsüz gün çizgiyi böler, tek kalan gün nokta olarak görünür.
class _LinesChart extends StatelessWidget {
  const _LinesChart({
    required this.days,
    required this.byDay,
    required this.today,
  });

  static const double _height = 200;

  final List<DateTime> days;
  final Map<DateTime, EnergyDay> byDay;
  final DateTime today;

  EnergyDay? _counted(DateTime day) {
    final entry = byDay[day];
    return entry == null || entry.net == null ? null : entry;
  }

  String get _semanticsLabel {
    final entries = [
      for (final day in days)
        if (_counted(day) case final entry?)
          '${DateFormat('d MMMM EEEE', AppDates.locale).format(day)} '
              'alınan ${HealthFormat.kcal(entry.intake ?? 0)}, '
              'yakılan ${HealthFormat.kcal(entry.burned)}'
              '${day == today ? ', şu ana kadar' : ''}',
    ];
    return 'Alınan ve yakılan enerji grafiği. '
        '${entries.isEmpty ? 'Veri yok.' : entries.join('. ')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMonth = days.length > 7;
    var top = 0.0;
    for (final day in days) {
      final entry = _counted(day);
      if (entry == null) continue;
      top = math.max(top, math.max(entry.intake ?? 0, entry.burned));
    }
    final maxY = top <= 0 ? 1.0 : top * 1.12;

    LineChartBarData line(Color color, double Function(EnergyDay) pick) =>
        LineChartBarData(
          spots: [
            for (final (index, day) in days.indexed)
              if (_counted(day) case final entry?)
                FlSpot(index.toDouble(), pick(entry))
              else
                FlSpot.nullSpot,
          ],
          color: color,
          barWidth: 2.2,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          dotData: FlDotData(
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              color: color,
              radius: isMonth ? 2.2 : 3.5,
              strokeWidth: 0,
            ),
          ),
        );

    return Semantics(
      label: _semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: _height,
          child: LineChart(
            LineChartData(
              minX: -0.5,
              maxX: days.length - 0.5,
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: _titles(context, days, today),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => AppColors.inverseSurface,
                  getTooltipItems: (touched) => [
                    for (final spot in touched)
                      LineTooltipItem(
                        '${_tooltipDate(days[spot.x.round()])}\n'
                        '${spot.barIndex == 0 ? 'Alınan' : 'Yakılan'} '
                        '${HealthFormat.kcal(spot.y)}',
                        TextStyle(
                          color: AppColors.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                line(AppColors.nutrition, (e) => e.intake ?? 0),
                line(AppColors.fitness, (e) => e.burned),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
