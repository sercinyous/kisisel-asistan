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

  Future<void> _reconnectHealth(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    var granted = false;
    try {
      granted = await ref.read(healthServiceProvider).requestAccess();
    } catch (_) {
      granted = false;
    }
    // İlk izinle birlikte son günler de okunur ve yedeklenir.
    unawaited(resyncHealthKit(container));
    if (granted) return;
    showSettingsSnack(
      messenger,
      'İzin verilmedi. iPhone Ayarlar > Sağlık > Veri Erişimi '
      'bölümünden açabilirsin.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthTodayProvider);
    // Apple satırı yalnızca Apple Health seçiliyken HealthKit okumasını
    // yorumlar; Google seçiliyken okuma Google'ındır.
    final appleActive =
        ref.watch(healthSourceProvider) == HealthSourceKind.appleHealth;

    final (healthText, healthColor) = !appleActive
        ? ('Kaynak olarak seçili değil', AppColors.textMuted)
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
              HealthStatus.notConnected ||
              HealthStatus.reconnect ||
              HealthStatus.failed =>
                ('Okunamadı', AppColors.warning),
            },
          );
    final healthUnavailable =
        !appleActive || health.valueOrNull?.status == HealthStatus.unavailable;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Bağlantılar')),
      body: ListView(
        padding: settingsListPadding,
        children: [
          SettingsSection(
            icon: Icons.link_rounded,
            title: 'Sağlık verisi',
            color: AppColors.nutrition,
            children: [
              const HealthSourcePicker(),
              const Divider(height: 24),
              SettingsStatusRow(
                icon: Icons.favorite_rounded,
                title: 'Apple Sağlık',
                status: healthText,
                statusColor: healthColor,
                actionLabel: 'Yeniden bağlan',
                onAction: health.isLoading || healthUnavailable
                    ? null
                    : () => _reconnectHealth(context, ref),
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
