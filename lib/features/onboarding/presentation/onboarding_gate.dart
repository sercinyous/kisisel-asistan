import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/error_reporter.dart';

import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_top/ritim_top.dart';
import '../../settings/presentation/settings_providers.dart';
import '../../shell/presentation/home_shell.dart';
import 'onboarding_screen.dart';

/// Kullanıcının ilk kurulumu bitirip bitirmediği (`onboarded_at` dolu mu).
/// Kullanıcı kimliğiyle anahtarlıdır: hesap değişince önceki kullanıcının
/// değeri yeni kullanıcıya sızmaz. Ayar satırı aynı kullanıcı için yeniden
/// okunurken (ör. profil düzenlemesi sonrası) önceki değer korunur.
final onboardedProvider =
    FutureProvider.family<bool, String>((ref, userId) async {
  final settings = await ref.watch(userSettingsProvider.future);
  return settings.onboardedAt != null;
});

/// Giriş sonrası kapı: ilk kurulum bitmediyse kılavuz ve sorular, bittiyse
/// ana kabuk ([child]).
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, this.child = const HomeShell()});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(
          authSessionProvider.select((s) => s.valueOrNull?.user.id),
        ) ??
        '';
    ref.listen<AsyncValue<bool>>(onboardedProvider(userId), (previous, next) {
      if (next case AsyncError(:final error, :final stackTrace)
          when previous is! AsyncError) {
        ref.read(reportErrorProvider)(error, stackTrace);
      }
    });
    final onboarded = ref.watch(onboardedProvider(userId));
    // Yeniden okuma sürerken önceki değer kullanılır; ana kabuk sökülmez.
    final value = onboarded.valueOrNull;
    if (value != null) return value ? child : const OnboardingScreen();
    if (onboarded.hasError) {
      return _SettingsLoadError(
        code: technicalErrorCode(onboarded.error!),
        onRetry: () => ref
          ..invalidate(userSettingsProvider)
          ..invalidate(onboardedProvider(userId)),
      );
    }
    return const Scaffold(body: Center(child: RitimTop(size: 72)));
  }
}

class _SettingsLoadError extends StatelessWidget {
  const _SettingsLoadError({required this.code, required this.onRetry});

  final String code;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page * 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 40, color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text(
                  'Hesabın yüklenemedi',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Bağlantını kontrol edip tekrar dene.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  code,
                  key: const Key('onboarding-error-code'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('onboarding-retry'),
                  onPressed: onRetry,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hata ekranında gösterilen kısa teknik kod (destek için): PostgREST kodu,
/// HTTP durumu ya da istisna türü.
String technicalErrorCode(Object error) => switch (error) {
      PostgrestException(:final code) when code != null && code.isNotEmpty =>
        'Kod: PG $code',
      PostgrestException() => 'Kod: PostgrestException',
      AuthException(:final statusCode) when statusCode != null =>
        'Kod: AUTH $statusCode',
      AuthException() => 'Kod: AuthException',
      StorageException(:final statusCode) when statusCode != null =>
        'Kod: HTTP $statusCode',
      SocketException() => 'Kod: NET SocketException',
      ClientException() => 'Kod: NET ClientException',
      TimeoutException() => 'Kod: NET Timeout',
      _ => 'Kod: ${error.runtimeType}',
    };
