import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ritim_top/ritim_top.dart';
import '../../../core/widgets/sunset_stripe.dart';
import 'password_reset_screen.dart';
import 'sign_in_controller.dart';

/// Giriş ekranı: "Google ile devam et" ana yoldur, e-posta/şifre ikincildir.
/// Google yapılandırılmamışsa (ya da tarayıcı demosunda) yalnızca e-posta
/// formu görünür. Kayıt herkese açıktır: Google ilk girişte hesap açar, e-posta
/// formunda "Kayıt ol" ile yeni hesap oluşturulur.
/// Yeni hesap şifresinin en kısa uzunluğu.
const int minPasswordLength = 8;

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Basit e-posta denetimi (boşluklar kırpılır).
bool isValidEmail(String? value) =>
    value != null && _emailPattern.hasMatch(value.trim());

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _emailOpen = false;
  bool _signUp = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(signInControllerProvider).isBusy ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final controller = ref.read(signInControllerProvider.notifier);
    final email = _email.text.trim();
    final ok = _signUp
        ? await controller.signUpWithPassword(
            email: email, password: _password.text)
        : await controller.signInWithPassword(
            email: email, password: _password.text);
    // iOS'un şifreyi anahtar zincirine kaydetmeyi önermesi için.
    if (ok) TextInput.finishAutofillContext();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(signInControllerProvider);
    final googleAvailable = ref.watch(googleLoginAvailableProvider);
    final busy = state.isBusy;
    final showForm = !googleAvailable || _emailOpen;
    final submitLabel = state.busy == SignInMethod.password
        ? (_signUp ? 'Hesap oluşturuluyor…' : 'Giriş yapılıyor…')
        : (_signUp ? 'Hesap oluştur' : 'Giriş yap');

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ViceHero(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Ritim',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Devam etmek için giriş yap.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (googleAvailable) ...[
                    FilledButton.icon(
                      key: const Key('sign-in-google'),
                      onPressed: busy
                          ? null
                          : () => ref
                              .read(signInControllerProvider.notifier)
                              .signInWithGoogle(),
                      icon: const Icon(Icons.g_mobiledata_outlined, size: 28),
                      label: Text(
                        state.busy == SignInMethod.google
                            ? 'Google ile giriş yapılıyor…'
                            : 'Google ile devam et',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (!_emailOpen)
                      OutlinedButton(
                        key: const Key('sign-in-email-toggle'),
                        onPressed: busy
                            ? null
                            : () => setState(() => _emailOpen = true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(color: AppColors.border),
                        ),
                        child: const Text('E-posta ile giriş'),
                      ),
                  ],
                  if (showForm) ...[
                    if (googleAvailable) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'veya e-posta ile',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _email,
                              enabled: !busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              decoration:
                                  const InputDecoration(hintText: 'E-posta'),
                              validator: (value) => isValidEmail(value)
                                  ? null
                                  : 'Geçerli bir e-posta gir.',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _password,
                              enabled: !busy,
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: [
                                _signUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                hintText: 'Şifre',
                                suffixIcon: IconButton(
                                  key: const Key('sign-in-toggle-password'),
                                  tooltip: _showPassword
                                      ? 'Şifreyi gizle'
                                      : 'Şifreyi göster',
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Şifreni gir.';
                                }
                                if (_signUp && value.length < minPasswordLength) {
                                  return 'Şifre en az $minPasswordLength '
                                      'karakter olmalı.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      state.error!,
                      key: const Key('sign-in-error'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.danger),
                    ),
                  ],
                  if (state.info != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      state.info!,
                      key: const Key('sign-in-info'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                  if (showForm) ...[
                    const SizedBox(height: AppSpacing.lg),
                    googleAvailable
                        ? OutlinedButton(
                            key: const Key('sign-in-submit'),
                            onPressed: busy ? null : _submit,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(color: AppColors.border),
                            ),
                            child: Text(submitLabel),
                          )
                        : FilledButton(
                            key: const Key('sign-in-submit'),
                            onPressed: busy ? null : _submit,
                            child: Text(submitLabel),
                          ),
                  ],
                  if (showForm) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      key: const Key('sign-in-mode-toggle'),
                      onPressed: busy
                          ? null
                          : () => setState(() => _signUp = !_signUp),
                      child: Text(
                        _signUp
                            ? 'Hesabın var mı? Giriş yap'
                            : 'Hesabın yok mu? Kayıt ol',
                      ),
                    ),
                    if (!_signUp)
                      TextButton(
                        key: const Key('sign-in-forgot'),
                        onPressed: busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PasswordResetScreen(
                                      initialEmail: _email.text.trim(),
                                    ),
                                  ),
                                ),
                        child: const Text('Şifremi unuttum'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Giriş başlığı: gece moru hale içinde simge renklerinde topaç ve gün
/// batımı şeridi (Vice City esintisi; zemin pastel kalır).
class _ViceHero extends StatelessWidget {
  const _ViceHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('sign-in-vice-hero'),
      children: [
        SizedBox.square(
          dimension: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.nightPurple.withValues(alpha: 0.35),
                  AppColors.sunsetEnd.withValues(alpha: 0.10),
                  AppColors.background.withValues(alpha: 0),
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
            child: const Center(
              child: RitimTop(mode: RitimTopMode.idle, size: 72),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const SunsetStripe(),
      ],
    );
  }
}
