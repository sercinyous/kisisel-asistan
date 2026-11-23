import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../onboarding/domain/goal_suggestion.dart' show TargetLimits;
import '../../settings/presentation/settings_providers.dart';
import 'fat_loss_providers.dart';
import 'weight_sheets.dart';

const String fatLossDisclaimer =
    'Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.';
const String fatLossWaterNote =
    'İlk 1–2 hafta su kaybı yüzünden tartı daha hızlı düşer.';
const String fatLossFastWarning =
    'Hız 0,8 kg/haftayı aşıyor; halsizlik olursa kaloriyi 200–300 kcal artır.';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Yağ yakımı planı: son tartıdan kalori/makro hedefleri, haftalık kayıp,
/// besin karşılıkları ve örnek menü.
class FatLossScreen extends ConsumerWidget {
  const FatLossScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FatLossScreen()),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(fatLossPlanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Yağ yakımı planı')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          8,
          AppSpacing.page,
          120,
        ),
        child: plan.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => BentoGrid(children: [
            BentoCell(
              child: BentoCard(
                onTap: () => ref.invalidate(fatLossPlanProvider),
                child:
                    const Text('Kilo yüklenemedi. Yeniden denemek için dokun.'),
              ),
            ),
          ]),
          data: (state) =>
              state == null ? const _EmptyState() : _PlanBody(state: state),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BentoGrid(children: [
      BentoCell(
        child: BentoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BentoLabel(
                icon: Icons.local_fire_department_outlined,
                label: 'Yağ yakımı',
                color: AppColors.nutrition,
              ),
              const SizedBox(height: 12),
              Text(
                'Planı hesaplamak için bir kilo ölçümü gerekli.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('fat-loss-add-weight'),
                onPressed: () => WeightFormSheet.show(context),
                child: const Text('Kilo ekle'),
              ),
              const SizedBox(height: 12),
              Text(
                fatLossDisclaimer,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.state});

  final FatLossPlanState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BentoGrid(children: [
          BentoCell(child: _TargetsCard(state: state)),
          BentoCell(child: _WeeklyCard(state: state)),
          BentoCell(child: _EquivalentsCard(targets: state.targets)),
          BentoCell(child: _MenuCard(targets: state.targets)),
        ]),
        const SizedBox(height: 16),
        Text(
          fatLossDisclaimer,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _TargetsCard extends ConsumerWidget {
  const _TargetsCard({required this.state});

  final FatLossPlanState state;

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final t = state.targets;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hedefler güncellensin mi?'),
        content: Text(
          'Günlük hedeflerin ${formatTr(t.kcal)} kcal, ${t.proteinG} g protein, '
          '${t.fatG} g yağ ve ${t.carbsG} g karbonhidrat olacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            key: const Key('fat-loss-apply-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ayarla'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(userSettingsProvider.notifier);
    try {
      final current = await ref.read(userSettingsProvider.future);
      await notifier.save(current.copyWith(
        dailyCalories: t.kcal
            .clamp(TargetLimits.caloriesMin, TargetLimits.caloriesMax)
            .toInt(),
        dailyProteinG: t.proteinG
            .clamp(TargetLimits.proteinMin, TargetLimits.proteinMax)
            .toInt(),
        dailyFatG:
            t.fatG.clamp(TargetLimits.fatMin, TargetLimits.fatMax).toInt(),
        dailyCarbsG: t.carbsG
            .clamp(TargetLimits.carbsMin, TargetLimits.carbsMax)
            .toInt(),
      ));
      messenger.showSnackBar(
        const SnackBar(content: Text('Hedefler güncellendi')),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Hedefler kaydedilemedi')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = state.targets;
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.local_fire_department_outlined,
            label: 'Günlük hedef',
            color: AppColors.nutrition,
            trailing:
                '${formatTrDecimal(state.weight.weightKg)} kg · ${_date(state.weight.loggedAt)}',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatTr(t.kcal),
                key: const Key('fat-loss-kcal'),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'kcal',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Macro(
                  label: 'Protein',
                  grams: t.proteinG,
                  color: AppColors.fitness),
              _Macro(label: 'Yağ', grams: t.fatG, color: AppColors.warning),
              _Macro(
                  label: 'Karb', grams: t.carbsG, color: AppColors.nutrition),
              _Macro(label: 'Lif', grams: t.fiberG, color: AppColors.water),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: const Key('fat-loss-apply'),
              onPressed: () => _apply(context, ref),
              child: const Text('Hedeflerimi buna göre ayarla'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.grams, required this.color});

  final String label;
  final int grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatTr(grams)} g',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WeeklyCard extends ConsumerWidget {
  const _WeeklyCard({required this.state});

  final FatLossPlanState state;

  Future<void> _editExpenditure(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: '${ref.read(manualExpenditureProvider)}');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Günlük harcama'),
        content: TextField(
          key: const Key('fat-loss-expenditure-field'),
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: 'kcal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await ref.read(manualExpenditureProvider.notifier).set(value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekly = state.weekly;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.trending_down,
            label: 'Haftalık kayıp',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 12),
          if (weekly.hasLoss)
            Text(
              '≈ ${formatTrDecimal(weekly.weeklyKg)} kg/hafta',
              key: const Key('fat-loss-weekly'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              'Harcama hedef kaloriden yüksek değil; bu planla kilo kaybı beklenmez.',
              key: const Key('fat-loss-no-loss'),
              style: theme.textTheme.bodyLarge,
            ),
          const SizedBox(height: 8),
          Text(
            'Günlük harcama ${formatTr(weekly.expenditureKcal)} kcal − hedef '
            '${formatTr(weekly.targetKcal)} kcal = açık ${formatTr(weekly.deficitKcal)} kcal',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          if (state.expenditure.fromProfile)
            Text('Harcama profilinden (bazal × hareket düzeyi) hesaplandı.',
                style: muted)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('fat-loss-edit-expenditure'),
                onPressed: () => _editExpenditure(context, ref),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Günlük harcamayı düzenle'),
              ),
            ),
          if (weekly.isTooFast) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fatLossFastWarning,
                    key: const Key('fat-loss-warning'),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ],
          if (weekly.hasLoss) ...[
            const SizedBox(height: 8),
            Text(fatLossWaterNote, style: muted),
          ],
        ],
      ),
    );
  }
}

