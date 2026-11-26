import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../data/weekly_checkin_repository.dart';

/// Bir haftanın check-in'i (yoksa `null`). Anahtar haftanın pazartesisidir.
final weeklyCheckinProvider =
    FutureProvider.autoDispose.family<WeeklyCheckin?, DateTime>(
  (ref, weekStart) =>
      ref.watch(weeklyCheckinRepositoryProvider).fetch(weekStart),
);

/// Pazar akşamı / Pazartesi: "Hafta nasıldı?" (1–5 + kısa not). Diğer
/// günlerde hiçbir şey çizmez.
class WeeklyCheckinCard extends ConsumerWidget {
  const WeeklyCheckinCard({super.key, this.bottomSpacing = 16});

  /// Kart görünürse altına bırakılan boşluk.
  final double bottomSpacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = checkinWeekFor(DateTime.now());
    if (week == null) return const SizedBox.shrink();
    final existing = ref.watch(weeklyCheckinProvider(week));
    final content = existing.when(
      skipLoadingOnRefresh: true,
      loading: () => null,
      error: (_, __) => null,
      data: (checkin) => _CheckinBody(week: week, saved: checkin),
    );
    if (content == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: BentoCard(child: content),
    );
  }
}

class _CheckinBody extends ConsumerStatefulWidget {
  const _CheckinBody({required this.week, required this.saved});

  final DateTime week;
  final WeeklyCheckin? saved;

  @override
  ConsumerState<_CheckinBody> createState() => _CheckinBodyState();
}

class _CheckinBodyState extends ConsumerState<_CheckinBody> {
  late final TextEditingController _note =
      TextEditingController(text: widget.saved?.note ?? '');
  late int? _mood = widget.saved?.mood;
  late bool _editing = widget.saved == null;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final mood = _mood;
    if (mood == null || !isValidCheckinMood(mood)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(weeklyCheckinRepositoryProvider).save(
            WeeklyCheckin(
              weekStart: widget.week,
              mood: mood,
              note: _note.text,
            ),
          );
      unawaited(HapticFeedback.selectionClick());
      ref.invalidate(weeklyCheckinProvider(widget.week));
      if (mounted) setState(() => _editing = false);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Check-in kaydedilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = widget.saved;

    if (!_editing && saved != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(
            icon: Icons.emoji_emotions_outlined,
            label: 'Haftalık check-in',
            color: AppColors.accent,
            trailing: 'kaydedildi',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${saved.mood}/5 · '
                  '${weeklyCheckinMoodLabels[saved.mood - 1]}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _editing = true),
                child: const Text('Düzenle'),
              ),
            ],
          ),
          if (saved.note != null)
            Text(
              saved.note!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoLabel(
          icon: Icons.emoji_emotions_outlined,
          label: 'Hafta nasıldı?',
          color: AppColors.accent,
          trailing: 'haftalık check-in',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var m = 1; m <= 5; m++) ...[
              Expanded(
                child: Tooltip(
                  message: weeklyCheckinMoodLabels[m - 1],
                  child: ChoiceChip(
                    label: SizedBox(
                      width: double.infinity,
                      child: Text('$m', textAlign: TextAlign.center),
                    ),
                    selected: _mood == m,
                    selectedColor: AppColors.accent,
                    labelStyle: TextStyle(
                      color: _mood == m
                          ? AppColors.onAccent
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected:
                        _saving ? null : (_) => setState(() => _mood = m),
                  ),
                ),
              ),
              if (m < 5) const SizedBox(width: 6),
            ],
          ],
        ),
        if (_mood != null) ...[
          const SizedBox(height: 4),
          Text(
            weeklyCheckinMoodLabels[_mood! - 1],
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          enabled: !_saving,
          maxLength: weeklyCheckinNoteMax,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Kısa not (isteğe bağlı)',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _mood == null || _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
        ),
      ],
    );
  }
}
