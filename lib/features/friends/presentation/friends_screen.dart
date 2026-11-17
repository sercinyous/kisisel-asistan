import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../data/friends_repository.dart';
import '../domain/friends_models.dart';
import 'friends_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _toast('İşlem yapılamadı. Bağlantını kontrol edip tekrar dene.');
    }
    if (mounted) refreshFriends(ref);
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

  Future<void> _confirmLeave(Friend f) async {
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
      await _run(() => ref.read(friendsRepositoryProvider).leave(f.friendId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, AppSpacing.section, AppSpacing.xs, 8),
          child: Text(t, style: theme.textTheme.titleMedium),
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Arkadaşlar')),
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
          children: [
            title('Davetler'),
            _incoming(theme),
            title('Arkadaşlar'),
            _friendList(theme),
            title('Arkadaş ekle'),
            BentoCard(
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
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_sending ? 'Gönderiliyor…' : 'İstek gönder'),
                  ),
                ],
              ),
            ),
            _outgoing(theme),
            title('Paylaşım anahtarları'),
            _sharing(theme),
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
        if (list.isEmpty) return _message(theme, 'Bekleyen davet yok.');
        return Column(
          children: [
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.grid),
                child: BentoCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.fromName.isEmpty ? 'Bir kullanıcı' : r.fromName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reddet',
                        color: AppColors.danger,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _run(() => ref
                            .read(friendsRepositoryProvider)
                            .respond(r.id, accept: false)),
                      ),
                      IconButton(
                        tooltip: 'Kabul et',
                        color: AppColors.accent,
                        icon: const Icon(Icons.check_rounded),
                        onPressed: () => _run(() => ref
                            .read(friendsRepositoryProvider)
                            .respond(r.id, accept: true)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _friendList(ThemeData theme) {
    final async = ref.watch(friendsWithSummaryProvider);
    return async.when(
      loading: _loading,
      error: (_, __) =>
          _error(theme, () => ref.invalidate(friendsWithSummaryProvider)),
      data: (list) {
        if (list.isEmpty) {
          return _message(theme, 'Henüz arkadaşın yok. E-postayla davet et.');
        }
        return Column(
          children: [
            for (final item in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.grid),
                child: BentoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.friend.displayName,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _confirmLeave(item.friend),
                            child: Text(
                              'Arkadaşlıktan çık',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Bu hafta hedef günleri',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final s in item.summaries)
                        if (s.metric != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(child: Text(s.metric!.label)),
                                Text(
                                  s.shared
                                      ? '${s.goalDays}/${s.dataDays} gün'
                                      : 'paylaşmıyor',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: s.shared
                                        ? AppColors.textPrimary
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
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
                      () => ref.read(friendsRepositoryProvider).cancelRequest(r.id),
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
            children: [
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
                subtitle: const Text(
                  'Arkadaşlar yalnızca hedefi tutturduğun gün sayısını görür.',
                ),
                value: s.shareCalories,
                onChanged: (v) => save(s.copyWith(calories: v)),
              ),
            ],
          ),
        );
      },
    );
  }
}
