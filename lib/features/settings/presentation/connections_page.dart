import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../health/presentation/health_providers.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import 'health_source_settings.dart';
import 'settings_widgets.dart';

/// Hesap › Bağlantılar: sağlık kaynağı, Apple Sağlık ve Google Health.
class ConnectionsPage extends ConsumerWidget {
  const ConnectionsPage({super.key});

  /// Apple Sağlık bağlantısı tek dokunuşla: HealthKit izin penceresi her
  /// seferinde istenir, [select] ise kaynak Apple Sağlık'a geçer, ardından bu
  /// hesap için onay verilir ve son günler okunup yedeklenir.
  Future<void> _connectAppleHealth(
    BuildContext context,
    WidgetRef ref, {
    required bool select,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    var granted = false;
    try {
      granted = await ref.read(healthServiceProvider).requestAccess();
    } catch (_) {
      granted = false;
    }
    if (!granted) {
      showSettingsSnack(
        messenger,
        'İzin verilmedi. iPhone Ayarlar > Sağlık > Veri Erişimi '
        'bölümünden açabilirsin.',
      );
      return;
    }
    if (select) {
      try {
        await selectHealthSource(container, HealthSourceKind.appleHealth);
      } catch (_) {
        // Seçim yazılamazsa onay yine verilir.
      }
    }
    // Onay (bu hesap için) + yeniden okuma; onay yoksa okuma "bağlı değil" kalır.
    await approveAppleHealth(container);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthTodayProvider);
    // Apple satırı yalnızca Apple Health seçiliyken HealthKit okumasını
    // yorumlar; Google seçiliyken okuma Google'ındır.
    final appleActive =
        ref.watch(healthSourceProvider) == HealthSourceKind.appleHealth;

    final (healthText, healthColor) = !appleActive
        ? (
            'Pasif: Google Health seçili, Apple Sağlık\'tan veri okunmuyor.',
            AppColors.textMuted
          )
        : health.when(
            skipLoadingOnRefresh: false,
            loading: () => ('Kontrol ediliyor…', AppColors.textMuted),
            error: (_, __) => ('Okunamadı', AppColors.warning),
            data: (s) => switch (s.status) {
              HealthStatus.ok when s.hasData => ('Bağlı', AppColors.accent),
              HealthStatus.ok => (
                  'Bağlı, bugün için veri yok',
                  AppColors.textSecondary
                ),
              HealthStatus.denied => ('İzin verilmedi', AppColors.warning),
              HealthStatus.unavailable => (
                  'Bu cihazda kullanılamıyor',
                  AppColors.textMuted
                ),
              HealthStatus.notConnected => (
                  'Bu hesap için onay gerekli',
                  AppColors.warning
                ),
              HealthStatus.reconnect ||
              HealthStatus.failed =>
                ('Okunamadı', AppColors.warning),
            },
          );
    final healthUnavailable = appleActive &&
        health.valueOrNull?.status == HealthStatus.unavailable;
    final needsConsent =
        appleActive && health.valueOrNull?.status == HealthStatus.notConnected;
    final appleAction = !appleActive
        ? 'Bağlan ve seç'
        : needsConsent
            ? 'Bağla'
            : 'Yeniden bağlan';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Bağlantılar')),
      body: ListView(
        padding: settingsListPadding,
        children: [
          SettingsSection(
            icon: Icons.link_outlined,
            title: 'Sağlık verisi',
            color: AppColors.nutrition,
            children: [
              const HealthSourcePicker(),
              const Divider(height: 24),
              HealthSourceDim(
                active: appleActive,
                child: SettingsStatusRow(
                  icon: Icons.favorite_rounded,
                  title: 'Apple Sağlık',
                  trailing: HealthSourceStateBadge(
                    key: const Key('apple-source-state'),
                    active: appleActive,
                  ),
                  status: healthText,
                  statusColor: healthColor,
                  actionLabel: appleAction,
                  onAction: (appleActive && health.isLoading) ||
                          healthUnavailable
                      ? null
                      : () => _connectAppleHealth(
                            context,
                            ref,
                            select: !appleActive,
                          ),
                ),
              ),
              const Divider(height: 16),
              const GoogleHealthRow(),
            ],
          ),
        ],
      ),
    );
  }
}
