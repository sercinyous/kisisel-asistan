import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_sync.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/bento.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../health/presentation/health_providers.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../domain/user_settings.dart';
import 'health_source_settings.dart';
import 'settings_providers.dart';

/// Ayarlar: görünüm, hedefler, bildirimler, ekip, bağlantılar ve hesap.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: SafeArea(
        child: settings.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _LoadError(
            onRetry: () => ref.invalidate(userSettingsProvider),
          ),
          data: (value) => _SettingsForm(settings: value),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Ayarlar yüklenemedi.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

/// Sayı alanı sınırları; supabase/schema.sql (user_settings) check'leriyle aynı.
abstract final class SettingsLimits {
  static const double weightMin = 30, weightMax = 250;
  static const int caloriesMin = 800, caloriesMax = 6000;
  static const int proteinMin = 0, proteinMax = 500;
  static const int carbsMin = 0, carbsMax = 800;
  static const int fatMin = 0, fatMax = 400;
  static const int stepsMin = 1000, stepsMax = 60000;
  static const int sleepMin = 180, sleepMax = 900;
  static const int heightMin = UserSettings.heightCmMin;
  static const int heightMax = UserSettings.heightCmMax;
  static const int birthYearMin = UserSettings.birthYearMin;

  /// Doğum yılı üst sınırı: bu yıl − 10 (en küçük kabul edilen yaş).
  static const int birthYearMinAge = 10;
  static const int leadDaysMin = 0, leadDaysMax = 14;
  static const int eventMinutesMin = 0, eventMinutesMax = 1440;
  static const int teamMax = 12;
  static const int teamNameMaxLength = 24;
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final UserSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();

  final _startWeight = TextEditingController();
  final _targetWeight = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _steps = TextEditingController();
  final _sleep = TextEditingController();
  final _height = TextEditingController();
  final _birthYear = TextEditingController();
  final _leadDays = TextEditingController();
  final _eventMinutes = TextEditingController();
  final _displayName = TextEditingController();
  final _workDescription = TextEditingController();
  final _teamInput = TextEditingController();

  late List<TextEditingController> _numberFields;

  /// Son kaydedilen (ya da yüklenen) değerler; "değişti mi" buna göre ölçülür.
  late UserSettings _saved;
  late List<String> _savedTexts;

  /// 'female' | 'male' | 'unspecified' | null (cevaplanmadı).
  String? _sex;
  late bool _notificationsEnabled;
  late bool _routineNotifications;
  late bool _quietHoursEnabled;
  late TimeOfDayValue _monthlyRemindTime;
  late TimeOfDayValue _quietStart;
  late TimeOfDayValue _quietEnd;
  late List<String> _team;

  String? _teamError;
  bool _saving = false;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _numberFields = [
      _startWeight,
      _targetWeight,
      _calories,
      _protein,
      _carbs,
      _fat,
      _steps,
      _sleep,
      _height,
      _birthYear,
      _leadDays,
      _eventMinutes,
      // Metin alanları da aynı "değişti mi" izlemesinden geçer.
      _displayName,
      _workDescription,
    ];
    _load(widget.settings);
    for (final c in _numberFields) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void didUpdateWidget(covariant _SettingsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Dışarıdan gelen yeni değer, kullanıcının yarım düzenlemesini ezmez.
    if (!identical(oldWidget.settings, widget.settings) && !_dirty) {
      _load(widget.settings);
    }
  }

  @override
  void dispose() {
    for (final c in _numberFields) {
      c.dispose();
    }
    _teamInput.dispose();
    super.dispose();
  }

  void _onFieldChanged() => setState(() {});

