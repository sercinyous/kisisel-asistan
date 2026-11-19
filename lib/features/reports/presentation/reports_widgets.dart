import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../kokpit/presentation/kokpit_widgets.dart';
import 'reports_format.dart';
import 'reports_providers.dart';
import 'reports_state.dart';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Dönem seçici: ‹ etiket ›. [onNext] `null` ise ileri gidilemez (gelecek).
class ReportPeriodSwitcher extends StatelessWidget {
  const ReportPeriodSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
    this.caption,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;

  /// Etiketin altındaki kısa not ("Bu hafta", "Bugün").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          tooltip: previousTooltip,
          icon: const Icon(Icons.chevron_left_rounded),
          color: AppColors.textSecondary,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (caption != null)
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: nextTooltip,
          icon: const Icon(Icons.chevron_right_rounded),
          color: AppColors.textSecondary,
          disabledColor: AppColors.border,
        ),
      ],
    );
  }
}

/// Yüzde kartı (İş / Form): büyük yüzde, kısa döküm ve ilerleme çubuğu.
class ReportRateCard extends StatelessWidget {
  const ReportRateCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.rate,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// 0..100; veri yoksa `null`.
  final int? rate;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(icon: icon, label: label, color: color),
          const SizedBox(height: 6),
          Text(
            ReportsFormat.rate(rate),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          KokpitBar(value: (rate ?? 0) / 100, color: color),
        ],
      ),
    );
  }
}

/// Izgaradaki tek sayı: küçük etiket + değer. Dar sütunda küçülür, taşmaz.
class ReportStat extends StatelessWidget {
  const ReportStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style:
                theme.textTheme.titleMedium?.copyWith(fontFeatures: _tabular),
          ),
        ),
      ],
    );
  }
}

/// Üçer sütunluk sayı ızgarası.
class ReportStatGrid extends StatelessWidget {
  const ReportStatGrid({super.key, required this.stats});

  final List<ReportStat> stats;

  @override
  Widget build(BuildContext context) {
    const columns = 3;
    return Column(
      children: [
        for (var start = 0; start < stats.length; start += columns) ...[
          if (start > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: 12),
                Expanded(
                  child: i < stats.length ? stats[i] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Hedefli sayı satırı: etiket, değer, "/ hedef" ve ilerleme çubuğu.
class ReportTargetRow extends StatelessWidget {
  const ReportTargetRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.target,
    this.progress,
  });

  final String label;
  final String value;
  final Color color;

  /// "/ 2.000 kcal"; hedef yoksa `null`.
  final String? target;

  /// 0..1; hedef yoksa `null` (çubuk çizilmez).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style:
                  theme.textTheme.titleMedium?.copyWith(fontFeatures: _tabular),
            ),
            if (target != null) ...[
              const SizedBox(width: 4),
              Text(
                target!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          KokpitBar(value: progress!, color: color, height: 6),
        ],
      ],
    );
  }
}

/// Yapay zekâ değerlendirme kartı. İsteğe bağlı [header] (ör. İş / Form
/// puanları) metnin üstünde durur; uzun yorum 4 satırda kesilir ve "Devamı"
/// ile açılır. Yeniden oluşturma başlıktaki [ReportRefreshButton] ile yapılır;
/// kartta düğme yalnızca rapor yokken ya da son deneme hata verdiyse görünür.
class ReportAiCard extends ConsumerWidget {
  const ReportAiCard({
    super.key,
    required this.kind,
    required this.date,
    required this.title,
    required this.emptyMessage,
    required this.emptyHint,
    required this.exists,
    this.status = ReportAiStatus.pending,
    this.summary,
    this.generatedAt,
    this.header,
  });

  final ReportKind kind;

  /// Dönem başı: haftalıkta Pazartesi, günlükte gün başı.
  final DateTime date;
  final String title;

  /// Rapor yokken gösterilen başlık ve açıklama.
  final String emptyMessage;
  final String emptyHint;

  /// Bu dönem için rapor satırı var mı?
  final bool exists;
  final ReportAiStatus status;
  final String? summary;
  final DateTime? generatedAt;