class _EquivalentsCard extends StatefulWidget {
  const _EquivalentsCard({required this.targets});

  final FatLossTargets targets;

  @override
  State<_EquivalentsCard> createState() => _EquivalentsCardState();
}

class _EquivalentsCardState extends State<_EquivalentsCard> {
  FatLossMacro _macro = FatLossMacro.protein;
  int _meals = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amounts = equivalentsFor(widget.targets, _macro, meals: _meals);
    final grams = widget.targets.gramsFor(_macro);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.restaurant_outlined,
            label: 'Besin karşılıkları',
            color: AppColors.nutrition,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<FatLossMacro>(
              showSelectedIcon: false,
              segments: [
                for (final m in FatLossMacro.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_macro},
              onSelectionChanged: (s) => setState(() => _macro = s.first),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Öğün sayısı', style: theme.textTheme.bodyMedium),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                ],
                selected: {_meals},
                onSelectionChanged: (s) => setState(() => _meals = s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _meals == 1
                ? 'Günlük ${formatTr(grams)} g ${_macro.label.toLowerCase()} için tek başına:'
                : 'Öğün başına ${formatTr(grams / _meals)} g ${_macro.label.toLowerCase()} için tek başına:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final a in amounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(a.label, style: theme.textTheme.bodyLarge),
            ),
          const SizedBox(height: 4),
          Text(
            'Pişmiş, 100 g değerleriyle; yaklaşık miktarlar.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatefulWidget {
  const _MenuCard({required this.targets});

  final FatLossTargets targets;

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  int _meals = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = scaledMenu(_meals, widget.targets);
    final totals = menuTotals(menu);
    return BentoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.menu_book_outlined,
            label: 'Örnek menü',
            color: AppColors.nutrition,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 2, label: Text('2 öğün')),
                ButtonSegment(value: 3, label: Text('3 öğün')),
              ],
              selected: {_meals},
              onSelectionChanged: (s) => setState(() => _meals = s.first),
            ),
          ),
          for (final meal in menu) ...[
            const SizedBox(height: 12),
            Text(
              meal.name,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meal.items.map((i) => i.label).join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Toplam ${formatTr(totals.kcal)} kcal · P ${formatTr(totals.protein)} g · '
            'Y ${formatTr(totals.fat)} g · K ${formatTr(totals.carbs)} g · '
            'Lif ${formatTr(totals.fiber)} g',
            key: const Key('fat-loss-menu-total'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sağlık › Beslenme'deki kısa giriş kartı.
class FatLossEntryCard extends ConsumerWidget {
  const FatLossEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(fatLossPlanProvider).valueOrNull;
    final text = plan == null
        ? 'Yağ yakımı'
        : 'Yağ yakımı · ${formatTr(plan.targets.kcal)} kcal';
    return BentoCard(
      key: const Key('fat-loss-entry'),
      onTap: () => FatLossScreen.open(context),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined,
              size: 20, color: AppColors.nutrition),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