  void _load(UserSettings s) {
    _saved = s;
    _startWeight.text = _formatWeight(s.startWeightKg);
    _targetWeight.text = _formatWeight(s.targetWeightKg);
    _calories.text = '${s.dailyCalories}';
    _protein.text = '${s.dailyProteinG}';
    _carbs.text = '${s.dailyCarbsG}';
    _fat.text = '${s.dailyFatG}';
    _steps.text = '${s.dailySteps}';
    _sleep.text = '${s.sleepMinutes}';
    _height.text = s.heightCm?.toString() ?? '';
    _birthYear.text = s.birthYear?.toString() ?? '';
    _sex = s.sex;
    _leadDays.text = '${s.monthlyLeadDays}';
    _eventMinutes.text = '${s.eventRemindMinutes}';
    _displayName.text = s.displayName ?? '';
    _workDescription.text = s.workDescription ?? '';
    _savedTexts = [for (final c in _numberFields) c.text];
    _notificationsEnabled = s.notificationsEnabled;
    _routineNotifications = s.routineNotifications;
    _quietHoursEnabled = s.quietHoursEnabled;
    _monthlyRemindTime = s.monthlyRemindTime;
    _quietStart = s.quietStart;
    _quietEnd = s.quietEnd;
    _team = List.of(s.teamMembers);
  }