  /// Yorumun üstünde gösterilen içerik (yalnızca rapor varken).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ReportTarget target = (kind: kind, date: date);
    final busy = ref.watch(
      reportRegenerationProvider.select((s) => s.busy.contains(target)),
    );
    final error = ref.watch(
      reportRegenerationProvider.select((s) => s.errors[target]),
    );
    final text = status == ReportAiStatus.ok ? summary : null;
    final showButton = !exists || error != null;

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (exists && header != null) ...[
            header!,
            const SizedBox(height: 14),
          ],
          BentoLabel(
            icon: Icons.auto_awesome_rounded,
            label: title,
            color: AppColors.accent,
            trailing: 'AI',
          ),
          const SizedBox(height: 10),
          if (!exists)
            _Notice(title: emptyMessage, detail: emptyHint)
          else if (text != null)
            _SummaryText(
              key: ValueKey('summary-$text'),
              parts: ReportsFormat.splitSummary(
                text,
                withSuggestions: kind == ReportKind.weekly,
              ),
            )
          else if (status == ReportAiStatus.pending)
            const _Notice(
              title: 'Yorum hazırlanıyor',
              detail: 'Sayılar hazır. Yorum gelmezse yukarıdaki yenile '
                  'simgesiyle raporu yeniden oluştur.',
            )
          else
            const _Notice(
              title: 'Yorum üretilemedi',
              detail: 'Sayılar kaydedildi. Yorum için yukarıdaki yenile '
                  'simgesiyle raporu yeniden oluştur.',
            ),
          if (exists && generatedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Oluşturuldu: ${AppDates.relativeDayTime(
                generatedAt!,
                now: ref.watch(kokpitClockProvider),
              )}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ],
          if (showButton) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : () => runRegeneration(ref, kind, date),
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Flexible(child: Text('Oluşturuluyor…')),
                      ],
                    )
                  : Text(error != null ? 'Tekrar dene' : 'Raporu oluştur'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Başlıktaki küçük yenile simgesi: seçili dönemin raporunu yeniden üretir.
/// Üretim sürerken döner gösterge çıkar ve dokunulamaz.
class ReportRefreshButton extends ConsumerWidget {
  const ReportRefreshButton({
    super.key,
    required this.kind,
    required this.date,
  });

  final ReportKind kind;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReportTarget target = (kind: kind, date: date);
    final busy = ref.watch(
      reportRegenerationProvider.select((s) => s.busy.contains(target)),
    );
    return IconButton(
      key: const ValueKey('reports-refresh'),
      tooltip: busy ? 'Oluşturuluyor…' : 'Raporu yeniden oluştur',
      onPressed: busy ? null : () => runRegeneration(ref, kind, date),
      color: AppColors.textSecondary,
      icon: busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 22),
    );
  }
}

/// Üst karttaki iki puan (İş %, Form %) yan yana.
class ReportScorePair extends StatelessWidget {
  const ReportScorePair({
    super.key,
    required this.workRate,
    required this.formRate,
  });

  final int? workRate;
  final int? formRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Score(
            label: 'İş',
            rate: workRate,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.grid),
        Expanded(
          child: _Score(
            label: 'Form',
            rate: formRate,
            color: AppColors.fitness,
          ),
        ),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.rate, required this.color});

  final String label;
  final int? rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ReportsFormat.rate(rate),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: color,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(height: 6),
          KokpitBar(value: (rate ?? 0) / 100, color: color),
        ],
      ),
    );
  }
}

/// Tek satırlık dokunulabilir bağlantı kartı ("Ayrıntılar ›").
class ReportLinkRow extends StatelessWidget {
  const ReportLinkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: 14,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          detail,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Yorum metni: kapalıyken 4 satır; sığmıyorsa ya da öneri varsa "Devamı".
class _SummaryText extends StatefulWidget {
  const _SummaryText({super.key, required this.parts});

  final SummaryParts parts;

  @override
  State<_SummaryText> createState() => _SummaryTextState();
}

class _SummaryTextState extends State<_SummaryText> {
  static const int _collapsedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = widget.parts;
    final bodyStyle = theme.textTheme.bodyMedium;
    final muted = bodyStyle?.copyWith(color: AppColors.textSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: parts.body, style: bodyStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: _collapsedLines,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        final canExpand = overflows || parts.suggestions.isNotEmpty;
        final open = _expanded || !canExpand;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parts.body,
              style: bodyStyle,
              maxLines: open ? null : _collapsedLines,
              overflow: open ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (open)
              for (final suggestion in parts.suggestions)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•', style: muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(suggestion, style: muted)),
                    ],
                  ),
                ),
            if (canExpand)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(_expanded ? 'Daha az' : 'Devamı'),
              ),
          ],
        );
      },
    );
  }
}

/// [ReportListCard] satırı.
class ReportListEntry {
  const ReportListEntry({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key key;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// Geçmiş raporların dokunulabilir listesi (tek kart, ayraçlı satırlar).
class ReportListCard extends StatelessWidget {
  const ReportListCard({super.key, required this.icon, required this.entries});

  final IconData icon;
  final List<ReportListEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 0.5,
                indent: AppSpacing.cardPadding,
                endIndent: AppSpacing.cardPadding,
              ),
            InkWell(
              key: entry.key,
              onTap: entry.onTap,
              child: ConstrainedBox(
                // Dokunma hedefi en az 44pt.
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.cardPadding,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: AppColors.ops),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              entry.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontFeatures: _tabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
