import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// Kartın düğmesinin yaptığı iş.
enum _CardAction { resync, connectGoogle, approveApple }

/// Sağlık kaynağı başlığının (HealthSourceBanner) metin ve eylem yardımcıları.
abstract final class _HealthSourceActions {
  static (String, String?, _CardAction) _healthKitMessage(
          HealthSnapshot data) =>
      switch (data.status) {
        HealthStatus.unavailable => (
            'Adım, uyku ve aktif kalori yalnızca iPhone\'da Apple Sağlık '
                'üzerinden okunur.',
            null,
            _CardAction.resync,
          ),
        HealthStatus.denied => (
            'Apple Sağlık erişimi verilmedi. Sağlık uygulaması > Paylaşım > '
                'Uygulamalar bölümünden izin verebilirsin.',
            'Yeniden bağlan',
            _CardAction.resync,
          ),
        HealthStatus.ok => (
            data.hasData
                ? 'Adım, uyku ve aktif kalori Sağlık uygulamasından okunuyor. '
                    'Dün gece uyku: ${KokpitFormat.sleep(data.sleepMinutes)}.'
                : 'Bağlı, ancak bugün için veri gelmedi. Saatin ya da '
                    'telefonun Sağlık uygulamasına yazdığından emin ol.',
            'Yeniden bağlan',
            _CardAction.resync,
          ),
        HealthStatus.notConnected => (
            data.message ?? appleHealthConsentMessage,
            'Bu hesap için onayla',
            _CardAction.approveApple,
          ),
        HealthStatus.reconnect || HealthStatus.failed => (
            data.message ?? 'Apple Sağlık verisi okunamadı.',
            'Tekrar dene',
            _CardAction.resync,
          ),
      };

  static (String, String?, _CardAction) _googleMessage(HealthSnapshot data) =>
      switch (data.status) {
        HealthStatus.ok => (
            data.hasData
                ? 'Adım, uyku ve aktif kalori Google Health\'ten (Fitbit) '
                    'okunuyor. Dün gece uyku: '
                    '${KokpitFormat.sleep(data.sleepMinutes)}.'
                : 'Bağlı, ancak bugün için veri gelmedi. Fitbit uygulamasının '
                    'eşitlendiğinden emin ol.',
            'Şimdi eşitle',
            _CardAction.resync,
          ),
        HealthStatus.unavailable => (
            data.message ??
                'Google ile bağlantı bu derlemede yapılandırılmamış.',
            null,
            _CardAction.resync,
          ),
        HealthStatus.notConnected => (
            data.message ?? 'Google Health bağlı değil.',
            'Google ile bağlan',
            _CardAction.connectGoogle,
          ),
        HealthStatus.reconnect => (
            data.message ??
                'Google oturumunun süresi doldu. Google\'a yeniden bağlan.',
            'Google\'a yeniden bağlan',
            _CardAction.connectGoogle,
          ),
        HealthStatus.denied || HealthStatus.failed => (
            data.message ?? 'Google Health verisi okunamadı.',
            'Tekrar dene',
            _CardAction.resync,
          ),
      };

  static Future<void> _run(BuildContext context, _CardAction kind) async {
    final container = ProviderScope.containerOf(context, listen: false);
    switch (kind) {
      case _CardAction.resync:
        await resyncHealthKit(container);
      case _CardAction.approveApple:
        await approveAppleHealth(container);
      case _CardAction.connectGoogle:
        final messenger = ScaffoldMessenger.of(context);
        final error = await connectGoogleHealth(container);
        if (error == null) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Sağlık sekmesinin üstünde, yalnızca kaynakta sorun varken (bağlı değil,
/// onay gerekli, erişim yok, okuma hatası) görünen tek satırlık uyarı.
/// Kaynağın tüm ayarları Hesap › Bağlantılar'dadır.
class HealthSourceBanner extends ConsumerWidget {
  const HealthSourceBanner({super.key});

  static bool _isProblem(HealthStatus status) => switch (status) {
        HealthStatus.ok || HealthStatus.unavailable => false,
        HealthStatus.denied ||
        HealthStatus.notConnected ||
        HealthStatus.reconnect ||
        HealthStatus.failed =>
          true,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthTodayProvider);
    final selected = ref.watch(healthSourceProvider);
    if (health.isLoading && !health.hasValue && !health.hasError) {
      return const SizedBox.shrink();
    }
    final snapshot = health.valueOrNull;
    final (String, String?, _CardAction) content;
    if (health.hasError && snapshot == null) {
      content = (
        '${selected.shortLabel} verisi okunamadı.',
        'Tekrar dene',
        _CardAction.resync,
      );
    } else if (snapshot != null && _isProblem(snapshot.status)) {
      content = snapshot.source == HealthSourceKind.googleHealth
          ? _HealthSourceActions._googleMessage(snapshot)
          : _HealthSourceActions._healthKitMessage(snapshot);
    } else {
      return const SizedBox.shrink();
    }
    final (message, action, kind) = content;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.grid),
      child: BentoCard(
        key: const Key('health-source-banner'),
        tint: AppColors.warning,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_outlined,
                size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: message,
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: health.isLoading
                    ? null
                    : () => _HealthSourceActions._run(context, kind),
                style: TextButton.styleFrom(
                  minimumSize: const Size(healthMinTouch, healthMinTouch),
                ),
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}