  bool get _dirty {
    for (final (i, c) in _numberFields.indexed) {
      if (c.text.trim() != _savedTexts[i]) return true;
    }
    return _sex != _saved.sex ||
        _notificationsEnabled != _saved.notificationsEnabled ||
        _routineNotifications != _saved.routineNotifications ||
        _quietHoursEnabled != _saved.quietHoursEnabled ||
        _monthlyRemindTime != _saved.monthlyRemindTime ||
        _quietStart != _saved.quietStart ||
        _quietEnd != _saved.quietEnd ||
        !_sameList(_team, _saved.teamMembers);
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  Future<void> _openFriends() => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const FriendsScreen()),
      );

  /// Yalnızca 5 tanıtım kartı; hiçbir şey yazılmaz.
  Future<void> _replayGuide() => Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const OnboardingScreen(replay: true),
        ),
      );

  UserSettings _draft() => UserSettings(
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
        heightCm: int.tryParse(_height.text.trim()),
        birthYear: int.tryParse(_birthYear.text.trim()),
        sex: _sex,
        // Boş metin null yazılır; ilk kurulum anı korunur (geri alınmaz).
        displayName: _blankToNull(_displayName.text),
        workDescription: _blankToNull(_workDescription.text),
        onboardedAt: _saved.onboardedAt,
        notificationsEnabled: _notificationsEnabled,
        routineNotifications: _routineNotifications,
        monthlyLeadDays: int.parse(_leadDays.text.trim()),
        monthlyRemindTime: _monthlyRemindTime,
        eventRemindMinutes: int.parse(_eventMinutes.text.trim()),
        quietHoursEnabled: _quietHoursEnabled,
        quietStart: _quietStart,
        quietEnd: _quietEnd,
        teamMembers: List.unmodifiable(_team),
      );

  int get _birthYearMax => DateTime.now().year - SettingsLimits.birthYearMinAge;

  String? _validateHeight(String? text) => _validateNumber(
        text,
        min: SettingsLimits.heightMin,
        max: SettingsLimits.heightMax,
        optional: true,
      );

  String? _validateBirthYear(String? text) => _validateNumber(
        text,
        min: SettingsLimits.birthYearMin,
        max: _birthYearMax,
        optional: true,
      );

  /// Boy ya da doğum yılı geçersizse kullanıcıya gösterilecek cümle.
  String? _profileProblem() {
    final height = _validateHeight(_height.text);
    if (height != null) return 'Boy $height.';
    final year = _validateBirthYear(_birthYear.text);
    if (year != null) return 'Doğum yılı $year.';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Kırmızı işaretli alanları düzelt.')),
        );
      return;
    }
    // Tembel liste ekran dışındaki alanı bellekten atar ve Form onu
    // doğrulayamaz; profil alanları bu yüzden ayrıca denetlenir.
    final profileError = _profileProblem();
    if (profileError != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Profil kaydedilemedi. $profileError')),
        );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(userSettingsProvider.notifier).save(_draft());
      // Yeni tercihlerle bekleyen bildirimler baştan planlanır.
      ref.invalidate(notificationSyncProvider);
      if (mounted) setState(() => _load(saved));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Ayarlar kaydedildi.')));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Kaydedilemedi. Bağlantını kontrol edip tekrar dene.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: const Text('Çıkarsan yaptığın değişiklikler kaybolacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Düzenlemeye dön'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Vazgeç ve çık'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) navigator.pop();
  }

  Future<void> _pickTime(
    TimeOfDayValue current,
    String helpText,
    ValueChanged<TimeOfDayValue> onPicked,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: helpText,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(TimeOfDayValue(picked.hour, picked.minute)));
  }

  static String _fold(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase();

  void _addMember() {
    final name = _teamInput.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    String? error;
    if (name.isEmpty) {
      error = 'Bir isim yaz.';
    } else if (name.length > SettingsLimits.teamNameMaxLength) {
      error = 'En fazla ${SettingsLimits.teamNameMaxLength} karakter.';
    } else if (_team.length >= SettingsLimits.teamMax) {
      error = 'En fazla ${SettingsLimits.teamMax} kişi eklenebilir.';
    } else if (_team.any((m) => _fold(m) == _fold(name))) {
      error = 'Bu isim zaten listede.';
    }
    setState(() {
      _teamError = error;
      if (error == null) {
        _team = [..._team, name];
        _teamInput.clear();
      }
    });
  }

  Future<void> _reconnectHealth() async {
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    var granted = false;
    try {
      granted = await ref.read(healthServiceProvider).requestAccess();
    } catch (_) {
      granted = false;
    }
    // İlk izinle birlikte son günler de okunur ve yedeklenir.
    unawaited(resyncHealthKit(container));
    if (granted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'İzin verilmedi. iPhone Ayarlar > Sağlık > Veri Erişimi '
            'bölümünden açabilirsin.',
          ),
        ),
      );
  }

  /// İzin yalnızca kullanıcı butona basınca istenir; ekranı açmak sormaz.
  Future<void> _requestNotifications() async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(notificationServiceProvider).requestPermission();
    container
      ..invalidate(notificationPermissionProvider)
      ..invalidate(notificationSyncProvider);
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: Text(
          _dirty
              ? 'Kaydedilmemiş değişikliklerin kaybolacak. '
                  'Tekrar giriş yapana kadar verilerin görünmez.'
              : 'Tekrar giriş yapana kadar verilerin görünmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Çıkış yap',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
      // Oturum kapanınca kök ekran giriş sayfasına döner; ayarlar üstte kalmasın.
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Çıkış yapılamadı. Tekrar dene.')),
        );
    }
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.grid,
                  AppSpacing.page,
                  AppSpacing.page,
                ),
                children: [
                  const _AppearanceCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _goalsCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _profileCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _notificationsCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _teamCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _shortcutsCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _connectionsCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _accountCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.grid,
                AppSpacing.page,
                AppSpacing.grid,
              ),
              child: FilledButton(
                onPressed: dirty && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalsCard() {
    return _Section(
      icon: Icons.flag_rounded,
      title: 'Hedefler',
      color: AppColors.accent,
      children: [
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-start-weight'),
            controller: _startWeight,
            label: 'Başlangıç (kg)',
            decimal: true,
            min: SettingsLimits.weightMin,
            max: SettingsLimits.weightMax,
          ),
          right: _NumberField(
            fieldKey: const Key('settings-target-weight'),
            controller: _targetWeight,
            label: 'Hedef (kg)',
            decimal: true,
            min: SettingsLimits.weightMin,
            max: SettingsLimits.weightMax,
          ),
        ),
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-calories'),
            controller: _calories,
            label: 'Kalori (kcal)',
            min: SettingsLimits.caloriesMin,
            max: SettingsLimits.caloriesMax,
          ),
          right: _NumberField(
            fieldKey: const Key('settings-protein'),
            controller: _protein,
            label: 'Protein (g)',
            min: SettingsLimits.proteinMin,
            max: SettingsLimits.proteinMax,
          ),
        ),
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-carbs'),
            controller: _carbs,
            label: 'Karbonhidrat (g)',
            min: SettingsLimits.carbsMin,
            max: SettingsLimits.carbsMax,
          ),
          right: _NumberField(
            fieldKey: const Key('settings-fat'),
            controller: _fat,
            label: 'Yağ (g)',
            min: SettingsLimits.fatMin,
            max: SettingsLimits.fatMax,
          ),
        ),
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-steps'),
            controller: _steps,
            label: 'Adım',
            min: SettingsLimits.stepsMin,
            max: SettingsLimits.stepsMax,
          ),
          right: _NumberField(
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

  static const List<(String, String)> _sexOptions = [
    ('female', 'Kadın'),
    ('male', 'Erkek'),
    ('unspecified', 'Belirtmek istemiyorum'),
  ];

  Widget _profileCard() {
    final theme = Theme.of(context);
    final incomplete = _height.text.trim().isEmpty ||
        _birthYear.text.trim().isEmpty ||
        _sex == null;
    return _Section(
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
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-height'),
            controller: _height,
            label: 'Boy (cm)',
            min: SettingsLimits.heightMin,
            max: SettingsLimits.heightMax,
            optional: true,
          ),
          right: _NumberField(
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
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.textMuted),
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
        _Hint(
          incomplete
              ? 'Enerji dengesi için boy, doğum yılı ve cinsiyet gerekli.'
              : 'Yalnızca enerji dengesi tahmininde kullanılır.',
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

  Widget _shortcutsCard() {
    return _Section(
      icon: Icons.explore_rounded,
      title: 'Arkadaşlar ve kılavuz',
      color: AppColors.accent,
      children: [
        ListTile(
          key: const Key('settings-friends'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.people_rounded, color: AppColors.textSecondary),
          title: const Text('Arkadaşlar'),
          subtitle: const Text('Davetler, arkadaş ekle, paylaşım anahtarları'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _openFriends,
        ),
        ListTile(
          key: const Key('settings-replay-guide'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.menu_book_rounded, color: AppColors.textSecondary),
          title: const Text('Kılavuzu yeniden göster'),
          subtitle: const Text('Uygulamanın kısa tanıtımı'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _replayGuide,
        ),
      ],
    );
  }

  String? _sleepHelper() {
    final minutes = int.tryParse(_sleep.text.trim());
    if (minutes == null || minutes <= 0) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  Widget _notificationsCard() {
    final on = _notificationsEnabled;
    return _Section(
      icon: Icons.notifications_rounded,
      title: 'Bildirimler',
      color: AppColors.ops,
      children: [
        _SwitchRow(
          key: const Key('settings-notifications'),
          title: 'Tüm bildirimler',
          subtitle: 'Kapalıyken hiçbir hatırlatma gelmez.',
          value: on,
          onChanged: (v) => setState(() => _notificationsEnabled = v),
        ),
        _SwitchRow(
          key: const Key('settings-routine-notifications'),
          title: 'Rutin bildirimleri',
          subtitle: 'Günlük ve haftalık sabitler saatinde hatırlatılır.',
          value: _routineNotifications,
          onChanged: on
              ? (v) => setState(() => _routineNotifications = v)
              : null,
        ),
        const SizedBox(height: 8),
        _FieldRow(
          left: _NumberField(
            fieldKey: const Key('settings-lead-days'),
            controller: _leadDays,
            label: 'Aylık iş (gün önce)',
            min: SettingsLimits.leadDaysMin,
            max: SettingsLimits.leadDaysMax,
          ),
          right: _NumberField(
            fieldKey: const Key('settings-event-minutes'),
            controller: _eventMinutes,
            label: 'Randevu (dk önce)',
            min: SettingsLimits.eventMinutesMin,
            max: SettingsLimits.eventMinutesMax,
          ),
        ),
        _TimeRow(
          key: const Key('settings-monthly-time'),
          title: 'Aylık iş hatırlatma saati',
          value: _monthlyRemindTime,
          onTap: () => _pickTime(
            _monthlyRemindTime,
            'Aylık iş hatırlatma saati',
            (v) => _monthlyRemindTime = v,
          ),
        ),
        const Divider(height: 16),
        _SwitchRow(
          key: const Key('settings-quiet-hours'),
          title: 'Sessiz saatler',
          subtitle: 'Bu aralığa denk gelen bildirim bitiş saatine ertelenir.',
          value: _quietHoursEnabled,
          onChanged: (v) => setState(() => _quietHoursEnabled = v),
        ),
        if (_quietHoursEnabled) ...[
          _TimeRow(
            key: const Key('settings-quiet-start'),
            title: 'Başlangıç',
            value: _quietStart,
            onTap: () => _pickTime(
              _quietStart,
              'Sessiz saat başlangıcı',
              (v) => _quietStart = v,
            ),
          ),
          _TimeRow(
            key: const Key('settings-quiet-end'),
            title: 'Bitiş',
            value: _quietEnd,
            onTap: () => _pickTime(
              _quietEnd,
              'Sessiz saat bitişi',
              (v) => _quietEnd = v,
            ),
          ),
          if (_quietStart == _quietEnd)
            const _Hint(
              'Başlangıç ve bitiş aynı olduğu için sessiz saat uygulanmaz.',
            ),
        ],
      ],
    );
  }

  Widget _teamCard() {
    final full = _team.length >= SettingsLimits.teamMax;
    return _Section(
      icon: Icons.groups_rounded,
      title: 'Ekip',
      color: AppColors.fitness,
      trailing: '${_team.length}/${SettingsLimits.teamMax}',
      children: [
        if (_team.isEmpty)
          const _Hint('Henüz kimse yok. Görevlerde seçmek için isim ekle.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final name in _team)
                InputChip(
                  label: Text(name),
                  backgroundColor: AppColors.surfaceHigh,
                  side: BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  deleteButtonTooltipMessage: '$name adını sil',
                  onDeleted: () => setState(() {
                    _team = _team.where((m) => m != name).toList();
                    _teamError = null;
                  }),
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
                controller: _teamInput,
                enabled: !full,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: SettingsLimits.teamNameMaxLength,
                onSubmitted: (_) => _addMember(),
                onChanged: (_) {
                  if (_teamError != null) setState(() => _teamError = null);
                },
                decoration: InputDecoration(
                  labelText: full ? 'Liste dolu' : 'İsim ekle',
                  counterText: '',
                  errorText: _teamError,
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
                onPressed: full ? null : _addMember,
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectionsCard() {
    final health = ref.watch(healthTodayProvider);
    final permission = ref.watch(notificationPermissionProvider);
    // Apple satırı yalnızca Apple Health seçiliyken HealthKit okumasını
    // yorumlar; Google seçiliyken okuma Google'ındır.
    final appleActive =
        ref.watch(healthSourceProvider) == HealthSourceKind.appleHealth;

    final (healthText, healthColor) = !appleActive
        ? ('Kaynak olarak seçili değil', AppColors.textMuted)
        : health.when(
            skipLoadingOnRefresh: false,
            loading: () => ('Kontrol ediliyor…', AppColors.textMuted),
            error: (_, __) => ('Okunamadı', AppColors.warning),
            data: (s) => switch (s.status) {
              HealthStatus.ok when s.hasData => ('Bağlı', AppColors.accent),
              HealthStatus.ok => (
                  'Bağlı, bugün için veri yok',
                  AppColors.textSecondary
                ),
              HealthStatus.denied => ('İzin verilmedi', AppColors.warning),
              HealthStatus.unavailable => (
                  'Bu cihazda kullanılamıyor',
                  AppColors.textMuted
                ),
              HealthStatus.notConnected ||
              HealthStatus.reconnect ||
              HealthStatus.failed =>
                ('Okunamadı', AppColors.warning),
            },
          );
    final healthUnavailable = !appleActive ||
        health.valueOrNull?.status == HealthStatus.unavailable;

    final (permissionText, permissionColor) = permission.when(
      skipLoadingOnRefresh: false,
      loading: () => ('Kontrol ediliyor…', AppColors.textMuted),
      error: (_, __) => ('Bilinmiyor', AppColors.textMuted),
      data: (granted) => granted
          ? ('Açık', AppColors.accent)
          : ('Kapalı · iPhone Ayarlar > Bildirimler', AppColors.warning),
    );

    return _Section(
      icon: Icons.link_rounded,
      title: 'Bağlantılar',
      color: AppColors.nutrition,
      children: [
        const HealthSourcePicker(),
        const Divider(height: 24),
        _StatusRow(
          icon: Icons.favorite_rounded,
          title: 'Apple Sağlık',
          status: healthText,
          statusColor: healthColor,
          actionLabel: 'Yeniden bağlan',
          onAction:
              health.isLoading || healthUnavailable ? null : _reconnectHealth,
        ),
        const Divider(height: 16),
        const GoogleHealthRow(),
        const Divider(height: 16),
        _StatusRow(
          icon: Icons.notifications_active_rounded,
          title: 'Bildirim izni',
          status: permissionText,
          statusColor: permissionColor,
          actionLabel: 'İzin iste',
          onAction: permission.isLoading || permission.valueOrNull == true
              ? null
              : _requestNotifications,
        ),
      ],
    );
  }

  Widget _accountCard() {
    final theme = Theme.of(context);
    final email = ref.watch(
      authSessionProvider.select((s) => s.valueOrNull?.user.email),
    );
    return _Section(
      icon: Icons.person_rounded,
      title: 'Hesap',
      color: AppColors.textSecondary,
      children: [
        Text(
          'E-posta',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          email == null || email.isEmpty ? 'Oturum bilgisi yok' : email,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: _signingOut ? null : _signOut,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(_signingOut ? 'Çıkış yapılıyor…' : 'Çıkış yap'),
        ),
      ],
    );
  }
}

/// Başlıklı bölüm kartı.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BentoLabel(icon: icon, label: title, color: color, trailing: trailing),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// Yan yana iki alan; hata metinleri hizayı bozmasın diye üstten hizalanır.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpacing.grid),
          Expanded(child: right),
        ],
      ),
    );
  }
}

String _showNumber(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Sayı alanı denetimi; hata yoksa `null`. [optional] ise boş metin geçerlidir.
String? _validateNumber(
  String? text, {
  required num min,
  required num max,
  bool decimal = false,
  bool optional = false,
}) {
  final raw = (text ?? '').trim();
  final range = '${_showNumber(min)}–${_showNumber(max)} arası olmalı';
  if (raw.isEmpty) return optional ? null : range;
  final num? value = decimal
      ? double.tryParse(raw.replaceAll(',', '.'))
      : int.tryParse(raw);
  if (value == null || value.isNaN || value < min || value > max) {
    return range;
  }
  return null;
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.decimal = false,
    this.optional = false,
    this.helper,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final num min;
  final num max;
  final bool decimal;

  /// Boş bırakılabilir (profil alanları); dolu ise yine aralık denetlenir.
  final bool optional;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
        LengthLimitingTextInputFormatter(decimal ? 6 : 5),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) => _validateNumber(
        text,
        min: min,
        max: max,
        decimal: decimal,
        optional: optional,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorMaxLines: 2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    super.key,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final TimeOfDayValue value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: Text(
            value.format(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String status;
  final Color statusColor;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge),
                  Text(
                    status,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: statusColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

/// Görünüm tercihi (Sistem / Açık / Koyu). Cihaza özgüdür: seçilir seçilmez
/// uygulanır, kaydedilmemiş değişikliklere ve Supabase'e dahil değildir.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  static IconData _icon(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => Icons.brightness_auto_rounded,
        AppThemeMode.light => Icons.light_mode_rounded,
        AppThemeMode.dark => Icons.dark_mode_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return _Section(
      icon: Icons.palette_rounded,
      title: 'Görünüm',
      color: AppColors.warning,
      children: [
        SegmentedButton<AppThemeMode>(
          key: const Key('settings-theme-mode'),
          showSelectedIcon: false,
          segments: [
            for (final option in AppThemeMode.values)
              ButtonSegment(
                value: option,
                label: Text(option.label),
                icon: Icon(_icon(option)),
              ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) =>
              ref.read(themeModeProvider.notifier).select(selection.first),
          style: SegmentedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textSecondary,
            selectedBackgroundColor: AppColors.surfaceHigh,
            selectedForegroundColor: AppColors.accent,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.inner),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const _Hint('Sistem, iPhone\'un açık/koyu ayarını izler.'),
      ],
    );
  }
}
