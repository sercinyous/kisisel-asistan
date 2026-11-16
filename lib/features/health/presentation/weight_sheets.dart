import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../operations/presentation/operations_widgets.dart';
import 'health_format.dart';
import 'health_providers.dart';
import 'health_widgets.dart';
import 'weight_card.dart';

/// Kilo ölçümü ekleme formu.
class WeightFormSheet extends ConsumerStatefulWidget {
  const WeightFormSheet({super.key});

  static Future<bool> show(BuildContext context) =>
      showOpsSheet(context, const WeightFormSheet());

  @override
  ConsumerState<WeightFormSheet> createState() => _WeightFormSheetState();
}

class _WeightFormSheetState extends ConsumerState<WeightFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = AppDates.startOfDay(now);
    _time = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final at = combineDateTime(_date, _time);
    if (at.isAfter(DateTime.now())) {
      setState(() => _error = 'Gelecekteki bir zaman seçilemez.');
      return;
    }
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await container
          .read(healthRepositoryProvider)
          .addWeight(parseDecimal(_weight.text)!, at: at);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = opsSaveError;
      });
      return;
    }
    invalidateHealthData(container);
    closeOpsSheet(navigator, route);
  }

  @override
  Widget build(BuildContext context) {
    return OpsSheetFrame(
      title: 'Kilo ekle',
      formKey: _formKey,
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        TextFormField(
          key: const Key('weight-kg'),
          controller: _weight,
          autofocus: true,
          keyboardType: healthDecimalKeyboard,
          decoration: const InputDecoration(
            labelText: 'Kilo',
            suffixText: 'kg',
          ),
          validator: (value) => validateDecimal(
            value,
            min: WeightLimits.minKg,
            max: WeightLimits.maxKg,
            required: true,
            decimals: 2,
          ),
        ),
        const OpsFieldLabel('Ölçüm zamanı'),
        HealthWhenPicker(
          date: _date,
          time: _time,
          onDate: (value) {
            if (mounted) setState(() => _date = value);
          },
          onTime: (value) {
            if (mounted) setState(() => _time = value);
          },
        ),
      ],
    );
  }
}

/// Seçili penceredeki ölçümlerin listesi; yanlış girilen ölçüm silinebilir.
class WeightHistorySheet extends ConsumerStatefulWidget {
  const WeightHistorySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
        ),
        builder: (context) => const WeightHistorySheet(),
      );

  @override
  ConsumerState<WeightHistorySheet> createState() => _WeightHistorySheetState();
}

class _WeightHistorySheetState extends ConsumerState<WeightHistorySheet> {
  String? _error;

  Future<void> _delete(WeightEntry entry) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await confirmDelete(
      context,
      title: 'Ölçüm silinsin mi?',
      message: '${HealthFormat.kg(entry.weightKg)} kg · '
          '${AppDates.relativeDayTime(entry.loggedAt)}',
    );
    if (!confirmed) return;
    try {
      await container.read(healthRepositoryProvider).deleteWeight(entry.id);
    } catch (_) {
      if (mounted) setState(() => _error = healthDeleteError);
      return;
    }
    invalidateHealthData(container);
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = ref.watch(weightWindowProvider);
    final series = ref.watch(weightSeriesProvider(window));

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ölçümler · son $window gün',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
          Flexible(
            child: series.when(
              skipLoadingOnRefresh: true,
              loading: () => const OpsLoading(),
              error: (_, __) => OpsMessage(
                icon: Icons.cloud_off_rounded,
                text: 'Kilo ölçümleri yüklenemedi.',
                onRetry: () => ref.invalidate(weightSeriesProvider),
              ),
              data: (entries) => entries.isEmpty
                  ? const OpsMessage(
                      icon: Icons.monitor_weight_outlined,
                      text: 'Bu aralıkta ölçüm yok.',
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 8, 16),
                      children: [
                        // Yeniden eskiye.
                        for (final entry in entries.reversed)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${HealthFormat.kg(entry.weightKg)} kg',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                AppDates.relativeDayTime(entry.loggedAt),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                onPressed: () => _delete(entry),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
