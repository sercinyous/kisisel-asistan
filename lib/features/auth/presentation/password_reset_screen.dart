import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/sign_in_backend.dart';
import '../domain/sign_in_messages.dart';
import 'sign_in_screen.dart';

/// Kod gönderildikten sonra (adres kayıtlı olsun olmasın) gösterilen metin.
const String resetCodeSentMessage =
    'Bu adres kayıtlıysa e-postana 6 haneli bir kod gönderdik. '
    'Gelen kutunu (ve spam) kontrol et.';

/// "Şifremi unuttum": e-postaya kod gönderilir, kod ve yeni şifreyle
/// sıfırlanır. Derin bağlantı gerektirmez (kod uygulamada yazılır).
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  String _message(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (e.code == 'otp_expired' ||
          m.contains('expired') ||
          m.contains('invalid')) {
        return 'Kod hatalı ya da süresi dolmuş. Yeni kod iste.';
      }
      if (e.code == 'same_password') {
        return 'Yeni şifre eskisiyle aynı olamaz.';
      }
    }
    return signInErrorMessage(e) ?? connectionFailedMessage;
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final backend = ref.read(signInBackendProvider);
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await backend.sendPasswordReset(email: email);
        if (!mounted) return;
        setState(() {
          _codeSent = true;
          _info = resetCodeSentMessage;
        });
      } else {
        await backend.resetPassword(
          email: email,
          code: _code.text.trim(),
          newPassword: _password.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Şifren güncellendi.')),
        );
        Navigator.of(context).maybePop();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      // Kod isteğinde adres kayıtlı mı belli olmasın: hız sınırı dışındaki
      // her durumda aynı bilgi gösterilir.
      if (!_codeSent && !(e is AuthException && e.statusCode == '429')) {
        setState(() {
          _codeSent = true;
          _info = resetCodeSentMessage;
        });
      } else {
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Şifremi unuttum')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _codeSent
                      ? 'E-postana gelen kodu ve yeni şifreni yaz.'
                      : 'Hesabının e-posta adresini yaz; sana bir kod '
                          'gönderelim.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  key: const Key('reset-email'),
                  controller: _email,
                  enabled: !_codeSent && !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(hintText: 'E-posta'),
                  validator: (v) =>
                      isValidEmail(v) ? null : 'Geçerli bir e-posta gir.',
                ),
                if (_codeSent) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('reset-code'),
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
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const Key('reset-password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration:
                        const InputDecoration(hintText: 'Yeni şifre'),
                    validator: (v) => (v ?? '').length >= minPasswordLength
                        ? null
                        : 'Şifre en az $minPasswordLength karakter olmalı.',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                if (_info != null && _error == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _info!,
                    key: const Key('reset-info'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    key: const Key('reset-error'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  key: const Key('reset-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_codeSent ? 'Şifreyi güncelle' : 'Kod gönder'),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _info = null;
                              _error = null;
                            }),
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
