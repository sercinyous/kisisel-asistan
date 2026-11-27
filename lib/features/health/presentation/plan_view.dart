import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/profile_goals_page.dart';
import '../../settings/presentation/settings_providers.dart';
import '../domain/checkin.dart';
import '../domain/energy_balance.dart';
import '../domain/fat_loss_plan.dart';
import '../domain/fat_loss_rate.dart';
import '../domain/goal_projection.dart';
import '../domain/health_sources.dart';
import 'diet_preset_card.dart';
import 'health_format.dart';
import 'health_widgets.dart';
import 'providers/targets_providers.dart';
import 'today/today_common.dart' show TodayFormat;
import 'water_providers.dart' show formatWaterMl, waterTodayProvider;
import 'trend_providers.dart' show trendClockProvider;
import 'weight_sheets.dart';

const String planDisclaimer =
    'Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.';

const String planApproxNote =
    'Yaklaşık değerler; pişmiş 100 g besin değerleriyle hesaplandı.';

const String menuUnderNote =
    'Menü hedefin altında; porsiyonları biraz artırabilirsin.';

const String supplementDisclaimer =
    'Genel bilgilendirmedir; takviye başlamadan önce doktoruna/eczacına '
    'danış. Hamilelik, emzirme ve kronik hastalıkta farklıdır.';

const String planExpenditureError = '1200–6000 arası gir';

const String planSaveError =
    'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

/// Plan ayar yazımı: hata olursa snackbar gösterir (sessizce kaybolmaz).
Future<void> guardedPlanWrite(
  BuildContext context,
  Future<Object?> Function() write,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await write();
  } on Object {
    messenger.showSnackBar(const SnackBar(content: Text(planSaveError)));
  }
}

/// Her tempo seçeneğinin bugünkü ayar ve kiloyla sonucu (Tempo listesinde
/// her seçeneğin kalorisi gösterilir).
final tempoOptionsProvider =
    FutureProvider<Map<FatLossRate, ResolvedTargets>>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final weight = await ref.watch(latestWeightProvider.future);
  final now = ref.watch(trendClockProvider)();
  return {
    for (final r in FatLossRate.values)
      r: resolveTargets(
        settings: settings.copyWith(weeklyRate: r),
        latestWeightKg: weight?.weightKg,
        age: ageFromSettings(settings, now),
        sex: Sex.tryParse(settings.sex),
      ),
  };
});

/// Her hedef türünün bugünkü ayar ve kiloyla projeksiyonu (Hedef türü
/// kartındaki karşılaştırma).
final goalProjectionsProvider =
    FutureProvider<List<GoalProjection>>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  final weight = await ref.watch(latestWeightProvider.future);
  final now = ref.watch(trendClockProvider)();
  return projectGoals(
    settings: settings,
    latestWeightKg: weight?.weightKg,
    age: ageFromSettings(settings, now),
    sex: Sex.tryParse(settings.sex),
  );
});

Color rateHealthColor(RateHealth h) => switch (h) {
      RateHealth.sustainable => AppColors.accent,
      RateHealth.fast => AppColors.warning,
      RateHealth.aggressive => AppColors.danger,
    };

