import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/services/health_source.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_sync.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/bento.dart';
import '../../friends/presentation/friends_providers.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import 'appearance_page.dart';
import 'categories_team_page.dart';
import 'connections_page.dart';
import 'feedback_sheet.dart';
import 'my_avatar.dart';
import 'notifications_page.dart';
import 'privacy_screen.dart';
import 'profile_goals_page.dart';
import 'settings_providers.dart';
import 'share_stories_card.dart';

/// Hesap menüsü: altı alt sayfa ve küçük yardım/çıkış grubu. Her alt sayfa
/// kendi içinde kaydeder.
class HesapScreen extends ConsumerStatefulWidget {
  const HesapScreen({super.key});

  @override
  ConsumerState<HesapScreen> createState() => _HesapScreenState();
}

class _HesapScreenState extends ConsumerState<HesapScreen> {
  bool _signingOut = false;

  void _open(Widget page) => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => page),
      );

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Tekrar giriş yapana kadar verilerin görünmez.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Çıkış yap', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOut = true);
    try {
      // Çıkıştan önce bekleyen bildirimler silinir: özel başlıklar kilit
      // ekranında kalmasın. Silme hatası çıkışı engellemez.
      try {
        await ref
            .read(notificationSyncQueueProvider)
            .endSession(ref.read(notificationServiceProvider));
      } catch (_) {}
      await ref.read(supabaseClientProvider).auth.signOut();
      // Oturum kapanınca kök ekran giriş sayfasına döner.
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Çıkış yapılamadı. Tekrar dene.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    final email = ref.watch(
      authSessionProvider.select((s) => s.valueOrNull?.user.email),
    );
    final pending =
        ref.watch(pendingFriendRequestCountProvider).valueOrNull ?? 0;
    final themeMode = ref.watch(themeModeProvider);
    final source = ref.watch(healthSourceProvider);

    final name = settings?.displayName;
    final profileHint = settings == null
        ? null
        : (settings.heightCm == null ||
                settings.birthYear == null ||
                settings.sex == null)
            ? 'Eksik'
            : null;
    final notificationHint = settings == null
        ? null
        : settings.notificationsEnabled
            ? 'Açık'
            : 'Kapalı';
    final teamCount = settings?.teamMembers.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Hesap')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.grid,
          AppSpacing.page,
          120,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                const MyAvatar(key: Key('hesap-avatar'), size: 52),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (name != null && name.isNotEmpty)
                        Text(name, style: theme.textTheme.titleMedium),
                      if (email != null && email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          BentoCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: _divided([
                _MenuRow(
                  key: const Key('hesap-profile'),
                  icon: Icons.badge_outlined,
                  title: 'Profil ve hedefler',
                  hint: profileHint,
                  onTap: () => _open(const ProfileGoalsPage()),
                ),
                _MenuRow(
                  key: const Key('settings-friends'),
                  icon: Icons.people_outlined,
                  title: 'Arkadaşlar',
                  badge: pending > 0 ? '$pending davet' : null,
                  onTap: () => _open(const FriendsScreen()),
                ),
                _MenuRow(
                  key: const Key('hesap-notifications'),
                  icon: Icons.notifications_outlined,
                  title: 'Bildirimler',
                  hint: notificationHint,
                  onTap: () => _open(const NotificationsPage()),
                ),
                _MenuRow(
                  key: const Key('hesap-appearance'),
                  icon: Icons.palette_outlined,
                  title: 'Görünüm',
                  hint: themeMode.label,
                  onTap: () => _open(const AppearancePage()),
                ),
                _MenuRow(
                  key: const Key('hesap-categories'),
                  icon: Icons.category_outlined,
                  title: 'Kategoriler ve ekip',
                  hint: teamCount == null || teamCount == 0
                      ? null
                      : '$teamCount kişi',
                  onTap: () => _open(const CategoriesTeamPage()),
                ),
                _MenuRow(
                  key: const Key('hesap-connections'),
                  icon: Icons.link_outlined,
                  title: 'Bağlantılar',
                  hint: source == HealthSourceKind.appleHealth
                      ? 'Apple Sağlık'
                      : source.label,
                  onTap: () => _open(const ConnectionsPage()),
                ),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          BentoCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: _divided([
                // BEGIN faz5_account
                _MenuRow(
                  key: const Key('settings-privacy'),
                  icon: Icons.privacy_tip_outlined,
                  title: 'Yardım ve gizlilik',
                  compact: true,
                  onTap: () => _open(const PrivacyScreen()),
                ),
                _MenuRow(
                  key: const Key('settings-replay-guide'),
                  icon: Icons.menu_book_outlined,
                  title: 'Kılavuzu yeniden göster',
                  compact: true,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => const OnboardingScreen(replay: true),
                    ),
                  ),
                ),
                _MenuRow(
                  key: const Key('settings-feedback'),
                  icon: Icons.bug_report_outlined,
                  title: 'Sorun bildir',
                  compact: true,
                  onTap: () => FeedbackSheet.show(context),
                ),
                // END faz5_account
                _MenuRow(
                  key: const Key('settings-sign-out'),
                  icon: Icons.logout_outlined,
                  title: _signingOut ? 'Çıkış yapılıyor…' : 'Çıkış yap',
                  compact: true,
                  danger: true,
                  showChevron: false,
                  onTap: _signingOut ? null : _signOut,
                ),
              ]),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          const ShareStoriesCard(),
        ],
      ),
    );
  }
}

/// Kart içindeki satırların arasına ince ayırıcı çizgi koyar.
List<Widget> _divided(List<Widget> rows) => [
      for (final (i, row) in rows.indexed) ...[
        if (i > 0)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: AppSpacing.cardPadding,
            endIndent: AppSpacing.cardPadding,
          ),
        row,
      ],
    ];

/// Menü satırı: başlık, sağda gri durum ya da rozet ve ok.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.hint,
    this.badge,
    this.compact = false,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? badge;
  final bool compact;
  final bool danger;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(color: color),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (hint != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              if (showChevron) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
