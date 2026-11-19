import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_sync.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../data/account_repository.dart';

/// Hesap > Profil ve hedefler > Hesabımı sil: neyin silineceğini anlatır, "SİL" yazılınca
/// sunucuda hesabı ve tüm verisini siler, cihazı temizler, oturumu kapatır.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  static const List<String> _deleted = [
    'Profilin, hedeflerin ve tüm ayarların',
    'Görevler, notlar, rutinler ve hatırlatıcılar',
    'Öğünler, su, kilo ve sağlık özetleri (adım, uyku, kalori)',
    'Günlük ve haftalık raporlar, AI kullanım sayaçları',
    'Arkadaşlıkların (iki taraftan da), gönderdiğin ve sana gelen davetler',
    'Paylaşım ayarların, gönderdiğin hata kayıtları ve geri bildirimler',
    'Bu cihazdaki hesabına ait tercihler',
  ];

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirm.text.trim().replaceAll('i', 'İ').toUpperCase() ==
      AccountRepository.confirmWord;

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final repository = ref.read(accountRepositoryProvider);
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.deleteAccount();
    } on AccountActionException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    // Hesap sunucuda silindi; buradan sonraki adımlar hata verse de sürer.
    try {
      await ref
          .read(notificationSyncQueueProvider)
          .endSession(ref.read(notificationServiceProvider));
    } catch (_) {}
    if (userId != null) await repository.clearLocalData(userId);
    try {
      await client.auth.signOut();
    } catch (_) {}
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabımı sil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.md,
          AppSpacing.page,
          120,
        ),
        children: [
          BentoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Bu işlem geri alınamaz',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Hesabın ve sunucudaki tüm verin hemen ve kalıcı olarak '
                  'silinir. Yedekten geri getirilemez.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final item in _deleted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.remove_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(item, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Apple Sağlık ya da Google Health\'teki kayıtların bu '
                  'uygulamaya ait değildir, onlara dokunulmaz. Arkadaşların '
                  'artık seni listelerinde görmez.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Onaylamak için SİL yaz',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('delete-account-confirm'),
            controller: _confirm,
            enabled: !_busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'SİL'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            key: const Key('delete-account-submit'),
            onPressed: _confirmed && !_busy ? _delete : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.onAccent,
            ),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onAccent,
                    ),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label: Text(_busy ? 'Siliniyor…' : 'Hesabımı kalıcı olarak sil'),
          ),
        ],
      ),
    );
  }
}
