import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/user_settings.dart';
import 'delete_account_screen.dart';
import 'settings_providers.dart';
import 'settings_widgets.dart';

/// Hesap › Profil ve hedefler: profil alanları ve günlük hedefler tek sütunda.
/// Sayfa kendi Kaydet düğmesiyle yalnızca kendi alanlarını yazar.
class ProfileGoalsPage extends StatelessWidget {
  const ProfileGoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Profil ve hedefler',
      builder: (settings) => _ProfileGoalsForm(settings: settings),
    );
  }
}

class _ProfileGoalsForm extends ConsumerStatefulWidget {
  const _ProfileGoalsForm({required this.settings});

  final UserSettings settings;

  @override
  ConsumerState<_ProfileGoalsForm> createState() => _ProfileGoalsFormState();
}

class _ProfileGoalsFormState extends ConsumerState<_ProfileGoalsForm> {
  final _formKey = GlobalKey<FormState>();

  final _displayName = TextEditingController();
  final _height = TextEditingController();
  final _birthYear = TextEditingController();
  final _workDescription = TextEditingController();
  final _startWeight = TextEditingController();
  final _targetWeight = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _steps = TextEditingController();
  final _sleep = TextEditingController();

  late final List<TextEditingController> _fields = [
    _displayName,
    _height,
    _birthYear,
    _workDescription,
    _startWeight,
    _targetWeight,
    _calories,
    _protein,
    _carbs,
    _fat,
    _steps,
    _sleep,
  ];

  late UserSettings _saved;
  late List<String> _savedTexts;

  /// 'female' | 'male' | 'unspecified' | null (cevaplanmadı).
  String? _sex;

  /// Hareket düzeyi; `null` = cevaplanmadı.
  ActivityLevel? _activity;
  bool _saving = false;

  static const List<(String, String)> _sexOptions = [
    ('female', 'Kadın'),
    ('male', 'Erkek'),
    ('unspecified', 'Belirtmek istemiyorum'),
  ];

