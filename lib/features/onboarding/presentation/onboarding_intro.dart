import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_top/ritim_top.dart';

/// Tanıtım kartı içeriği (renk, çizim sırasında etkin paletten okunur).
class OnboardingIntroCard {
  const OnboardingIntroCard({
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}

/// Kılavuzun 5 kartı: Kokpit, + ile iki ayrı giriş, İşler ve aylık rutin
/// mantığı, Sağlık (trend ve denge), Raporlar ve Arkadaşlar.
const List<OnboardingIntroCard> onboardingIntroCards = [
  OnboardingIntroCard(
    icon: Icons.dashboard_rounded,
    title: 'Kokpit: günün tek bakışta',
    body: 'Bugünün görevleri, rutinlerin, yaklaşan aylık işler ve beslenme '
        'özetin burada toplanır.',
    bullets: [
      'Gün görünümü bugünü, Ay görünümü ayın tamamını gösterir.',
      'Satırı sola kaydırarak sil, uzun basarak düzenle.',
    ],
  ),
  OnboardingIntroCard(
    icon: Icons.add_circle_rounded,
    title: '+ ile iki ayrı giriş',
    body: 'Alt çubuğun ortasındaki + düğmesine bir cümle yaz; yapay zekâ '
        'bunu kayda çevirir. İki ayrı kapı vardır ve birbirine karışmaz:',
    bullets: [
      'İş: görev, randevu, not.',
      'Sağlık ve beslenme: öğün, antrenman, kilo.',
    ],
  ),
  OnboardingIntroCard(
    icon: Icons.checklist_rounded,
    title: 'İşler ve aylık rutinler',
    body: 'İşler sekmesinde görevler, notlar ve rutinler (tekrarlayan '
        'işler) durur. Aylık rutinler ayın belirli günü bir iştir.',
    bullets: [
      'Ayın 15\'i ödeme gibi rutinler gününden birkaç gün önce görünür '
          '(Ayarlar\'dan değişir).',
      'Gün geçince "gecikti" olur, ay sonunda "yapılmadı" diye kapanır.',
      'Tarih hafta sonuna denk gelse de kaymaz.',
    ],
  ),
  OnboardingIntroCard(
    icon: Icons.favorite_rounded,
    title: 'Sağlık: trend ve denge',
    body: 'Adım, uyku ve kalori kartlarına dokununca Trend açılır: hedefi '
        'tutturduğun günler ve seri.',
    bullets: [
      'Enerji dengesi, yediğin ile yaktığın farkı tahmini gösterir.',
      'Tüm sayılar tahmindir, tıbbi tavsiye değildir.',
    ],
  ),
  OnboardingIntroCard(
    icon: Icons.groups_rounded,
    title: 'Raporlar ve Arkadaşlar',
    body: 'Günlük ve haftalık raporlar sunucuda otomatik hazırlanır. '
        'Arkadaşlarını Kokpit\'in üstündeki kişi simgesinden e-postayla '
        'ekleyebilirsin.',
    bullets: [
      'Arkadaşların yalnızca senin açtığın sağlık hedefi özetini görür '
          '(adım, uyku, kalori).',
      'İşin, görevlerin ve notların asla paylaşılmaz.',
    ],
  ),
];

/// Tek tanıtım kartının sayfası.
class OnboardingIntroPage extends StatelessWidget {
  const OnboardingIntroPage({
    super.key,
    required this.card,
    this.accent,
    this.showMark = false,
  });

  final OnboardingIntroCard card;

  /// Kartın üstünde uygulama topacı bir kez dönüp yerine oturur (karşılama).
  final bool showMark;

  /// Simge rengi; verilmezse ana vurgu.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? AppColors.accent;
    return BentoCard(
      padding: const EdgeInsets.all(AppSpacing.cardPadding + 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMark) ...[
            const Center(
              child: RitimTop(mode: RitimTopMode.settle, size: 96),
            ),
            const SizedBox(height: 12),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.inner),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(card.icon, size: 32, color: color),
            ),
          ),
          const SizedBox(height: 20),
          Text(card.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            card.body,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: AppColors.textSecondary, height: 1.45),
          ),
          if (card.bullets.isNotEmpty) const SizedBox(height: 14),
          for (final bullet in card.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 6),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Kart ilerleme noktaları.
class OnboardingDots extends StatelessWidget {
  const OnboardingDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
