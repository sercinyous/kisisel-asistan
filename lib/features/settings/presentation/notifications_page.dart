import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_sync.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/user_settings.dart';
import 'settings_providers.dart';
import 'settings_widgets.dart';

/// Hesap › Bildirimler: izin durumu, hatırlatma tercihleri ve sessiz saatler.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Bildirimler',
      builder: (settings) => _NotificationsForm(settings: settings),
    );
  }
}

class _NotificationsForm extends ConsumerStatefulWidget {
  const _NotificationsForm({required this.settings});

  final UserSettings settings;

  @override
  ConsumerState<_NotificationsForm> createState() => _NotificationsFormState();
}

class _NotificationsFormState extends ConsumerState<_NotificationsForm> {
  final _formKey = GlobalKey<FormState>();
  final _leadDays = TextEditingController();
  final _eventMinutes = TextEditingController();

  late UserSettings _saved;
  late bool _enabled;
  late bool _routine;
  late bool _quiet;
  late TimeOfDayValue _monthlyTime;
  late TimeOfDayValue _quietStart;
  late TimeOfDayValue _quietEnd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(widget.settings);
    _leadDays.addListener(_onChanged);
    _eventMinutes.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _NotificationsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settings, widget.settings) && !_dirty) {
      _load(widget.settings);
    }
  }

  @override
  void dispose() {
    _leadDays.dispose();
    _eventMinutes.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _load(UserSettings s) {
    _saved = s;
    _leadDays.text = '${s.monthlyLeadDays}';
    _eventMinutes.text = '${s.eventRemindMinutes}';
    _enabled = s.notificationsEnabled;
    _routine = s.routineNotifications;
    _quiet = s.quietHoursEnabled;
    _monthlyTime = s.monthlyRemindTime;
    _quietStart = s.quietStart;
    _quietEnd = s.quietEnd;
  }

  bool get _dirty =>
      _leadDays.text.trim() != '${_saved.monthlyLeadDays}' ||
      _eventMinutes.text.trim() != '${_saved.eventRemindMinutes}' ||
      _enabled != _saved.notificationsEnabled ||
      _routine != _saved.routineNotifications ||
      _quiet != _saved.quietHoursEnabled ||
      _monthlyTime != _saved.monthlyRemindTime ||
      _quietStart != _saved.quietStart ||
      _quietEnd != _saved.quietEnd;

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showSettingsSnack(messenger, 'Kırmızı işaretli alanları düzelt.');
      return;
    }
    setState(() => _saving = true);
    try {
      final base = ref.read(userSettingsProvider).valueOrNull ?? _saved;
      final saved = await ref.read(userSettingsProvider.notifier).save(
            base.copyWith(
              notificationsEnabled: _enabled,
              routineNotifications: _routine,
              monthlyLeadDays: int.parse(_leadDays.text.trim()),
              monthlyRemindTime: _monthlyTime,
              eventRemindMinutes: int.parse(_eventMinutes.text.trim()),
              quietHoursEnabled: _quiet,
              quietStart: _quietStart,
              quietEnd: _quietEnd,
            ),
          );
      // Yeni tercihlerle bekleyen bildirimler baştan planlanır.
      ref.invalidate(notificationSyncProvider);
      if (mounted) setState(() => _load(saved));
      showSettingsSnack(messenger, 'Kaydedildi.');
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

  /// İzin yalnızca kullanıcı butona basınca istenir; ekranı açmak sormaz.
  Future<void> _requestPermission() async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(notificationServiceProvider).requestPermission();
    container
      ..invalidate(notificationPermissionProvider)
      ..invalidate(notificationSyncProvider);
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
                  _permissionCard(),
                  const SizedBox(height: AppSpacing.grid),
                  _preferencesCard(),
                ],
              ),
            ),
            SettingsSaveBar(enabled: dirty, saving: _saving, onSave: _save),
          ],
        ),
      ),
    );
  }

  Widget _permissionCard() {
    final permission = ref.watch(notificationPermissionProvider);
    final (text, color) = permission.when(
      skipLoadingOnRefresh: false,
      loading: () => ('Kontrol ediliyor…', AppColors.textMuted),
      error: (_, __) => ('Bilinmiyor', AppColors.textMuted),
      data: (granted) => granted
          ? ('Açık', AppColors.accent)
          : ('Kapalı · iPhone Ayarlar > Bildirimler', AppColors.warning),
    );
    return SettingsSection(
      icon: Icons.notifications_active_rounded,
      title: 'İzin',
      color: AppColors.ops,
      children: [
        SettingsStatusRow(
          icon: Icons.phone_iphone_rounded,
          title: 'Bildirim izni',
          status: text,
          statusColor: color,
          actionLabel: 'İzin iste',
          onAction: permission.isLoading || permission.valueOrNull == true
              ? null
              : _requestPermission,
        ),
      ],
    );
  }

  Widget _preferencesCard() {
    final on = _enabled;
    return SettingsSection(
      icon: Icons.notifications_rounded,
      title: 'Hatırlatmalar',
      color: AppColors.ops,
      children: [
        SettingsSwitchRow(
          key: const Key('settings-notifications'),
          title: 'Tüm bildirimler',
          subtitle: 'Kapalıyken hiçbir hatırlatma gelmez.',
          value: on,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        SettingsSwitchRow(
          key: const Key('settings-routine-notifications'),
          title: 'Rutin bildirimleri',
          subtitle: 'Günlük ve haftalık rutinler saatinde hatırlatılır.',
          value: _routine,
          onChanged: on ? (v) => setState(() => _routine = v) : null,
        ),
        const SizedBox(height: 8),
        SettingsFieldRow(
          left: SettingsNumberField(
            fieldKey: const Key('settings-lead-days'),
            controller: _leadDays,
            label: 'Aylık iş (gün önce)',
            min: SettingsLimits.leadDaysMin,
            max: SettingsLimits.leadDaysMax,
          ),
          right: SettingsNumberField(
            fieldKey: const Key('settings-event-minutes'),
            controller: _eventMinutes,
            label: 'Randevu (dk önce)',
            min: SettingsLimits.eventMinutesMin,
            max: SettingsLimits.eventMinutesMax,
          ),
        ),
        SettingsTimeRow(
          key: const Key('settings-monthly-time'),
          title: 'Aylık iş hatırlatma saati',
          value: _monthlyTime,
          onTap: () => _pickTime(
            _monthlyTime,
            'Aylık iş hatırlatma saati',
            (v) => _monthlyTime = v,
          ),
        ),
        const Divider(height: 16),
        SettingsSwitchRow(
          key: const Key('settings-quiet-hours'),
          title: 'Sessiz saatler',
          subtitle: 'Bu aralığa denk gelen bildirim bitiş saatine ertelenir.',
          value: _quiet,
          onChanged: (v) => setState(() => _quiet = v),
        ),
        if (_quiet) ...[
          SettingsTimeRow(
            key: const Key('settings-quiet-start'),
            title: 'Başlangıç',
            value: _quietStart,
            onTap: () => _pickTime(
              _quietStart,
              'Sessiz saat başlangıcı',
              (v) => _quietStart = v,
            ),
          ),
          SettingsTimeRow(
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
            const SettingsHint(
              'Başlangıç ve bitiş aynı olduğu için sessiz saat uygulanmaz.',
            ),
        ],
      ],
    );
  }
}
