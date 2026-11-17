import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../health/presentation/health_providers.dart';
import '../../kokpit/presentation/kokpit_providers.dart';

/// Ayarlar > Bağlantılar: "Sağlık verisi kaynağı" seçimi (Apple Health |
/// Google Health). Seçim cihazda saklanır ve hemen yeni kaynaktan eşitlenir.
class HealthSourcePicker extends ConsumerWidget {
  const HealthSourcePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final source = ref.watch(healthSourceProvider);
    final configured = ref.watch(googleConfiguredProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sağlık verisi kaynağı',
          style:
              theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        SegmentedButton<HealthSourceKind>(
          key: const Key('settings-health-source'),
          showSelectedIcon: false,
          segments: [
            for (final kind in HealthSourceKind.values)
              ButtonSegment(
                value: kind,
                enabled: kind != HealthSourceKind.googleHealth || configured,
                label: Text(
                  kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: {source},
          onSelectionChanged: (selection) => selectHealthSource(
            ProviderScope.containerOf(context, listen: false),
            selection.first,
          ),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textSecondary,
            selectedBackgroundColor: AppColors.surfaceHigh,
            selectedForegroundColor: AppColors.accent,
            disabledForegroundColor: AppColors.textMuted,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.inner),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          configured
              ? 'Adım, uyku ve aktif kalori yalnızca seçili kaynaktan okunur; '
                  'ikisi birlikte sayılmaz.'
              : 'Google Health için derlemeye GOOGLE_IOS_CLIENT_ID verilmeli '
                  '(README > Google Health ile bağlantı).',
          style:
              theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Google Health (Fitbit) bağlantı satırı: yapılandırılmamış / bağlı değil /
/// bağlı (hesap + son eşitleme) / yeniden bağlanmalı.
class GoogleHealthRow extends ConsumerStatefulWidget {
  const GoogleHealthRow({super.key});

  @override
  ConsumerState<GoogleHealthRow> createState() => _GoogleHealthRowState();
}

class _GoogleHealthRowState extends ConsumerState<GoogleHealthRow> {
  bool _syncing = false;
  bool _disconnecting = false;

  void _show(ScaffoldMessengerState messenger, String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final error = await connectGoogleHealth(container);
    if (error != null) _show(messenger, error);
  }

  Future<void> _sync() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    await resyncHealthKit(container);
    if (mounted) setState(() => _syncing = false);
    final snapshot = container.read(healthTodayProvider).valueOrNull;
    _show(
      messenger,
      snapshot?.status == HealthStatus.ok
          ? 'Google Health eşitlendi.'
          : snapshot?.message ?? 'Google Health eşitlenemedi.',
    );
  }

  Future<void> _disconnect() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Google bağlantısı kesilsin mi?'),
        content: const Text(
          'Google Health erişim izni geri alınır. Daha önce kaydedilen '
          'günlük değerler ve içe aktarılan antrenmanlar silinmez.',
        ),
        actions: [
          TextButton(
            key: const Key('settings-google-disconnect-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            key: const Key('settings-google-disconnect-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Bağlantıyı kes',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _disconnecting = true);
    await disconnectGoogleHealth(container);
    if (mounted) setState(() => _disconnecting = false);
    _show(messenger, 'Google bağlantısı kesildi.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = ref.watch(googleConnectionProvider);
    final googleSelected =
        ref.watch(healthSourceProvider) == HealthSourceKind.googleHealth;
    final busy = _syncing || _disconnecting;
    final lastSync = link.lastSyncAt;
    final syncText = lastSync == null
        ? 'Henüz eşitlenmedi'
        : 'Son eşitleme: ${AppDates.relativeDayTime(lastSync)}';

    final (String status, Color statusColor, String? detail) =
        switch (link.status) {
      GoogleLinkStatus.notConfigured => (
          'Bu derlemede yapılandırılmamış',
          AppColors.textMuted,
          'Derlemeye GOOGLE_IOS_CLIENT_ID verilmedi.',
        ),
      GoogleLinkStatus.disconnected => (
          'Bağlı değil',
          AppColors.textMuted,
          'Fitbit verilerin Google hesabından okunur.',
        ),
      GoogleLinkStatus.connecting => (
          'Bağlanıyor…',
          AppColors.textMuted,
          null,
        ),
      GoogleLinkStatus.connected => (
          link.email ?? 'Bağlı',
          AppColors.accent,
          googleSelected
              ? syncText
              : '$syncText · Kaynak olarak seçilince veriler buradan okunur.',
        ),
      GoogleLinkStatus.reconnect => (
          link.message ?? 'Google\'a yeniden bağlanman gerekiyor.',
          AppColors.warning,
          [if (link.email != null) link.email!, syncText].join(' · '),
        ),
    };

    final actions = <Widget>[
      if (link.status == GoogleLinkStatus.disconnected ||
          link.status == GoogleLinkStatus.connecting)
        TextButton(
          key: const Key('settings-google-connect'),
          onPressed:
              link.status == GoogleLinkStatus.connecting ? null : _connect,
          child: const Text('Google ile bağlan'),
        ),
      if (link.status == GoogleLinkStatus.reconnect)
        TextButton(
          key: const Key('settings-google-connect'),
          onPressed: busy ? null : _connect,
          child: const Text('Google\'a yeniden bağlan'),
        ),
      if (link.status == GoogleLinkStatus.connected)
        TextButton(
          key: const Key('settings-google-sync'),
          onPressed: googleSelected && !busy ? _sync : null,
          child: Text(_syncing ? 'Eşitleniyor…' : 'Şimdi eşitle'),
        ),
      if (link.isLinked)
        TextButton(
          key: const Key('settings-google-disconnect'),
          onPressed: busy ? null : _disconnect,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Bağlantıyı kes'),
        ),
    ];

    return Column(
      key: const Key('settings-google-row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.watch_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Google Health (Fitbit)',
                      style: theme.textTheme.bodyLarge),
                  Text(
                    status,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: statusColor),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: actions,
            ),
          ),
      ],
    );
  }
}
