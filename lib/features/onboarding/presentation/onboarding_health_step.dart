import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../health/presentation/health_providers.dart';
import 'onboarding_widgets.dart';

/// Apple Health izninin bu adımdaki durumu.
enum OnboardingHealthAccess { idle, requesting, granted, denied, unavailable }

/// 6. adım: sağlık kaynağı. Apple Sağlık ya da Google Health bağlanır;
/// bağlanan kaynak seçili sağlık kaynağı olur. Atlanabilir.
class OnboardingHealthStep extends ConsumerStatefulWidget {
  const OnboardingHealthStep({
    super.key,
    required this.access,
    required this.onRequest,
    required this.onSkip,
  });

  final OnboardingHealthAccess access;
  final VoidCallback onRequest;
  final VoidCallback onSkip;

  @override
  ConsumerState<OnboardingHealthStep> createState() =>
      _OnboardingHealthStepState();
}

class _OnboardingHealthStepState extends ConsumerState<OnboardingHealthStep> {
  bool _googleBusy = false;
  String? _googleError;
  HealthSourceKind? _confirmedFor;
  int? _todaySteps;

  @override
  void didUpdateWidget(OnboardingHealthStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access != OnboardingHealthAccess.granted &&
        widget.access == OnboardingHealthAccess.granted) {
      _activate(HealthSourceKind.appleHealth);
    }
  }

  Future<void> _activate(HealthSourceKind kind) async {
    final container = ProviderScope.containerOf(context, listen: false);
    if (kind == HealthSourceKind.appleHealth) {
      // Kullanıcı bu adımda Apple Sağlık'ı kendisi seçti: bu hesap için onay.
      final owner = container.read(healthRepositoryProvider).currentUserId;
      if (owner != null) {
        await container.read(appleHealthConsentProvider.notifier).grant(owner);
      }
      if (!mounted) return;
    }
    try {
      await selectHealthSource(container, kind);
    } catch (_) {
      // Seçim yazılamazsa bile okuma denenir.
    }
    if (!mounted || ref.read(healthSourceProvider) != kind) return;
    setState(() {
      _confirmedFor = kind;
      _todaySteps = null;
    });
    try {
      final snapshot = await ref.read(healthDataSourceProvider).readToday();
      if (!mounted || _confirmedFor != kind) return;
      if (snapshot.status == HealthStatus.ok) {
        setState(() => _todaySteps = snapshot.steps);
      }
    } catch (_) {
      // Onay metni adım sayısı olmadan gösterilir.
    }
  }

  Future<void> _connectGoogle() async {
    if (_googleBusy) return;
    setState(() {
      _googleBusy = true;
      _googleError = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    final error = await connectGoogleHealth(container);
    if (!mounted) return;
    final linked = ref.read(googleConnectionProvider).isLinked;
    setState(() {
      _googleBusy = false;
      _googleError = error;
    });
    if (error == null && linked) {
      await _activate(HealthSourceKind.googleHealth);
    }
  }

  String _appleStatus() => switch (widget.access) {
        OnboardingHealthAccess.granted => 'İzin verildi.',
        OnboardingHealthAccess.denied =>
          'İzin verilmedi. iPhone Ayarlar > Sağlık > Veri Erişimi\'nden '
              'açabilirsin.',
        OnboardingHealthAccess.unavailable =>
          'Bu cihazda Apple Sağlık yok. Verilerini elle girebilirsin.',
        OnboardingHealthAccess.requesting => 'İzin isteniyor…',
        OnboardingHealthAccess.idle =>
          'Adım, uyku ve aktif kalori Apple Sağlık\'tan okunur.',
      };

  String _googleStatus(GoogleLinkState link, bool selected) {
    if (_googleError != null) return _googleError!;
    return switch (link.status) {
      GoogleLinkStatus.notConfigured =>
        'Bu derlemede Google Health kullanılamıyor.',
      GoogleLinkStatus.connecting => 'Google\'a bağlanılıyor…',
      GoogleLinkStatus.connected => selected
          ? 'Bağlandı${link.email == null ? '' : ': ${link.email}'}.'
          : 'Hesap bağlı. Kaynak olarak seçmek için dokun.',
      GoogleLinkStatus.reconnect =>
        link.message ?? 'Google\'a yeniden bağlanman gerekiyor.',
      GoogleLinkStatus.disconnected =>
        'Adım, uyku ve aktif kalori Google Health\'ten okunur.',
    };
  }

  String? _confirmation() {
    final kind = _confirmedFor;
    if (kind == null) return null;
    final name = kind == HealthSourceKind.appleHealth
        ? 'Apple Sağlık'
        : 'Google Health';
    final steps = _todaySteps;
    return steps == null
        ? '$name bağlandı.'
        : '$name bağlandı. Bugün $steps adım.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = ref.watch(healthSourceProvider);
    final link = ref.watch(googleConnectionProvider);
    final appleDone = widget.access == OnboardingHealthAccess.granted;
    final googleSelected = source == HealthSourceKind.googleHealth &&
        link.status == GoogleLinkStatus.connected;
    final googleBusy =
        _googleBusy || link.status == GoogleLinkStatus.connecting;
    final confirmation = _confirmation();

    TextStyle? status(bool ok) => theme.textTheme.bodyMedium?.copyWith(
          color: ok ? AppColors.accent : AppColors.textSecondary,
          height: 1.4,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingStepHeader(
          title: 'Sağlık verisi',
          subtitle: 'Adım, uyku ve aktif kalori için bir kaynak seç. '
              'Atlayıp sonra da yapabilirsin.',
        ),
        BentoCard(
          tint: appleDone && source == HealthSourceKind.appleHealth
              ? AppColors.accent
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.favorite_rounded,
                label: 'Apple Sağlık',
                color: AppColors.danger,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(_appleStatus(), style: status(appleDone)),
              if (!appleDone &&
                  widget.access != OnboardingHealthAccess.unavailable)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    key: const Key('onboarding-health-request'),
                    onPressed:
                        widget.access == OnboardingHealthAccess.requesting
                            ? null
                            : widget.onRequest,
                    child: const Text('Apple Sağlık izni ver'),
                  ),
                )
              else if (appleDone && source != HealthSourceKind.appleHealth)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const Key('onboarding-health-apple-select'),
                    onPressed: () => _activate(HealthSourceKind.appleHealth),
                    child: const Text('Kaynak olarak seç'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BentoCard(
          tint: googleSelected ? AppColors.accent : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BentoLabel(
                icon: Icons.monitor_heart_rounded,
                label: 'Google Health',
                color: AppColors.accent,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _googleStatus(link, googleSelected),
                style: status(googleSelected && _googleError == null),
              ),
              if (link.status != GoogleLinkStatus.notConfigured &&
                  !googleSelected)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    key: const Key('onboarding-health-google'),
                    onPressed: googleBusy ? null : _connectGoogle,
                    child: Text(
                      link.status == GoogleLinkStatus.connected
                          ? 'Google Health\'i seç'
                          : 'Google\'a bağlan',
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (confirmation != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            confirmation,
            key: const Key('onboarding-health-confirmation'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        Align(
          alignment: AlignmentDirectional.center,
          child: TextButton(
            key: const Key('onboarding-health-skip'),
            onPressed: widget.onSkip,
            child: const Text('Şimdilik atla'),
          ),
        ),
        const OnboardingHint(
          'Aynı anda tek kaynak veri yazar. Kaynağı sonra Hesap > '
          'Bağlantılar\'dan değiştirebilirsin.',
        ),
      ],
    );
  }
}
