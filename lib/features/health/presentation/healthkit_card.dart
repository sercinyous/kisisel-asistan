import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/bento.dart';
import '../../kokpit/presentation/kokpit_format.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import 'health_providers.dart';
import 'health_widgets.dart';

/// Kartın düğmesinin yaptığı iş.
enum _CardAction { resync, connectGoogle, approveApple }

/// Sağlık verisi kaynağının durumu: etkin kaynak (HealthKit ya da Google
/// Health), son eşitleme ve yeniden bağlanma.
class HealthKitCard extends ConsumerWidget {
  const HealthKitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final health = ref.watch(healthTodayProvider);
    final selected = ref.watch(healthSourceProvider);
    final snapshot = health.valueOrNull;
    final readAt = snapshot?.readAt;
    // Yeni kaynağın okuması sürerken başlık seçili kaynağı gösterir.
    final source = health.isLoading ? selected : snapshot?.source ?? selected;

    final (String message, String? action, _CardAction kind) = health.when(
      skipLoadingOnRefresh: true,
      loading: () =>
          ('${source.shortLabel} okunuyor…', null, _CardAction.resync),
      error: (_, __) => (
        '${source.shortLabel} verisi okunamadı.',
        'Tekrar dene',
        _CardAction.resync,
      ),
      data: (data) => data.source == HealthSourceKind.googleHealth
          ? _googleMessage(data)
          : _healthKitMessage(data),
    );

    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.favorite_rounded,
            label: source.shortLabel,
            color: AppColors.danger,
            trailing: health.isLoading || readAt == null
                ? null
                : 'son eşitleme ${AppDates.hourMinute(readAt)}',
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: health.isLoading ? null : () => _run(context, kind),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(healthMinTouch, healthMinTouch),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(action),
              ),
            ),
        ],
      ),
    );
  }

  static (String, String?, _CardAction) _healthKitMessage(
          HealthSnapshot data) =>
      switch (data.status) {
        HealthStatus.unavailable => (
            'Adım, uyku ve aktif kalori yalnızca iPhone\'da HealthKit '
                'üzerinden okunur.',
            null,
            _CardAction.resync,
          ),
        HealthStatus.denied => (
            'HealthKit erişimi verilmedi. Sağlık uygulaması > Paylaşım > '
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
        HealthStatus.reconnect ||
        HealthStatus.failed =>
          (
            data.message ?? 'HealthKit verisi okunamadı.',
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
