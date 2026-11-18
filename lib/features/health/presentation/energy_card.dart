import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import 'energy_detail_screen.dart';
import 'energy_providers.dart';
import 'health_format.dart';
import 'health_widgets.dart';
import 'trend_providers.dart' show trendClockProvider;

/// Profil eksikken kartın metni.
const String energyProfileMissingText =
    'Dengeyi hesaplamak için boy, yaş ve cinsiyet gerekli';

/// Aktif kalori verisi olmayan günün notu.
const String energyActiveMissingNote =
    'aktif kalori verisi yok, tahmin bazala dayanıyor';

/// Günün yorumu. 18 yaşından küçükler için `null`: yorum ve açık hedefi
/// gösterilmez, yalnızca sayılar görünür. Metinler bugüne yöneliktir
/// (kart yalnızca bugünü gösterir).
String? energyVerdictText(EnergyVerdict verdict) => switch (verdict) {
      EnergyVerdict.veryHighDeficit =>
        'Çok yüksek kalori açığı: yeterince yediğinden emin ol',
      EnergyVerdict.burning => 'Bugün yağ yaktın',
      EnergyVerdict.steady => 'Bugün yerinde saydın, yağ almadın',
      EnergyVerdict.slightOver => 'Bugün biraz kaçırdın, telafi edebilirsin',
      EnergyVerdict.over =>
        'Bugün fazla geçti; bir günle bozulmaz, yarın toparla',
      EnergyVerdict.noMeals => 'Henüz öğün girilmedi',
      EnergyVerdict.underAge => null,
    };

/// "Biraz kaçırdın" gününün telafi satırı; başka günlerde `null`.
String? energyCompensationText(EnergyDay day) {
  final minutes = day.walkingMinutesToCompensate;
  final cut = day.tomorrowCutKcal;
  if (minutes == null || cut == null) return null;
  return 'Telafi: yaklaşık $minutes dk tempolu yürüyüş ya da yarın '
      '${HealthFormat.count(cut)} kcal daha az ye';
}

/// Yorumun rengi (etkin temadan okunur; `const` içinde kullanılmaz). Çok
/// yüksek açık dikkat rengidir, mint değil: övgü değildir.
Color energyVerdictColor(EnergyVerdict verdict) => switch (verdict) {
      EnergyVerdict.burning => AppColors.accent,
      EnergyVerdict.steady => AppColors.textPrimary,
      EnergyVerdict.veryHighDeficit ||
      EnergyVerdict.slightOver ||
      EnergyVerdict.over =>
        AppColors.warning,
      EnergyVerdict.noMeals ||
      EnergyVerdict.underAge =>
        AppColors.textSecondary,
    };

/// Rengin yanında şekil de taşısın diye her yorumun simgesi vardır.
IconData energyVerdictIcon(EnergyVerdict verdict) => switch (verdict) {
      EnergyVerdict.burning => Icons.trending_down_rounded,
      EnergyVerdict.steady => Icons.drag_handle_rounded,
      EnergyVerdict.slightOver ||
      EnergyVerdict.over =>
        Icons.trending_up_rounded,
      EnergyVerdict.veryHighDeficit => Icons.warning_amber_rounded,
      EnergyVerdict.noMeals => Icons.restaurant_rounded,
      EnergyVerdict.underAge => Icons.info_outline_rounded,
    };

/// Sağlık sekmesinin "Enerji dengesi" kartı: bugün alınan, yakılan ve net
/// kcal, günün yorumu ve (biraz fazla günde) telafi önerisi. Dokununca
/// hafta/ay detayı açılır. Profil eksikse Ayarlar'a götürür.
///
/// "Bugün" her build'de [trendClockProvider]'dan okunur; uygulama gece
/// yarısını geçip öne gelince sağlayıcılar tazelenir ve kart yeni güne göre
/// yeniden çizilir.
class EnergyCard extends ConsumerWidget {
  const EnergyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
    final energy = ref.watch(energyDayProvider(today));
    final day = energy.valueOrNull;

    return BentoCard(
      onTap: day == null ? null : () => EnergyDetailScreen.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: BentoLabel(
                  icon: Icons.bolt_rounded,
                  label: 'Enerji dengesi',
                  color: AppColors.fitness,
                  trailing: day != null && day.isToday ? 'Şu ana kadar' : null,
                ),
              ),
              if (day != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 10),
          energy.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const HealthCardLoading(height: 96),
            error: (_, __) => HealthCompactMessage(
              text: 'Enerji dengesi yüklenemedi.',
              onRetry: () {
                ref
                  ..invalidate(userSettingsProvider)
                  ..invalidate(energyDayProvider);
              },
            ),
            data: (value) => value == null
                ? const _ProfileMissing()
                : _EnergyBody(day: value),
          ),
        ],
      ),
    );
  }
}

