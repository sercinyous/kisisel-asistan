import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_avatar.dart';
import '../../../core/widgets/bento.dart';
import '../../../core/widgets/ritim_ui.dart';
import '../data/friends_repository.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key}) : sharingOnly = false;

  /// Arkadaşlar › Paylaşım ayarları: yalnızca paylaşım anahtarları.
  const FriendsScreen.sharing({super.key}) : sharingOnly = true;

  final bool sharingOnly;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _email = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// İşlemi çalıştırır; başarılıysa `true`. Hata kullanıcıya bildirilir.
  Future<bool> _run(Future<void> Function() action) async {
    var ok = true;
    try {
      await action();
    } catch (_) {
      ok = false;
      _toast('İşlem yapılamadı. Bağlantını kontrol edip tekrar dene.');
    }
    if (mounted) refreshFriends(ref);
    return ok;
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@') || email.length < 5) {
      _toast('Geçerli bir e-posta yaz.');
      return;
    }
    setState(() => _sending = true);
    try {
      final msg = await ref.read(friendsRepositoryProvider).sendRequest(email);
      _email.clear();
      _toast(msg);
    } catch (_) {
      _toast('İstek gönderilemedi. Tekrar dene.');
    }
    if (mounted) {
      setState(() => _sending = false);
      refreshFriends(ref);
    }
  }

  Future<void> _confirmLeave(LeaderboardEntry f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arkadaşlıktan çık'),
        content: Text('${f.displayName} ile arkadaşlık sona erecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Çık', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(friendsRepositoryProvider).leave(f.userId));
    }
  }

  Future<void> _confirmBlock(LeaderboardEntry f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Engelle'),
        content: Text(
          '${f.displayName} arkadaş listenden çıkar ve sana bir daha '
          'istek gönderemez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Engelle', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(friendsRepositoryProvider).block(f.userId));
    }
  }

  /// Kullanıcıyı bildirir: onay + isteğe bağlı kısa gerekçe; isterse aynı
  /// anda engeller. Bildirim kullanıcı kimliğini (ve varsa istek kimliğini) taşır.
  Future<void> _report(
    String subject, {
    String? userId,
    String? requestId,
  }) async {
    final choice = await showDialog<({String reason, bool block})>(
      context: context,
      builder: (_) => _ReportDialog(subject: subject, canBlock: userId != null),
    );
    if (choice == null || !mounted) return;
    final repo = ref.read(friendsRepositoryProvider);
    final ok = await _run(() async {
      await repo.report(
        subject: subject,
        // Gelen istekte gönderenin kimliği istemciye açılmaz; istek kimliği
        // sunucuda gönderene götürür (friend_requests.from_user).
        reason: [
          if (userId != null) 'kullanıcı $userId',
          if (requestId != null) 'arkadaşlık isteği $requestId',
          if (choice.reason.isNotEmpty) 'gerekçe: ${choice.reason}',
        ].join(' · '),
      );
      if (choice.block && userId != null) {
        await repo.block(userId);
      } else if (requestId != null) {
        // Bildirilen istek reddedilir.
        await repo.respond(requestId, accept: false);
      }
    });
    if (ok) {
      _toast(choice.block
          ? 'Bildirimin alındı ve kullanıcı engellendi.'
          : 'Bildirimin alındı. Teşekkürler.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: AppSpacing.grid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.sharingOnly ? 'Paylaşım ayarları' : 'Arkadaşlar'),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async => refreshFriends(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            120,
          ),
          children: widget.sharingOnly
              ? [
                  const SizedBox(height: AppSpacing.grid),
                  _sharing(theme),
                ]
              : [
                  gap,
                  _incoming(theme),
                  gap,
                  _friendList(theme),
                  gap,
                  RitimSectionCard(
                    title: 'Arkadaş ekle',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            hintText: 'ornek@gmail.com',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.grid),
                        FilledButton(
                          onPressed: _sending ? null : _send,
                          child:
                              Text(_sending ? 'Gönderiliyor…' : 'İstek gönder'),
                        ),
                      ],
                    ),
                  ),
                  _outgoing(theme),
                  gap,
                  BentoCard(
                    key: const Key('friends-sharing-settings'),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const FriendsScreen.sharing(),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Paylaşım ayarları',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _message(ThemeData theme, String text) => BentoCard(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );

  Widget _error(ThemeData theme, VoidCallback retry) => BentoCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Yüklenemedi.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
            TextButton(onPressed: retry, child: const Text('Tekrar dene')),
          ],
        ),
      );

  Widget _loading() => const BentoCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.grid),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );

  Widget _incoming(ThemeData theme) {
    final async = ref.watch(incomingRequestsProvider);
    return async.when(
      loading: _loading,
      error: (_, __) =>
          _error(theme, () => ref.invalidate(incomingRequestsProvider)),
      data: (list) {
        if (list.isEmpty) {
          return RitimSectionCard(
            title: 'Davetler',
            trailing: 'yok',
            child: Text(
              'Bekleyen davet yok.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        return RitimSectionCard(
          title: 'Davetler',
          trailing: '${list.length} davet',
          child: Column(
            children: [
              for (final (i, r) in list.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.fromName.isEmpty ? 'Bir kullanıcı' : r.fromName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Bildir',
                        color: AppColors.textMuted,
                        icon: const Icon(Icons.flag_outlined),
                        onPressed: () => _report(
                          r.fromName.isEmpty ? 'Bir kullanıcı' : r.fromName,
                          requestId: r.id,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reddet',
                        color: AppColors.danger,
                        icon: const Icon(Icons.close_outlined),
                        onPressed: () => _run(() => ref
                            .read(friendsRepositoryProvider)
                            .respond(r.id, accept: false)),
                      ),
                      IconButton(
                        tooltip: 'Kabul et',
                        color: AppColors.accent,
                        icon: const Icon(Icons.check_outlined),
                        onPressed: () => _run(() => ref
                            .read(friendsRepositoryProvider)
                            .respond(r.id, accept: true)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _friendList(ThemeData theme) {
    final async = ref.watch(friendsLeaderboardProvider);
    final metric = ref.watch(leaderboardMetricProvider);
    final period = ref.watch(leaderboardPeriodProvider);
    // Ham değeri paylaşılmayan arkadaş için hedef gün sayıları.
    final goals = <String, Map<GoalMetric, GoalSummary>>{
      for (final f in ref.watch(friendsWithSummaryProvider).valueOrNull ??
          const <FriendWithSummary>[])
        f.friend.friendId: {
          for (final s in f.summaries)
            if (s.metric != null) s.metric!: s,
        },
    };
    return async.when(
      loading: _loading,
      error: (_, __) =>
          _error(theme, () => ref.invalidate(friendsLeaderboardProvider)),
      data: (list) {
        final ranked = rankEntries(list, metric, period);
        final hasFriends = list.any((e) => !e.isSelf);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final m in GoalMetric.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: m == metric,
                    onSelected: (_) =>
                        ref.read(leaderboardMetricProvider.notifier).state = m,
                  ),
                for (final p in RankPeriod.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p == period,
                    onSelected: (_) =>
                        ref.read(leaderboardPeriodProvider.notifier).state = p,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.grid),
            RitimSectionCard(
              title: 'Arkadaşlar',
              trailing: '${metric.label} · ${period.label}',
              child: Column(
                children: [
                  for (var i = 0; i < ranked.length; i++)
                    _rankRow(
                      theme,
                      ranked[i],
                      i,
                      metric,
                      period,
                      goals[ranked[i].userId]?[metric],
                    ),
                ],
              ),
            ),
            if (!hasFriends)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.grid),
                child: _message(
                    theme, 'Henüz arkadaşın yok. E-postayla davet et.'),
              ),
          ],
        );
      },
    );
  }

  Color? _medalColor(int index) => switch (index) {
        0 => AppColors.warning,
        1 => AppColors.textSecondary,
        2 => AppColors.nutrition,
        _ => null,
      };

  Widget _rankRow(
    ThemeData theme,
    LeaderboardEntry e,
    int index,
    GoalMetric metric,
    RankPeriod period,
    GoalSummary? goal,
  ) {
    final value = e.value(metric, period);
    final label = value == null && !e.isSelf
        ? formatGoalDays(goal) ?? formatMetricValue(metric, period, null)
        : formatMetricValue(metric, period, value);
    // Kalori sıralaması yapılmaz: çok yiyene madalya verilmez (ICG2-11).
    final ranked = metric != GoalMetric.calories;
    final medal =
        ranked && value != null && value > 0 ? _medalColor(index) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: medal != null
                ? Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: medal,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Text(
                    ranked ? '${index + 1}' : '·',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.textMuted),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _Avatar(entry: e),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.isSelf ? '${e.displayName} (sen)' : e.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (e.isSelf && e.email.isNotEmpty && e.email != e.displayName)
                  Text(
                    e.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: value != null ? FontWeight.w600 : null,
              color:
                  value != null ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
          if (!e.isSelf)
            PopupMenuButton<String>(
              tooltip: 'Seçenekler',
              icon: Icon(Icons.more_vert_outlined,
                  size: 20, color: AppColors.textMuted),
              onSelected: (v) => switch (v) {
                'block' => _confirmBlock(e),
                'report' => _report(e.displayName, userId: e.userId),
                _ => _confirmLeave(e),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Text(
                    'Arkadaşlıktan çık',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text(
                    'Engelle',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
                const PopupMenuItem(value: 'report', child: Text('Bildir')),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Ayrıntılı değer paylaşımı için ayrı, açık onay: paylaşılacak değerler
  /// tek tek listelenir.
  Future<bool> _confirmDetails(FriendSharing s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ayrıntılı değerleri paylaş'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Onaylarsan tüm arkadaşların hedef gün sayısına ek olarak '
              'şunları görür:',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final label in s.detailValueLabels)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text('• $label'),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tarih ya da tekil kayıt paylaşılmaz. İstediğin zaman '
              'kapatabilirsin.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onaylıyorum'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _outgoing(ThemeData theme) {
    final list = ref.watch(outgoingRequestsProvider).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.grid),
      child: BentoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bekleyen istekler',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            for (final r in list)
              Row(
                children: [
                  Expanded(child: Text(r.targetEmail)),
                  TextButton(
                    onPressed: () => _run(
                      () => ref
                          .read(friendsRepositoryProvider)
                          .cancelRequest(r.id),
                    ),
                    child: const Text('İptal'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _sharing(ThemeData theme) {
    final async = ref.watch(mySharingProvider);
    return async.when(
      loading: _loading,
      error: (_, __) => _error(theme, () => ref.invalidate(mySharingProvider)),
      data: (s) {
        Future<void> save(FriendSharing next) => _run(
              () async => ref.read(friendsRepositoryProvider).saveSharing(next),
            );
        return BentoCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Hedef paylaşımı: arkadaşların yalnızca bu hafta hedefi '
                  'tutturduğun gün sayısını görür (ör. 3/5 gün). Adım, uyku '
                  'ya da kalori değerin paylaşılmaz.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Adım hedefi'),
                value: s.shareSteps,
                onChanged: (v) => save(s.copyWith(steps: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Uyku hedefi'),
                value: s.shareSleep,
                onChanged: (v) => save(s.copyWith(sleep: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kalori hedefi'),
                value: s.shareCalories,
                onChanged: (v) => save(s.copyWith(calories: v)),
              ),
              const Divider(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ayrıntılı değerleri de paylaş'),
                subtitle: Text(
                  !s.sharesAnyGoal
                      ? 'Önce en az bir hedef paylaşımını aç.'
                      : s.shareDetails
                          ? 'Arkadaşların görür: ${s.detailValueLabels.join('; ')}.'
                          : 'Kapalı: arkadaşların ham değerlerini görmez.',
                ),
                value: s.shareDetails,
                onChanged: !s.sharesAnyGoal && !s.shareDetails
                    ? null
                    : (v) async {
                        if (v && !await _confirmDetails(s)) return;
                        await save(s.copyWith(details: v));
                      },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => RitimAvatar(
        key: ValueKey('friend-avatar-${entry.userId}'),
        choice: entry.avatar,
        name: entry.displayName,
        email: entry.email,
        userId: entry.userId,
        size: 40,
      );
}

/// Bildirim onayı: isteğe bağlı kısa gerekçe ve "engelle" seçeneği.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.subject, required this.canBlock});

  final String subject;

  /// Engelleme seçeneği (kullanıcı kimliği biliniyorsa).
  final bool canBlock;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController();
  bool _block = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.subject} bildirilsin mi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('report-reason'),
            controller: _reason,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: 'Kısa gerekçe (isteğe bağlı)',
            ),
          ),
          if (widget.canBlock)
            CheckboxListTile(
              key: const ValueKey('report-block'),
              contentPadding: EdgeInsets.zero,
              value: _block,
              onChanged: (v) => setState(() => _block = v ?? false),
              title: const Text('Ayrıca engelle'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (reason: _reason.text.trim(), block: _block),
          ),
          child: Text('Bildir', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}
