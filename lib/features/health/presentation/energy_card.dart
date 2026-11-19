import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../settings/presentation/profile_goals_page.dart';
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
            MaterialPageRoute<void>(builder: (_) => const ProfileGoalsPage()),
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