class _ProfileMissing extends StatelessWidget {
  const _ProfileMissing();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          energyProfileMissingText,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        FilledButton.tonal(
          key: const Key('energy-open-settings'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(healthMinTouch, healthMinTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Profili doldur'),
        ),
      ],
    );
  }
}

class _EnergyBody extends StatelessWidget {
  const _EnergyBody({required this.day});

  final EnergyDay day;

  String get _semantics {
    final intake = day.intake;
    final net = day.net;
    final parts = [
      'Enerji dengesi${day.isToday ? ', şu ana kadar' : ''}',
      if (intake != null) 'alınan ${HealthFormat.kcal(intake)}',
      'yakılan ${HealthFormat.kcal(day.burned)}',
      if (net != null) 'net ${formatEnergyNet(net)} kcal',
      if (energyVerdictText(day.verdict) case final text?) text,
      if (energyCompensationText(day) case final text?) text,
      if (day.activeDataMissing) energyActiveMissingNote,
    ];
    return parts.join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdict = day.verdict;
    final verdictText = energyVerdictText(verdict);
    final compensation = energyCompensationText(day);
    final intake = day.intake;
    final net = day.net;
    final verdictColor = energyVerdictColor(verdict);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    return Semantics(
      label: _semantics,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Figure(
                    valueKey: const Key('energy-intake'),
                    label: 'Alınan',
                    value: intake == null
                        ? KokpitFormat.none
                        : HealthFormat.count(intake),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    valueKey: const Key('energy-burned'),
                    label: 'Yakılan',
                    value: HealthFormat.count(day.burned),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    valueKey: const Key('energy-net'),
                    label: 'Net',
                    value:
                        net == null ? KokpitFormat.none : formatEnergyNet(net),
                    color: net == null ? null : verdictColor,
                  ),
                ),
              ],
            ),
            if (verdictText != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      energyVerdictIcon(verdict),
                      size: 18,
                      color: verdictColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verdictText,
                      key: const Key('energy-verdict'),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: verdictColor),
                    ),
                  ),
                ],
              ),
            ],
            if (compensation != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  compensation,
                  key: const Key('energy-compensation'),
                  style: muted,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Yakılan = bazal ${HealthFormat.count(day.basal)} + '
              'aktif ${HealthFormat.count(day.active)} kcal',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
            if (day.activeDataMissing)
              Text(
                energyActiveMissingNote,
                key: const Key('energy-active-missing'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Üç sütunlu sayı satırındaki tek değer: etiket, büyük sayı, birim.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.valueKey,
    required this.label,
    required this.value,
    this.color,
  });

  final Key valueKey;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
        ),
        // Büyük metin ölçeğinde taşmak yerine küçülür.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: valueKey,
            maxLines: 1,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          'kcal',
          style:
              theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Özet sekmesinin enerji kartı: yalnızca bugünün net kcal'i. Alınan,
/// yakılan ve yorum dokununca açılan detay ekranındadır.
class EnergyNetCard extends ConsumerWidget {
  const EnergyNetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = AppDates.startOfDay(ref.watch(trendClockProvider)());
    final energy = ref.watch(energyDayProvider(today));
    final day = energy.valueOrNull;

    return BentoCard(
      onTap: day == null ? null : () => EnergyDetailScreen.open(context),
      child: energy.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const HealthCardLoading(height: 56),
        error: (_, __) => HealthCompactMessage(
          text: 'Enerji dengesi yüklenemedi.',
          onRetry: () {
            ref
              ..invalidate(userSettingsProvider)
              ..invalidate(energyDayProvider);
          },
        ),
        data: (value) {
          if (value == null) return const _ProfileMissing();
          final net = value.net;
          final label = net == null
              ? 'Enerji · bugün yakılan'
              : 'Enerji · bugün net';
          final number = net == null
              ? HealthFormat.count(value.burned)
              : formatEnergyNet(net);
          return Semantics(
            label: '$label $number kcal',
            button: true,
            container: true,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        HealthBigValue(
                          key: const Key('energy-net-today'),
                          value: number,
                          unit: 'kcal',
                          singleLine: true,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