/// Sağlık > Plan: hedef, günlük hedefler, tempo, açıklama, rehber, ölçü günü
/// ve elle ayar bağlantısı.
class PlanView extends ConsumerWidget {
  const PlanView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(resolvedTargetsProvider);
    return resolved.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const HealthCardLoading(height: 240),
      error: (_, __) => BentoGrid(children: [
        BentoCell(
          child: BentoCard(
            key: const Key('plan-retry'),
            child: HealthCompactMessage(
              text: 'Plan yüklenemedi.',
              onRetry: () => ref
                ..invalidate(userSettingsProvider)
                ..invalidate(resolvedTargetsProvider),
            ),
          ),
        ),
      ]),
      data: (r) => _PlanBody(resolved: r),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.resolved});

  final ResolvedTargets resolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eski şemada hedef türü sütunları yoksa seçim kaydedilemez: kart gizli.
    final goalModeColumns =
        ref.watch(userSettingsProvider).valueOrNull?.goalModeColumns ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoGrid(children: [
          BentoCell(child: _GoalCard(resolved: resolved)),
          if (goalModeColumns)
            BentoCell(child: _GoalModeCard(resolved: resolved)),
          BentoCell(child: _TargetsCard(resolved: resolved)),
          const BentoCell(child: DietPresetCard()),
          if (!resolved.locked && resolved.goal == GoalMode.fatLoss)
            BentoCell(child: _TempoCard(resolved: resolved)),
          BentoCell(child: _WhyCard(resolved: resolved)),
          BentoCell(child: _GuideCard(resolved: resolved)),
          const BentoCell(child: _CheckinCard()),
          BentoCell(
            child: BentoCard(
              key: const Key('plan-manual-link'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ProfileGoalsPage()),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hedefleri elle ayarla',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          planDisclaimer,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Renkli küçük rozet.
class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.text, this.color});

  final String text;

  /// Verilmezse gri seçim dolgusu ve ikincil metin.
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.10) ?? AppColors.selection,
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color ?? AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Hedefim

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.resolved});

  final ResolvedTargets resolved;

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final write = await ref
          .read(planControllerProvider)
          .applyPlan(PlanTrigger.suggestionApplied);
      messenger.showSnackBar(SnackBar(
        content: Text(write?.message ?? 'Hedeflerin plana göre ayarlandı'),
      ));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Hedefler güncellenemedi.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsOrDefaultProvider);
    final targets = ref.watch(targetsProvider);
    final suggestion = ref.watch(planSuggestionProvider).valueOrNull;
    final hasWeight = ref.watch(latestWeightProvider).valueOrNull != null;
    final manual = targets.source == TargetsSource.manual;
    final updated = targets.updatedAt;
    final source = presetActive(settings, DietPreset.highProtein1800)
        ? 'Hazır paket · ${DietPreset.highProtein1800.label}'
        : manual
            ? 'Elle ayarlandı'
            : 'Otomatik (kiloya göre)'
                '${updated == null ? '' : ' · ${DateFormat('d MMM', 'tr_TR').format(updated.toLocal())}'}';
    final tempo = resolved.locked
        ? 'Dengeli beslenme'
        : switch (resolved.mode) {
            TargetsMode.maintain => resolved.goal == GoalMode.maintain
                ? GoalMode.maintain.label
                : 'Koruma',
            TargetsMode.recomp => GoalMode.recomp.label,
            TargetsMode.gain =>
              '${GoalMode.leanGain.label} · ${resolved.gainRate.label}',
            _ => '${GoalMode.fatLoss.label} · ${resolved.rate.label}',
          };
    return BentoCard(
      key: const Key('plan-goal'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.flag_outlined,
            label: 'Hedefim',
            color: AppColors.accent,
          ),
          const SizedBox(height: 10),
          Text(
            '${HealthFormat.plain(resolved.weightKg)} → '
            '${HealthFormat.plain(settings.targetWeightKg)} kg',
            key: const Key('plan-goal-weights'),
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tempo,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: PlanBadge(
              key: const Key('plan-source'),
              text: source,
              color: manual ? AppColors.warning : null,
            ),
          ),
          if (!hasWeight) ...[
            const SizedBox(height: 10),
            Text(
              'Henüz tartı yok; hesap başlangıç kilonla yapıldı.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('plan-add-weight'),
                onPressed: () => WeightFormSheet.show(context),
                icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                label: const Text('Tartıl'),
              ),
            ),
          ],
          if (suggestion != null) ...[
            const SizedBox(height: 10),
            Row(
              key: const Key('plan-suggestion'),
              children: [
                Expanded(
                  child: Text(
                    'Kilona göre önerilen ${formatTr(suggestion.kcal)} kcal',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  key: const Key('plan-suggestion-apply'),
                  // Tema tam genişlik verir; satır içinde içerik kadar olsun.
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                  onPressed: () => _apply(context, ref),
                  child: const Text('Uygula'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------- Hedef türü

class _GoalModeCard extends ConsumerWidget {
  const _GoalModeCard({required this.resolved});

  final ResolvedTargets resolved;

  Future<void> _select(BuildContext context, WidgetRef ref,
      {GoalMode? goal, GainRate? gainRate}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final write = await ref.read(planControllerProvider).applyPlan(
            PlanTrigger.rateChanged,
            goal: goal,
            gainRate: gainRate,
          );
      if (write != null) {
        messenger.showSnackBar(SnackBar(content: Text(write.message)));
      }
    } catch (_) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Hedef kaydedilemedi.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projections = ref.watch(goalProjectionsProvider).valueOrNull;
    final selected = resolved.goal;
    return BentoCard(
      key: const Key('plan-goal-mode'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.alt_route_outlined,
            label: 'Hedef türü',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 8),
          for (final g in GoalMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GoalOption(
                goal: g,
                projection: projections?.firstWhere((p) => p.goal == g),
                selected: g == selected,
                onTap:
                    g == selected ? null : () => _select(context, ref, goal: g),
              ),
            ),
          if (selected == GoalMode.leanGain && !resolved.locked) ...[
            Text(
              'Kas yapma temposu',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in GainRate.values)
                  ChoiceChip(
                    key: Key('plan-gain-${r.name}'),
                    label: Text(r.label),
                    selected: resolved.gainRate == r,
                    onSelected: resolved.gainRate == r
                        ? null
                        : (_) => _select(context, ref, gainRate: r),
                  ),
              ],
            ),
          ],
          for (final note in resolved.goalNotes)
            _WarningLine(
              key: Key('plan-goal-note-${resolved.goalNotes.indexOf(note)}'),
              text: note,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _GoalOption extends StatelessWidget {
  const _GoalOption({
    required this.goal,
    required this.projection,
    required this.selected,
    required this.onTap,
  });

  final GoalMode goal;
  final GoalProjection? projection;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = projection;
    final eta = p?.etaText;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Material(
        key: Key('plan-goal-${goal.dbValue}'),
        color: selected
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadii.inner),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_outlined,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        goal.summary,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      if (p != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${p.kcalText} · ${p.weeklyText}',
                          key: Key('plan-goal-${goal.dbValue}-stats'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [p.headline, if (eta != null) eta].join(' · '),
                          key: Key('plan-goal-${goal.dbValue}-projection'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (p.fastLossText != null)
                          Text(
                            p.fastLossText!,
                            key: Key('plan-goal-${goal.dbValue}-fast'),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.warning),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- Günlük hedefler

class _TargetsCard extends ConsumerWidget {
  const _TargetsCard({required this.resolved});

  final ResolvedTargets resolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(targetsProvider);
    final deficit = t.source == TargetsSource.manual
        ? resolved.expenditure.kcal - t.kcal
        : resolved.deficit;
    return BentoCard(
      key: const Key('plan-targets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BentoLabel(label: 'Günlük hedeflerin'),
          const SizedBox(height: 8),
          RitimChipGrid(
            children: [
              RitimChipTile(
                key: const Key('plan-kcal'),
                label: 'Kalori',
                value: '${formatTr(t.kcal)} kcal',
              ),
              RitimChipTile(
                  label: 'Protein', value: '${formatTr(t.proteinG)} g'),
              RitimChipTile(
                  label: 'Karbonhidrat', value: '${formatTr(t.carbsG)} g'),
              RitimChipTile(label: 'Yağ', value: '${formatTr(t.fatG)} g'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Lif ${formatTr(resolved.fiberG)} g · '
            'Adım ${HealthFormat.count(t.steps)} · Uyku '
            '${t.sleepMinutes ~/ 60} sa'
            '${t.sleepMinutes % 60 == 0 ? '' : ' ${t.sleepMinutes % 60} dk'}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (deficit > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Hedef açık: ${formatTr(deficit)} kcal/gün',
              key: const Key('plan-deficit'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (resolved.mode == TargetsMode.gain && resolved.surplus > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Hedef fazla: ${formatTr(resolved.surplus)} kcal/gün',
              key: const Key('plan-surplus'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final w in resolved.warnings)
            _WarningLine(
              key: Key('plan-warning-${resolved.warnings.indexOf(w)}'),
              text: w,
              color: w == resolved.lockedText ? AppColors.textSecondary : null,
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Tempo

class _TempoCard extends ConsumerWidget {
  const _TempoCard({required this.resolved});

  final ResolvedTargets resolved;

  Future<void> _select(
      BuildContext context, WidgetRef ref, FatLossRate rate) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final write = await ref
          .read(planControllerProvider)
          .applyPlan(PlanTrigger.rateChanged, rate: rate);
      if (write != null) {
        messenger.showSnackBar(SnackBar(content: Text(write.message)));
      }
    } catch (_) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Tempo kaydedilemedi.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final options = ref.watch(tempoOptionsProvider).valueOrNull;
    final selected = resolved.rate;
    final info = rateInfo(resolved.asRateResult);
    return BentoCard(
      key: const Key('plan-tempo'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.speed_outlined,
            label: 'Tempo',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 8),
          for (final r in FatLossRate.values)
            _TempoOption(
              rate: r,
              result: options?[r],
              selected: r == selected,
              onTap: r == selected ? null : () => _select(context, ref, r),
            ),
          const SizedBox(height: 12),
          Text(
            'Ne kadar sağlıklı?',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in info.pros)
            _Bullet(text: p, color: AppColors.accent, sign: '+'),
          for (final c in info.cons)
            _Bullet(text: c, color: AppColors.warning, sign: '−'),
        ],
      ),
    );
  }
}

class _TempoOption extends StatelessWidget {
  const _TempoOption({
    required this.rate,
    required this.result,
    required this.selected,
    required this.onTap,
  });

  final FatLossRate rate;
  final ResolvedTargets? result;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final health = r?.health;
    final pct = r == null || r.kgPerWeek <= 0
        ? null
        : ratePercentOfBodyWeight(r.kgPerWeek, r.weightKg);
    final sub = r == null
        ? null
        : [
            '${formatTr(r.kcal)} kcal',
            if (r.kgPerWeek > 0)
              '≈ ${formatTrDecimal2(r.kgPerWeek)} kg/hafta'
                  '${pct == null ? '' : ' · %${formatTrDecimal2(pct)}'}',
            if (r.clamped) 'tabana takıldı',
          ].join(' · ');
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Material(
        key: Key('plan-rate-${rate.name}'),
        color: selected
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.surface.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(AppRadii.inner),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_outlined,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rate.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      if (sub != null)
                        Text(
                          sub,
                          key: Key('plan-rate-${rate.name}-sub'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (health != null) ...[
                  const SizedBox(width: 8),
                  PlanBadge(
                    key: Key('plan-rate-${rate.name}-badge'),
                    text: health.label,
                    color: rateHealthColor(health),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.color, required this.sign});

  final String text;
  final Color color;
  final String sign;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(sign,
                style:
                    body?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child:
                Text(text, style: body?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- Açılır kartlar

/// Başlığa dokununca açılıp kapanan kart.
class _Collapsible extends StatefulWidget {
  const _Collapsible({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget child;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              key: Key(
                  '${(widget.key as ValueKey<String>?)?.value ?? 'plan'}-toggle'),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: BentoLabel(
                        icon: widget.icon,
                        label: widget.title,
                        color: widget.color,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_outlined,
                          color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.cardPadding,
                        0, AppSpacing.cardPadding, AppSpacing.cardPadding),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ Neden bu sayılar?

String _expenditureSourceText(ExpenditureSource s) => switch (s) {
      ExpenditureSource.manual => 'senin girdiğin değer',
      ExpenditureSource.health => 'bazal + sağlık uygulamasındaki aktif kalori',
      ExpenditureSource.estimate => 'profilinden (bazal × hareket) tahmin',
      ExpenditureSource.fallback => 'profil eksik olduğu için varsayılan değer',
    };

class _WhyCard extends ConsumerWidget {
  const _WhyCard({required this.resolved});

  final ResolvedTargets resolved;

  /// Proteinin hedefe göre gerekçesi.
  static String _proteinWhy(TargetsMode mode) => switch (mode) {
        TargetsMode.gain => 'kas yapımını destekler.',
        TargetsMode.maintain ||
        TargetsMode.locked =>
          'kas kütleni korumana yardım eder.',
        _ => 'açıkta kas kaybını azaltır.',
      };

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => ExpenditureDialog(
        initial: resolved.expenditure.kcal,
        estimateKcal: resolved.estimatedExpenditureKcal,
      ),
    );
    if (value != null && context.mounted) {
      await guardedPlanWrite(context,
          () => ref.read(planControllerProvider).setExpenditureManual(value));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final e = resolved.expenditure;
    final body =
        theme.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary);
    final kgText = HealthFormat.kg(resolved.weightKg);
    final deficitText = switch (resolved.mode) {
      TargetsMode.classic when resolved.deficit > 0 =>
        'Klasik formül kilonun 26 katını verir (${formatTr(resolved.kcal)} kcal); '
            'bu, günde ${formatTr(resolved.deficit)} kcal açık demek.',
      TargetsMode.classic =>
        'Klasik formül kilonun 26 katını verir (${formatTr(resolved.kcal)} kcal); '
            'bu, harcamandan ${formatTr(-resolved.deficit)} kcal fazla: açık yok, '
            'bu hedefle kilo vermezsin.',
      TargetsMode.rate when resolved.deficit > 0 =>
        'Seçtiğin hız için günde ${formatTr(resolved.deficit)} kcal açık gerekir '
            '(1 kg yağ ≈ 7.700 kcal). Hedef ${formatTr(resolved.floorKcal)} '
            'kcal tabanının altına inmez.',
      TargetsMode.rate =>
        'Harcaman ${formatTr(resolved.floorKcal)} kcal tabanının altında; '
            'hedef tabana sabitlendi, bu yüzden açık oluşmuyor.',
      TargetsMode.maintain when resolved.goal == GoalMode.maintain =>
        'Hedefin kilonu korumak; harcaman kadar yemen önerilir.',
      TargetsMode.maintain =>
        'Hedef kilon şimdiki kilondan düşük değil; harcaman kadar yemen önerilir.',
      TargetsMode.recomp when resolved.deficit <= 0 =>
        'Harcaman ${formatTr(resolved.floorKcal)} kcal tabanına çok yakın; '
            'hedef tabana sabitlendi, bu yüzden açık oluşmuyor. Yüksek '
            'proteinle (kg × 2,2) beslen.',
      TargetsMode.recomp =>
        'Kas yaparken yağ yakmak için harcamanın ~%10 altında '
            '(${formatTr(resolved.deficit)} kcal açık) ve yüksek proteinle '
            '(kg × 2,2) beslenirsin. Hedef '
            '${formatTr(resolved.floorKcal)} kcal tabanının altına inmez.',
      TargetsMode.gain =>
        'Kas yapmak için harcamanın ${formatTr(resolved.surplus)} kcal '
            'üstünde ve kg × 2,0 proteinle beslenirsin. Haftalık artış '
            'tahminidir; bir kısmı yağdır.',
      TargetsMode.locked => resolved.lockedText,
    };
    final manual = e.source == ExpenditureSource.manual;
    return _Collapsible(
      key: const ValueKey('plan-why'),
      icon: Icons.help_outline_outlined,
      title: 'Neden bu sayılar?',
      color: AppColors.textSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Günlük harcaman yaklaşık ${formatTr(e.kcal)} kcal '
            '(${_expenditureSourceText(e.source)}).',
            key: const Key('plan-why-expenditure'),
            style: body,
          ),
          if (resolved.manualExpenditureOff)
            _WarningLine(
              key: const Key('plan-why-expenditure-off'),
              text: '${SafeTargets.manualExpenditureWarning} (tahmin '
                  '${formatTr(resolved.estimatedExpenditureKcal!)} kcal).',
            ),
          const SizedBox(height: 8),
          Text(deficitText, key: const Key('plan-why-deficit'), style: body),
          const SizedBox(height: 8),
          Text(
            'Protein ${formatTr(resolved.proteinG)} g ($kgText kg için); '
            '${_proteinWhy(resolved.mode)} Makrolar hiçbir zaman kalori '
            'hedefini aşmaz.',
            style: body,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const Key('plan-edit-expenditure'),
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Harcamayı elle gir'),
              ),
              if (manual)
                TextButton(
                  key: const Key('plan-reset-expenditure'),
                  onPressed: () => guardedPlanWrite(
                      context,
                      () => ref
                          .read(planControllerProvider)
                          .setExpenditureManual(null)),
                  child: const Text('Tahmine dön'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Günlük harcama girişi; denetleyicinin sahibi bu durum nesnesidir, böylece
/// diyalog kapanış animasyonu sırasında da denetleyici geçerli kalır.
class ExpenditureDialog extends StatefulWidget {
  const ExpenditureDialog({
    super.key,
    required this.initial,
    this.estimateKcal,
  });

  final int initial;

  /// Modelin tahmini; girilen değer bundan ±%30 saparsa uyarı (kaydı
  /// engellemez).
  final int? estimateKcal;

  @override
  State<ExpenditureDialog> createState() => _ExpenditureDialogState();
}

class _ExpenditureDialogState extends State<ExpenditureDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _offEstimate {
    final estimate = widget.estimateKcal;
    final value = int.tryParse(_controller.text.trim());
    return estimate != null &&
        value != null &&
        manualExpenditureOutOfRange(manualKcal: value, estimateKcal: estimate);
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null ||
        value < UserSettings.expenditureManualMin ||
        value > UserSettings.expenditureManualMax) {
      setState(() => _error = planExpenditureError);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Günlük harcama'),
      content: TextField(
        key: const Key('plan-expenditure-field'),
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          suffixText: 'kcal',
          errorText: _error,
          helperText: _offEstimate
              ? '${SafeTargets.manualExpenditureWarning} '
                  '(tahmin ${formatTr(widget.estimateKcal!)} kcal)'
              : null,
          helperStyle: TextStyle(color: AppColors.warning),
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('plan-expenditure-save'),
          onPressed: _submit,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- Rehber

class _GuideCard extends ConsumerWidget {
  const _GuideCard({required this.resolved});

  final ResolvedTargets resolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsOrDefaultProvider);
    final t = ref.watch(targetsProvider);
    // Rehber kaydedilmiş hedeflere göre ölçeklenir (elle ayar dahil).
    final targets = FatLossTargets(
      weightKg: resolved.weightKg,
      kcal: t.kcal,
      proteinG: t.proteinG,
      fatG: t.fatG,
      fiberG: resolved.fiberG,
      carbsG: t.carbsG,
    );
    return _Collapsible(
      key: const ValueKey('plan-guide'),
      icon: Icons.menu_book_outlined,
      title: 'Rehber',
      color: AppColors.nutrition,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EquivalentsSection(targets: targets),
          const _GuideDivider(),
          _MenuSection(targets: targets, mealCount: settings.mealCount),
          const _GuideDivider(),
          _SupplementSection(
            targets: targets,
            sex: Sex.tryParse(settings.sex),
          ),
        ],
      ),
    );
  }
}

class _GuideDivider extends StatelessWidget {
  const _GuideDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, thickness: 0.5, color: AppColors.border),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class _EquivalentsSection extends StatefulWidget {
  const _EquivalentsSection({required this.targets});

  final FatLossTargets targets;

  @override
  State<_EquivalentsSection> createState() => _EquivalentsSectionState();
}

class _EquivalentsSectionState extends State<_EquivalentsSection> {
  FatLossMacro _macro = FatLossMacro.protein;
  int _meals = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amounts = equivalentsFor(widget.targets, _macro, meals: _meals);
    final grams = widget.targets.gramsFor(_macro);
    return Column(
      key: const Key('plan-equivalents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Besin karşılıkları'),
        SegmentedButton<FatLossMacro>(
          showSelectedIcon: false,
          segments: [
            for (final m in FatLossMacro.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {_macro},
          onSelectionChanged: (s) => setState(() => _macro = s.first),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: Text('Öğün sayısı', style: theme.textTheme.bodyMedium)),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {_meals},
              onSelectionChanged: (s) => setState(() => _meals = s.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _meals == 1
              ? 'Günlük ${formatTr(grams)} g ${_macro.label.toLowerCase()} için tek başına:'
              : 'Öğün başına ${formatTr(grams / _meals)} g ${_macro.label.toLowerCase()} için tek başına:',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        for (final a in amounts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(a.label, style: theme.textTheme.bodyLarge),
          ),
      ],
    );
  }
}

class _MenuSection extends ConsumerWidget {
  const _MenuSection({required this.targets, required this.mealCount});

  final FatLossTargets targets;
  final int mealCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final menu = scaledMenu(mealCount, targets);
    final totals = menuTotals(menu);
    final under = menuUnderTarget(menu, targets);
    final t = targets;
    return Column(
      key: const Key('plan-menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Örnek menü'),
        RitimSegmented<int>(
          segments: const {2: '2 öğün', 3: '3 öğün'},
          selected: mealCount,
          onChanged: (n) => guardedPlanWrite(
              context, () => ref.read(planControllerProvider).setMealCount(n)),
        ),
        for (final meal in menu) ...[
          const SizedBox(height: 12),
          Text(
            meal.name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meal.items.map((i) => i.label).join(' · '),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Toplam ${formatTr(totals.kcal)} kcal · P ${formatTr(totals.protein)} g · '
          'Y ${formatTr(totals.fat)} g · K ${formatTr(totals.carbs)} g · '
          'Lif ${formatTr(totals.fiber)} g',
          key: const Key('plan-menu-total'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Hedef ${formatTr(t.kcal)} kcal · P ${formatTr(t.proteinG)} g · '
          'Y ${formatTr(t.fatG)} g · K ${formatTr(t.carbsG)} g · '
          'Lif ${formatTr(t.fiberG)} g',
          key: const Key('plan-menu-target'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        if (under) ...[
          const SizedBox(height: 4),
          Text(menuUnderNote,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.warning)),
        ],
        const SizedBox(height: 4),
        Text(planApproxNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

/// Rehberdeki su önerisi takipteki hedeften farklıysa "Hedefi 2,95 L yap".
class _WaterTargetAction extends ConsumerWidget {
  const _WaterTargetAction({required this.recommendedMl});

  final int recommendedMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(waterTodayProvider).valueOrNull?.targetMl;
    if (current == null || current == recommendedMl) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextButton.icon(
          key: const Key('plan-water-apply'),
          onPressed: () => guardedPlanWrite(
            context,
            () =>
                ref.read(waterTodayProvider.notifier).setTarget(recommendedMl),
          ),
          icon:
              Icon(Icons.water_drop_outlined, size: 18, color: AppColors.water),
          label: Text('Hedefi ${formatWaterMl(recommendedMl)} yap '
              '(şu an ${formatWaterMl(current)})'),
        ),
      ),
    );
  }
}

class _SupplementSection extends StatelessWidget {
  const _SupplementSection({required this.targets, required this.sex});

  final FatLossTargets targets;
  final Sex? sex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = theme.textTheme.titleSmall?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final body =
        theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    Widget item(String key, String head, String text, {bool hot = false}) =>
        Padding(
          key: Key('supplement-$key'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(head,
                  style:
                      hot ? title?.copyWith(color: AppColors.warning) : title),
              const SizedBox(height: 2),
              Text(text, style: body),
            ],
          ),
        );
    return Column(
      key: const Key('plan-supplements'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Su ve lif'),
        item(
            'water',
            'Su',
            '≈ ${formatTr(recommendedWaterMl(targets.weightKg))} ml/gün '
                '(kilo × 35 ml, en çok 4.000 ml); yiyecek ve içecek dahil; '
                'kalp/böbrek hastalığında doktora sor.'),
        _WaterTargetAction(recommendedMl: recommendedWaterMl(targets.weightKg)),
        item(
            'fiber',
            'Lif',
            'En az 25 g; hedefin: ${formatTr(targets.fiberG)} g. Sebze, '
                'baklagil ve tam tahıl.'),
        Text(
          supplementDisclaimer,
          key: const Key('supplement-disclaimer'),
          style:
              theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Kaynaklar'),
        for (final src in healthSources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              '${src.topic}: ${src.citation}\n${src.url}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------- Ölçü ve fotoğraf günü

class _CheckinCard extends ConsumerWidget {
  const _CheckinCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsOrDefaultProvider);
    final now = ref.watch(trendClockProvider)();
    final controller = ref.read(planControllerProvider);
    final weekly = settings.checkinCadence == CheckinCadence.weekly;
    return BentoCard(
      key: const Key('plan-checkin'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.straighten_outlined,
            label: 'Ölçü ve fotoğraf günü',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 4),
          Text(
            checkinScheduleLine(settings, now),
            key: const Key('plan-checkin-line'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          RitimSegmented<CheckinCadence>(
            key: const Key('plan-checkin-cadence'),
            segments: const {
              CheckinCadence.weekly: 'Haftalık',
              CheckinCadence.monthly: 'Aylık',
            },
            selected: settings.checkinCadence,
            onChanged: (c) => guardedPlanWrite(
                context, () => controller.setCheckinSchedule(cadence: c)),
          ),
          const SizedBox(height: 12),
          if (weekly)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    key: Key('plan-checkin-weekday-$d'),
                    label: Text(TodayFormat.weekdayShort[d - 1]),
                    tooltip: trWeekdayNames[d - 1],
                    selected: settings.checkinWeekday == d,
                    onSelected: (_) => guardedPlanWrite(context,
                        () => controller.setCheckinSchedule(weekday: d)),
                  ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text('Ayın günü', style: theme.textTheme.bodyMedium),
                ),
                DropdownButton<int>(
                  key: const Key('plan-checkin-monthday'),
                  value: settings.checkinMonthday,
                  items: [
                    for (var d = 1; d <= UserSettings.checkinMonthdayMax; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (d) {
                    if (d != null) {
                      guardedPlanWrite(context,
                          () => controller.setCheckinSchedule(monthday: d));
                    }
                  },
                ),
              ],
            ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            key: const Key('plan-checkin-reminder'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Hatırlatma (09:00)'),
            value: settings.checkinReminder,
            onChanged: (v) => guardedPlanWrite(
                context, () => controller.setCheckinSchedule(reminder: v)),
          ),
        ],
      ),
    );
  }
}
