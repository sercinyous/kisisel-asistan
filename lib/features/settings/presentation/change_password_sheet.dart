import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/sign_in_backend.dart';
import '../../auth/domain/sign_in_messages.dart';

/// Hesap > Şifreyi değiştir: e-posta hesabında açık oturumla yeni şifre.
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        builder: (_) => const ChangePasswordSheet(),
      );

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(signInBackendProvider).setNewPassword(_password.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = signInErrorMessage(e) ?? connectionFailedMessage;
        });
      }
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Şifren güncellendi.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Şifreyi değiştir', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('change-password-field'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Yeni şifre'),
              validator: (v) => (v ?? '').length >= minPasswordLength
                  ? null
                  : 'Şifre en az $minPasswordLength karakter olmalı.',
              onFieldSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('change-password-save'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Kaydediliyor…' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