  @override
  void initState() {
    super.initState();
    _load(widget.settings);
    for (final c in _fields) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void didUpdateWidget(covariant _ProfileGoalsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Dışarıdan gelen yeni değer, kullanıcının yarım düzenlemesini ezmez.
    if (!identical(oldWidget.settings, widget.settings) && !_dirty) {
      _load(widget.settings);
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  void _load(UserSettings s) {
    _saved = s;
    _displayName.text = s.displayName ?? '';
    _height.text = s.heightCm?.toString() ?? '';
    _birthYear.text = s.birthYear?.toString() ?? '';
    _workDescription.text = s.workDescription ?? '';
    _startWeight.text = _formatWeight(s.startWeightKg);
    _targetWeight.text = _formatWeight(s.targetWeightKg);
    _calories.text = '${s.dailyCalories}';
    _protein.text = '${s.dailyProteinG}';
    _carbs.text = '${s.dailyCarbsG}';
    _fat.text = '${s.dailyFatG}';
    _steps.text = '${s.dailySteps}';
    _sleep.text = '${s.sleepMinutes}';
    _sex = s.sex;
    _activity = s.activityLevel;
    _savedTexts = [for (final c in _fields) c.text];
  }

  bool get _dirty {
    for (final (i, c) in _fields.indexed) {
      if (c.text.trim() != _savedTexts[i]) return true;
    }
    return _sex != _saved.sex || _activity != _saved.activityLevel;
  }

  static String _formatWeight(double kg) {
    final fixed = kg.toStringAsFixed(2);
    return fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
  }

  static double? _parseDecimal(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  static String? _blankToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int get _birthYearMax => DateTime.now().year - SettingsLimits.birthYearMinAge;

  /// Boy ya da doğum yılı geçersizse kullanıcıya gösterilecek cümle.
  String? _profileProblem() {
    final height = validateSettingsNumber(
      _height.text,
      min: SettingsLimits.heightMin,
      max: SettingsLimits.heightMax,
      optional: true,
    );
    if (height != null) return 'Boy $height.';
    final year = validateSettingsNumber(
      _birthYear.text,
      min: SettingsLimits.birthYearMin,
      max: _birthYearMax,
      optional: true,
    );
    if (year != null) return 'Doğum yılı $year.';
    return null;
  }

  /// En güncel ayarların üstüne yalnızca bu sayfanın alanları yazılır;
  /// böylece diğer alt sayfalarda kaydedilenler ezilmez.
  UserSettings _draft() {
    final base = ref.read(userSettingsProvider).valueOrNull ?? _saved;
    final height = int.tryParse(_height.text.trim());
    final birthYear = int.tryParse(_birthYear.text.trim());
    final displayName = _blankToNull(_displayName.text);
    final work = _blankToNull(_workDescription.text);
    return base.copyWith(
      // numeric(5,2): iki ondalığa yuvarlanır.
      startWeightKg:
          (_parseDecimal(_startWeight.text)! * 100).roundToDouble() / 100,
      targetWeightKg:
          (_parseDecimal(_targetWeight.text)! * 100).roundToDouble() / 100,
      dailyCalories: int.parse(_calories.text.trim()),
      dailyProteinG: int.parse(_protein.text.trim()),
      dailyCarbsG: int.parse(_carbs.text.trim()),
      dailyFatG: int.parse(_fat.text.trim()),
      dailySteps: int.parse(_steps.text.trim()),
      sleepMinutes: int.parse(_sleep.text.trim()),
      // Boş alan null yazılır; böylece kullanıcı profilini temizleyebilir.
      heightCm: height,
      clearHeightCm: height == null,
      birthYear: birthYear,
      clearBirthYear: birthYear == null,
      sex: _sex,
      clearSex: _sex == null,
      activityLevel: _activity,
      displayName: displayName,
      clearDisplayName: displayName == null,
      workDescription: work,
      clearWorkDescription: work == null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showSettingsSnack(messenger, 'Kırmızı işaretli alanları düzelt.');
      return;
    }
    // Tembel liste ekran dışındaki alanı bellekten atar ve Form onu
    // doğrulayamaz; profil alanları bu yüzden ayrıca denetlenir.
    final profileError = _profileProblem();
    if (profileError != null) {
      showSettingsSnack(messenger, 'Profil kaydedilemedi. $profileError');
      return;
    }

    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(userSettingsProvider.notifier).save(_draft());
      ref.invalidate(notificationSyncProvider);
      if (mounted) setState(() => _load(saved));
      showSettingsSnack(messenger, 'Ayarlar kaydedildi.');
    } catch (_) {
      showSettingsSnack(
        messenger,
        'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    if (await confirmDiscardChanges(context) && mounted) navigator.pop();
  }

  String? _sleepHelper() {
    final minutes = int.tryParse(_sleep.text.trim());
    if (minutes == null || minutes <= 0) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: settingsListPadding,
                children: [
                  _goalsCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _profileCard(),
                  const SizedBox(height: AppSpacing.section),
                  // BEGIN faz5_account
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      key: const Key('settings-delete-account'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const DeleteAccountScreen(),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text('Hesabımı sil'),
                    ),
                  ),
                  // END faz5_account
                ],
              ),
            ),
            SettingsSaveBar(
              enabled: dirty,
              saving: _saving,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard() {
    final theme = Theme.of(context);
    final incomplete = _height.text.trim().isEmpty ||
        _birthYear.text.trim().isEmpty ||
        _sex == null;
    return SettingsSection(
      icon: Icons.badge_rounded,
      title: 'Profil',
      color: AppColors.fitness,
      children: [
        TextFormField(
          key: const Key('settings-display-name'),
          controller: _displayName,
          maxLength: UserSettings.displayNameMax,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Görünen ad',
            helperText: 'Arkadaşların seni bu adla görür.',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        SettingsFieldRow(
          left: SettingsNumberField(
            fieldKey: const Key('settings-height'),
            controller: _height,
            label: 'Boy (cm)',
            min: SettingsLimits.heightMin,
            max: SettingsLimits.heightMax,
            optional: true,
          ),
          right: SettingsNumberField(
            fieldKey: const Key('settings-birth-year'),
            controller: _birthYear,
            label: 'Doğum yılı',
            min: SettingsLimits.birthYearMin,
            max: _birthYearMax,
            optional: true,
          ),
        ),
        Text(
          'Cinsiyet',
          style:
              theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final (value, label) in _sexOptions)
              ChoiceChip(
                key: Key('settings-sex-$value'),
                label: Text(label),
                showCheckmark: false,
                selected: _sex == value,
                // Seçili çipe yeniden dokunmak seçimi kaldırır (alan boş kalır).
                onSelected: (on) => setState(() => _sex = on ? value : null),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SettingsHint(
          incomplete
              ? 'Enerji dengesi için boy, doğum yılı ve cinsiyet gerekli.'
              : 'Yalnızca enerji dengesi tahmininde kullanılır.',
        ),
        const SizedBox(height: 12),
        Text(
          'Hareket düzeyi',
          style:
              theme.textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final level in ActivityLevel.values)
              ChoiceChip(
                key: Key('settings-activity-${level.name}'),
                label: Text(level.label),
                showCheckmark: false,
                selected: _activity == level,
                onSelected: (_) => setState(() => _activity = level),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('settings-work-description'),
          controller: _workDescription,
          maxLength: UserSettings.workDescriptionMax,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Ne iş yapıyorsun? (isteğe bağlı)',
            helperText: 'Yapay zekâ seni anlasın diye; yalnızca AI komutuna '
                'girer, kimseyle paylaşılmaz.',
            helperMaxLines: 3,
            counterText: '',
          ),
        ),
      ],
    );
  }

  Widget _goalField(Widget field) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: field,
      );

  Widget _goalsCard() {
    return SettingsSection(
      icon: Icons.flag_rounded,
      title: 'Hedefler',
      color: AppColors.accent,
      children: [
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-start-weight'),
            controller: _startWeight,
            label: 'Başlangıç kilosu (kg)',
            decimal: true,
            min: SettingsLimits.weightMin,
            max: SettingsLimits.weightMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-target-weight'),
            controller: _targetWeight,
            label: 'Hedef kilo (kg)',
            decimal: true,
            min: SettingsLimits.weightMin,
            max: SettingsLimits.weightMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-calories'),
            controller: _calories,
            label: 'Kalori (kcal)',
            min: SettingsLimits.caloriesMin,
            max: SettingsLimits.caloriesMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-protein'),
            controller: _protein,
            label: 'Protein (g)',
            min: SettingsLimits.proteinMin,
            max: SettingsLimits.proteinMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-carbs'),
            controller: _carbs,
            label: 'Karbonhidrat (g)',
            min: SettingsLimits.carbsMin,
            max: SettingsLimits.carbsMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-fat'),
            controller: _fat,
            label: 'Yağ (g)',
            min: SettingsLimits.fatMin,
            max: SettingsLimits.fatMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-steps'),
            controller: _steps,
            label: 'Adım',
            min: SettingsLimits.stepsMin,
            max: SettingsLimits.stepsMax,
          ),
        ),
        _goalField(
          SettingsNumberField(
            fieldKey: const Key('settings-sleep'),
            controller: _sleep,
            label: 'Uyku (dk)',
            min: SettingsLimits.sleepMin,
            max: SettingsLimits.sleepMax,
            helper: _sleepHelper(),
          ),
        ),
      ],
    );
  }
}
