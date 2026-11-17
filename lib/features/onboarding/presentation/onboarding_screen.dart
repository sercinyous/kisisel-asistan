import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/health_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/templates/routine_templates.dart';
import '../../../core/theme/app_theme.dart';
import '../../health/data/health_repository.dart';
import '../../health/domain/energy_balance.dart';
import '../../health/presentation/health_providers.dart';
import '../../operations/presentation/operations_providers.dart';
import '../../routines/data/routines_repository.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/onboarding_writer.dart';
import '../domain/goal_suggestion.dart';
import '../domain/onboarding_answers.dart';
import '../domain/onboarding_result.dart';
import 'onboarding_health_step.dart';
import 'onboarding_intro.dart';
import 'onboarding_preferences_step.dart';
import 'onboarding_profile_step.dart';
import 'onboarding_routines_step.dart';
import 'onboarding_targets_step.dart';

/// İlk kurulumun adımları: 5 kartlık tanıtım, sorular, hedefler, bildirimler,
/// başlangıç rutinleri, sağlık kaynağı.
enum OnboardingStep { intro, profile, targets, preferences, routines, health }

/// İlk kurulum: kılavuz ve sorular. Giriş sonrası `onboarded_at` boşsa kapı
/// bunu gösterir; sonuç tek `user_settings` kaydıyla yazılır, seçilen rutinler
/// eklenir, kilo cevabı ayrıca tartı kaydı olur ve `onboarded_at` dolar.
///
/// [replay] Ayarlar'dan "Kılavuzu yeniden göster": yalnızca 5 tanıtım kartı,
/// hiçbir şey yazılmaz, bitince ekran kapanır.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false, this.clock});

  final bool replay;

  /// Yaş sınırı ve `onboarded_at` için saat; boşsa `DateTime.now`.
  final DateTime Function()? clock;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const String _saveError =
      'Kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

  final _scroll = ScrollController();
  OnboardingStep _step = OnboardingStep.intro;
  int _introPage = 0;

  // 2. adım: sorular.
  final _name = TextEditingController();
  final _height = TextEditingController();
  final _birthYear = TextEditingController();
  final _weight = TextEditingController();
  final _targetWeight = TextEditingController();
  final _work = TextEditingController();
  Sex? _sex;
  OnboardingGoal? _goal;

  // 3. adım: hedefler (hesap imzası değişmedikçe düzenlemeler korunur).
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _steps = TextEditingController();
  final _sleep = TextEditingController();
  String? _targetsFor;

  // 4. adım: bildirimler.
  bool _notificationsEnabled = true;
  OnboardingPermission _permission = OnboardingPermission.unknown;
  bool _quietEnabled = true;
  TimeOfDayValue _quietStart = const TimeOfDayValue(23, 0);
  TimeOfDayValue _quietEnd = const TimeOfDayValue(7, 30);

  // 5. adım: başlangıç rutinleri (şablon kimlikleri). Varsayılan boş.
  final Set<String> _routineIds = {};

  // 6. adım: sağlık kaynağı.
  OnboardingHealthAccess _health = OnboardingHealthAccess.idle;

  bool _saving = false;
  String? _error;
  OnboardingWriter? _writer;

  late final List<TextEditingController> _tracked = [
    _name,
    _height,
    _birthYear,
    _weight,
    _targetWeight,
    _work,
    _calories,
    _protein,
    _carbs,
    _fat,
    _steps,
    _sleep,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _tracked) {
      c.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final c in _tracked) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool get _atStart => _step == OnboardingStep.intro && _introPage == 0;

  OnboardingAnswers? get _answers => OnboardingAnswers.tryParse(
        displayName: _name.text,
        height: _height.text,
        birthYear: _birthYear.text,
        sex: _sex,
        weight: _weight.text,
        targetWeight: _targetWeight.text,
        goal: _goal,
        workDescription: _work.text,
        nowYear: _now().year,
      );

  OnboardingTargets? get _targets {
    final calories = TargetLimits.parse(
        _calories.text, TargetLimits.caloriesMin, TargetLimits.caloriesMax);
    final protein = TargetLimits.parse(
        _protein.text, TargetLimits.proteinMin, TargetLimits.proteinMax);
    final carbs = TargetLimits.parse(
        _carbs.text, TargetLimits.carbsMin, TargetLimits.carbsMax);
    final fat =
        TargetLimits.parse(_fat.text, TargetLimits.fatMin, TargetLimits.fatMax);
    final steps = TargetLimits.parse(
        _steps.text, TargetLimits.stepsMin, TargetLimits.stepsMax);
    final sleep = TargetLimits.parse(
        _sleep.text, TargetLimits.sleepMin, TargetLimits.sleepMax);
    if (calories == null ||
        protein == null ||
        carbs == null ||
        fat == null ||
        steps == null ||
        sleep == null) {
      return null;
    }
    return OnboardingTargets(
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      steps: steps,
      sleepMinutes: sleep,
    );
  }

  bool get _canNext {
    if (_saving) return false;
    return switch (_step) {
      OnboardingStep.profile => _answers != null,
      OnboardingStep.targets => _targets != null,
      _ => true,
    };
  }

  String get _nextLabel => switch (_step) {
        OnboardingStep.intro when _introPage == onboardingIntroCards.length - 1 =>
          widget.replay ? 'Bitti' : 'Başlayalım',
        OnboardingStep.health => 'Başla',
        _ => 'İleri',
      };

  void _goTo(OnboardingStep step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _fillTargets(OnboardingTargets t) {
    _calories.text = '${t.calories}';
    _protein.text = '${t.proteinG}';
    _carbs.text = '${t.carbsG}';
    _fat.text = '${t.fatG}';
    _steps.text = '${t.steps}';
    _sleep.text = '${t.sleepMinutes}';
  }

  void _resetTargets() {
    final answers = _answers;
    if (answers == null) return;
    _fillTargets(GoalSuggestion.compute(answers, nowYear: _now().year));
    _targetsFor = answers.targetsSignature;
  }

  void _next() {
    if (!_canNext) return;
    switch (_step) {
      case OnboardingStep.intro:
        if (_introPage < onboardingIntroCards.length - 1) {
          setState(() => _introPage++);
        } else if (widget.replay) {
          Navigator.of(context).pop();
        } else {
          _goTo(OnboardingStep.profile);
        }
      case OnboardingStep.profile:
        final answers = _answers!;
        // Hesabı etkileyen cevap değiştiyse hedefler yeniden önerilir.
        if (_targetsFor != answers.targetsSignature) _resetTargets();
        _goTo(OnboardingStep.targets);
      case OnboardingStep.targets:
        _goTo(OnboardingStep.preferences);
      case OnboardingStep.preferences:
        _goTo(OnboardingStep.routines);
      case OnboardingStep.routines:
        _goTo(OnboardingStep.health);
      case OnboardingStep.health:
        unawaited(_finish());
    }
  }

  void _back() {
    if (_saving) return;
    if (_step == OnboardingStep.intro) {
      if (_introPage > 0) setState(() => _introPage--);
      return;
    }
    if (_step == OnboardingStep.profile) {
      setState(() => _introPage = onboardingIntroCards.length - 1);
    }
    _goTo(OnboardingStep.values[_step.index - 1]);
  }

  Future<void> _signOut() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Çıkış yapılamadı. Tekrar dene.')),
        );
    }
  }

  Future<void> _requestNotificationPermission() async {
    final service = ref.read(notificationServiceProvider);
    setState(() => _permission = OnboardingPermission.requesting);
    var granted = false;
    try {
      granted = await service.requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _permission =
        granted ? OnboardingPermission.granted : OnboardingPermission.denied);
  }

  Future<void> _requestHealthAccess() async {
    final service = ref.read(healthServiceProvider);
    if (!service.isSupported) {
      setState(() => _health = OnboardingHealthAccess.unavailable);
      return;
    }
    setState(() => _health = OnboardingHealthAccess.requesting);
    var granted = false;
    try {
      granted = await service.requestAccess();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _health =
        granted ? OnboardingHealthAccess.granted : OnboardingHealthAccess.denied);
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final current = start ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: start ? 'Sessiz saat başlangıcı' : 'Sessiz saat bitişi',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final value = TimeOfDayValue(picked.hour, picked.minute);
    setState(() => start ? _quietStart = value : _quietEnd = value);
  }

  /// Sonucu yazar: tartı, rutinler, en son tek ayar kaydı. Başarıda ayar
  /// kaydı kapıyı açar ve bu ekran sökülür; hatada aynı adımdan yeniden denenir.
  Future<void> _finish() async {
    final answers = _answers;
    final targets = _targets;
    if (answers == null || targets == null || _saving) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final base =
        ref.read(userSettingsProvider).valueOrNull ?? const UserSettings.defaults();
    final result = buildOnboardingResult(
      base: base,
      answers: answers,
      targets: targets,
      preferences: OnboardingPreferences(
        notificationsEnabled: _notificationsEnabled,
        quietHoursEnabled: _quietEnabled,
        quietStart: _quietStart,
        quietEnd: _quietEnd,
      ),
      routines: [
        for (final t in RoutineTemplates.starters)
          if (_routineIds.contains(t.id)) t,
      ],
      now: _now(),
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    final writer = _writer ??= OnboardingWriter(
      addWeight: (kg) => container.read(healthRepositoryProvider).addWeight(kg),
      createRoutine: (routine) =>
          container.read(routinesRepositoryProvider).create(routine),
      saveSettings: (settings) async {
        // Yeni tartı ve rutinler ana kabuk açılmadan önce görünsün.
        invalidateHealthData(container);
        notifyRoutineChange(container.invalidate);
        return container.read(userSettingsProvider.notifier).save(settings);
      },
    );
    try {
      await writer.complete(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _saveError;
      });
    }
  }

  static Color _introAccent(int index) => switch (index) {
        2 => AppColors.ops,
        3 => AppColors.fitness,
        4 => AppColors.nutrition,
        _ => AppColors.accent,
      };

  Widget _content() {
    switch (_step) {
      case OnboardingStep.intro:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OnboardingIntroPage(
              key: ValueKey('intro-$_introPage'),
              card: onboardingIntroCards[_introPage],
              accent: _introAccent(_introPage),
            ),
            const SizedBox(height: 16),
            OnboardingDots(
              count: onboardingIntroCards.length,
              index: _introPage,
            ),
            if (!widget.replay)
              Align(
                child: TextButton(
                  key: const Key('onboarding-skip-intro'),
                  onPressed: () => _goTo(OnboardingStep.profile),
                  child: const Text('Tanıtımı atla'),
                ),
              ),
          ],
        );
      case OnboardingStep.profile:
        return OnboardingProfileStep(
          name: _name,
          height: _height,
          birthYear: _birthYear,
          weight: _weight,
          targetWeight: _targetWeight,
          work: _work,
          sex: _sex,
          onSex: (value) => setState(() => _sex = value),
          goal: _goal,
          onGoal: (value) => setState(() => _goal = value),
          nowYear: _now().year,
        );
      case OnboardingStep.targets:
        return OnboardingTargetsStep(
          goal: _goal ?? OnboardingGoal.maintain,
          calories: _calories,
          protein: _protein,
          carbs: _carbs,
          fat: _fat,
          steps: _steps,
          sleep: _sleep,
          onReset: _resetTargets,
        );
      case OnboardingStep.preferences:
        return OnboardingPreferencesStep(
          notificationsEnabled: _notificationsEnabled,
          onNotifications: (value) => setState(() => _notificationsEnabled = value),
          permission: _permission,
          onRequestPermission: _requestNotificationPermission,
          quietEnabled: _quietEnabled,
          onQuiet: (value) => setState(() => _quietEnabled = value),
          quietStart: _quietStart,
          quietEnd: _quietEnd,
          onPickStart: () => _pickQuietTime(start: true),
          onPickEnd: () => _pickQuietTime(start: false),
        );
      case OnboardingStep.routines:
        return OnboardingRoutinesStep(
          selected: _routineIds,
          onToggle: (id, value) => setState(
            () => value ? _routineIds.add(id) : _routineIds.remove(id),
          ),
          onSelectAll: () => setState(
            () => _routineIds.addAll(RoutineTemplates.starters.map((t) => t.id)),
          ),
          onClear: () => setState(_routineIds.clear),
        );
      case OnboardingStep.health:
        return OnboardingHealthStep(
          access: _health,
          onRequest: _requestHealthAccess,
        );
    }
  }

  Widget _header() {
    final theme = Theme.of(context);
    final stepCount = OnboardingStep.values.length;
    final fraction = _step == OnboardingStep.intro
        ? (_introPage + 1) / onboardingIntroCards.length
        : 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.grid,
        AppSpacing.page,
        4,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.replay
                        ? 'Kılavuz'
                        : 'Adım ${_step.index + 1} / $stepCount',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                if (widget.replay)
                  IconButton(
                    key: const Key('onboarding-close'),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  TextButton(
                    key: const Key('onboarding-sign-out'),
                    onPressed: _saving ? null : _signOut,
                    child: const Text('Çıkış yap'),
                  ),
              ],
            ),
          ),
          if (!widget.replay)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                key: const Key('onboarding-progress'),
                value: (_step.index + fraction) / stepCount,
                minHeight: 4,
                backgroundColor: AppColors.surfaceHigh,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.grid,
        AppSpacing.page,
        AppSpacing.page,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const Key('onboarding-error'),
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ),
          Row(
            children: [
              if (!_atStart) ...[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('onboarding-back'),
                    onPressed: _saving ? null : _back,
                    child: const Text('Geri'),
                  ),
                ),
                const SizedBox(width: AppSpacing.grid),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('onboarding-next'),
                  onPressed: _canNext ? _next : null,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_nextLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Sistem geri hareketi bir önceki adıma döner; ilk kartta ekrandan çıkar.
      canPop: _atStart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.grid,
                    AppSpacing.page,
                    AppSpacing.page,
                  ),
                  child: _content(),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }
}
