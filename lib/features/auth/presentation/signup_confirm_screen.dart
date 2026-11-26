import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/sign_in_backend.dart';
import '../domain/sign_in_messages.dart';

/// Kayıttan sonra e-postaya gelen 6 haneli onay kodu uygulamada yazılır;
/// bağlantı (Site URL) telefonda açılmasa da hesap onaylanır.
class SignupConfirmScreen extends ConsumerStatefulWidget {
  const SignupConfirmScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<SignupConfirmScreen> createState() =>
      _SignupConfirmScreenState();
}

class _SignupConfirmScreenState extends ConsumerState<SignupConfirmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _message(Object e) {
    if (e is AuthException) {
      if (e.statusCode == '429' || e.code == 'over_email_send_rate_limit') {
        return 'Çok sık denedin. Bir dakika sonra tekrar dene.';
      }
      final m = e.message.toLowerCase();
      if (e.code == 'otp_expired' ||
          m.contains('expired') ||
          m.contains('invalid')) {
        return 'Kod hatalı ya da süresi dolmuş. Kodu yeniden gönder.';
      }
    }
    return signInErrorMessage(e) ?? connectionFailedMessage;
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (done != null) setState(() => _info = done);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final backend = ref.read(signInBackendProvider);
    var ok = false;
    await _run(() async {
      await backend.verifySignupCode(
          email: widget.email, code: _code.text.trim());
      ok = true;
    });
    // Oturum açıldı; kapı ana ekrana geçer.
    if (ok && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _resend() => _run(
        () => ref
            .read(signInBackendProvider)
            .resendSignupCode(email: widget.email),
        done: 'Yeni kod gönderildi.',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('E-postanı onayla')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.email} adresine gelen 6 haneli kodu yaz.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('confirm-code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 10,
                  decoration: const InputDecoration(
                    hintText: 'Kod',
                    counterText: '',
                  ),
                  validator: (v) => (v ?? '').trim().length >= 6
                      ? null
                      : 'E-postadaki kodu gir.',
                  onFieldSubmitted: (_) => _verify(),
                ),
                if (_info != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _info!,
                    key: const Key('confirm-info'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    key: const Key('confirm-error'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('confirm-submit'),
                  onPressed: _busy ? null : _verify,
                  child: const Text('Onayla'),
                ),
                TextButton(
                  key: const Key('confirm-resend'),
                  onPressed: _busy ? null : _resend,
                  child: const Text('Kodu yeniden gönder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
