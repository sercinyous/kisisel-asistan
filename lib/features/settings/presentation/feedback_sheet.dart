import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

/// Ayarlar > Sorun bildir: kısa metin uygulama sahibine (public.feedback) gider.
class FeedbackSheet extends ConsumerStatefulWidget {
  const FeedbackSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        builder: (_) => const FeedbackSheet(),
      );

  @override
  ConsumerState<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<FeedbackSheet> {
  final _text = TextEditingController();
  FeedbackCategory _category = FeedbackCategory.bug;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(accountRepositoryProvider)
          .sendFeedback(message: _text.text, category: _category);
    } on AccountActionException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
      return;
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Teşekkürler, iletildi.')),
      );
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sorun bildir', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Mesajın uygulama sahibine iletilir; uygulama sürümü de eklenir.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<FeedbackCategory>(
            segments: [
              for (final c in FeedbackCategory.values)
                ButtonSegment(value: c, label: Text(c.label)),
            ],
            selected: {_category},
            onSelectionChanged:
                _sending ? null : (s) => setState(() => _category = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('feedback-message'),
            controller: _text,
            enabled: !_sending,
            minLines: 4,
            maxLines: 8,
            maxLength: AccountRepository.maxFeedback,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ne oldu? Ne bekliyordun?',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
          FilledButton(
            key: const Key('feedback-send'),
            onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
            child: Text(_sending ? 'Gönderiliyor…' : 'Gönder'),
          ),
        ],
      ),
    );
  }
}
