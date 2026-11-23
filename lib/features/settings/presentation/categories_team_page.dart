import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'settings_providers.dart';
import 'settings_widgets.dart';
import 'task_categories_settings.dart';

/// Hesap › Kategoriler ve ekip. Her değişiklik anında kaydedilir.
class CategoriesTeamPage extends StatelessWidget {
  const CategoriesTeamPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Kategoriler ve ekip')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: settingsListPadding,
        children: const [
          TaskCategoriesCard(),
          SizedBox(height: AppSpacing.grid),
          TeamCard(),
        ],
      ),
    );
  }
}

/// Görevlerde seçilen ekip üyeleri; ekleme ve silme hemen yazılır.
class TeamCard extends ConsumerStatefulWidget {
  const TeamCard({super.key});

  @override
  ConsumerState<TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<TeamCard> {
  final _input = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  static String _fold(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  Future<bool> _write(List<String> team) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = ref.read(userSettingsProvider).valueOrNull;
    if (current == null) return false;
    setState(() => _saving = true);
    try {
      await ref
          .read(userSettingsProvider.notifier)
          .save(current.copyWith(teamMembers: List.unmodifiable(team)));
      return true;
    } catch (_) {
      showSettingsSnack(
        messenger,
        'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add(List<String> team) async {
    final name = _input.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    String? error;
    if (name.isEmpty) {
      error = 'Bir isim yaz.';
    } else if (name.length > SettingsLimits.teamNameMaxLength) {
      error = 'En fazla ${SettingsLimits.teamNameMaxLength} karakter.';
    } else if (team.length >= SettingsLimits.teamMax) {
      error = 'En fazla ${SettingsLimits.teamMax} kişi eklenebilir.';
    } else if (team.any((m) => _fold(m) == _fold(name))) {
      error = 'Bu isim zaten listede.';
    }
    setState(() => _error = error);
    if (error != null) return;
    if (await _write([...team, name]) && mounted) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(
      userSettingsProvider.select(
        (s) => s.valueOrNull?.teamMembers ?? const <String>[],
      ),
    );
    final full = team.length >= SettingsLimits.teamMax;
    return SettingsSection(
      icon: Icons.groups_outlined,
      title: 'Ekip',
      color: AppColors.fitness,
      trailing: '${team.length}/${SettingsLimits.teamMax}',
      children: [
        if (team.isEmpty)
          const SettingsHint(
              'Henüz kimse yok. Görevlerde seçmek için isim ekle.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final name in team)
                InputChip(
                  label: Text(name),
                  backgroundColor: AppColors.surfaceHigh,
                  side: BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  deleteButtonTooltipMessage: '$name adını sil',
                  onDeleted: _saving
                      ? null
                      : () {
                          setState(() => _error = null);
                          _write(team.where((m) => m != name).toList());
                        },
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('settings-team-input'),
                controller: _input,
                enabled: !full,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: SettingsLimits.teamNameMaxLength,
                onSubmitted: (_) => _add(team),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: full ? 'Liste dolu' : 'İsim ekle',
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton.filledTonal(
                key: const Key('settings-team-add'),
                tooltip: 'Ekle',
                onPressed: full || _saving ? null : () => _add(team),
                icon: const Icon(Icons.add_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
