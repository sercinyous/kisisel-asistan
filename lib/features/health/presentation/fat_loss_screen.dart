import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bento.dart';
import '../../settings/presentation/settings_providers.dart';
import 'health_providers.dart' show weightSeriesProvider;
import 'fat_loss_providers.dart';
import 'weight_sheets.dart';

const String fatLossDisclaimer =
    'Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.';
const String fatLossWaterNote =
    'İlk 1–2 hafta su kaybı yüzünden tartı daha hızlı düşer.';
/// Haftalık kayıp hızlı/agresif sınıftayken gösterilen uyarı.
String fatLossFastWarning(RateHealth health) =>
    'Hız ${health.label.toLowerCase()} (vücut ağırlığının %0,7\'sinden fazla); '
    'halsizlik olursa kaloriyi 200–300 kcal artır.';

const String menuUnderNote =
    'Menü hedefin altında; porsiyonları biraz artırabilirsin.';

/// Klasik formül 1.200 kcal tabanının altındayken gösterilen uyarı.
String classicFloorWarning(int kcal) =>
    'Bu formül ${formatTr(kcal)} kcal veriyor; 1.200 kcal altına inmemen '
    'önerilir — hız seçeneklerinden birini kullan.';
const String fatLossLoadError = 'Plan yüklenemedi. Yeniden denemek için dokun.';
const String fatLossNegativeDeficit =
    'Hedef harcamanın üstünde; kilo kaybı beklenmez.';
const String fatLossExpenditureError = '1200–6000 arası gir';
const String fatLossApproxNote =
    'Yaklaşık değerler; pişmiş 100 g besin değerleriyle hesaplandı.';

const String supplementDisclaimer =
    'Genel bilgilendirmedir; takviye başlamadan önce doktoruna/eczacına '
    'danış. Hamilelik, emzirme ve kronik hastalıkta farklıdır.';

/// Hız modu kalori tabanına takıldığında gösterilen not.
String rateFloorNote(double actualKgPerWeek) => actualKgPerWeek <= 0
    ? 'Bu hız için kalori tabanına takıldı. Bu harcamayla kilo kaybı '
        'beklenmez.'
    : 'Bu hız için kalori tabanına takıldı; gerçek hız '
        '≈${formatTrDecimal2(actualKgPerWeek)} kg/hafta.';

/// Uygulamanın kalori sınırı nedeniyle değişen kaydın açıklaması.
String fatLossClampNote(int kcal) =>
    'Uygulamanın sınırı nedeniyle ${formatTr(kcal)} kcal olarak kaydedilecek.';

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
                key: const Key('fat-loss-retry'),
                onTap: () => ref
                  ..invalidate(weightSeriesProvider)
                  ..invalidate(userSettingsProvider)
                  ..invalidate(fatLossPlanProvider),
                child: const Text(fatLossLoadError),
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
          const BentoCell(child: TodayGapCard()),
          BentoCell(child: _TargetsCard(state: state)),
          BentoCell(child: FatLossRateCard(state: state)),
          BentoCell(child: _WeeklyCard(state: state)),
          BentoCell(child: _EquivalentsCard(targets: state.targets)),
          BentoCell(child: _MenuCard(targets: state.targets)),
          BentoCell(child: SupplementCard(state: state)),
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
    final v = fatLossApplyValues(state.targets);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hedefler güncellensin mi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Günlük hedeflerin ${formatTr(v.kcal)} kcal, ${v.proteinG} g protein, '
              '${v.fatG} g yağ ve ${v.carbsG} g karbonhidrat olacak.',
              key: const Key('fat-loss-apply-text'),
            ),
            if (v.clamped) ...[
              const SizedBox(height: 8),
              Text(
                fatLossClampNote(v.kcal),
                key: const Key('fat-loss-apply-clamp'),
                style: TextStyle(color: AppColors.warning),
              ),
            ],
          ],
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
        dailyCalories: v.kcal,
        dailyProteinG: v.proteinG,
        dailyFatG: v.fatG,
        dailyCarbsG: v.carbsG,
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
    final value = await showDialog<int>(
      context: context,
      builder: (_) =>
          ExpenditureDialog(initial: ref.read(manualExpenditureProvider)),
    );
    if (value != null) {
      await ref.read(manualExpenditureProvider.notifier).set(value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekly = state.weekly;
    final health = classifyRate(weekly.weeklyKg, state.weight.weightKg);
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
              '≈ ${formatTrDecimal2(weekly.weeklyKg)} kg/hafta',
              key: const Key('fat-loss-weekly'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              weekly.deficitKcal < 0
                  ? fatLossNegativeDeficit
                  : 'Harcama hedef kaloriden yüksek değil; bu planla kilo kaybı beklenmez.',
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
          if (state.expenditure.profileAvailable) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                key: const Key('fat-loss-expenditure-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Profilden hesapla')),
                  ButtonSegment(value: true, label: Text('Elle gir')),
                ],
                selected: {!state.expenditure.fromProfile},
                onSelectionChanged: (s) => ref
                    .read(manualExpenditureModeProvider.notifier)
                    .set(s.first),
              ),
            ),
            const SizedBox(height: 4),
          ],
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
          if (weekly.hasLoss && health != RateHealth.sustainable) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fatLossFastWarning(health),
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

class _MenuCard extends ConsumerWidget {
  const _MenuCard({required this.targets});

  final FatLossTargets targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meals = ref.watch(fatLossMealCountProvider);
    final menu = scaledMenu(meals, targets);
    final totals = menuTotals(menu);
    final under = menuUnderTarget(menu, targets);
    final t = targets;
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
              selected: {meals},
              onSelectionChanged: (s) =>
                  ref.read(fatLossMealCountProvider.notifier).state = s.first,
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
          const SizedBox(height: 4),
          Text(
            'Hedef ${formatTr(t.kcal)} kcal · P ${formatTr(t.proteinG)} g · '
            'Y ${formatTr(t.fatG)} g · K ${formatTr(t.carbsG)} g · '
            'Lif ${formatTr(t.fiberG)} g',
            key: const Key('fat-loss-menu-target'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (under) ...[
            const SizedBox(height: 4),
            Text(
              menuUnderNote,
              key: const Key('fat-loss-menu-under'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            fatLossApproxNote,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Günlük harcama girişi; denetleyicinin sahibi bu durum nesnesidir, böylece
/// diyalog kapanış animasyonu sırasında da denetleyici geçerli kalır.
class ExpenditureDialog extends StatefulWidget {
  const ExpenditureDialog({super.key, required this.initial});

  final int initial;

  @override
  State<ExpenditureDialog> createState() => _ExpenditureDialogState();
}

class _ExpenditureDialogState extends State<ExpenditureDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null ||
        value < FatLossRules.expenditureMin ||
        value > FatLossRules.expenditureMax) {
      setState(() => _error = fatLossExpenditureError);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Günlük harcama'),
      content: TextField(
        key: const Key('fat-loss-expenditure-field'),
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(suffixText: 'kcal', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('fat-loss-expenditure-save'),
          onPressed: _submit,
          child: const Text('Kaydet'),
        ),
      ],
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

/// "Bugün": günün öğünleri hedeflere göre; eksikler için besin, fazlalar için
/// telafi önerisi.
class TodayGapCard extends ConsumerWidget {
  const TodayGapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ref.watch(todayMealGapProvider);
    return BentoCard(
      key: const Key('fat-loss-today'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.today_outlined,
            label: 'Bugün',
            color: AppColors.nutrition,
          ),
          const SizedBox(height: 12),
          report.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(todayMealGapProvider),
              child: const Text('Bugünün öğünleri yüklenemedi · Tekrar dene'),
            ),
            data: (r) => r == null
                ? const SizedBox.shrink()
                : _TodayGapBody(report: r, theme: theme),
          ),
        ],
      ),
    );
  }
}

class _TodayGapBody extends StatelessWidget {
  const _TodayGapBody({required this.report, required this.theme});

  final MealGapReport report;
  final ThemeData theme;

  Color _color(GapStatus s) => switch (s) {
        GapStatus.deficit => AppColors.textSecondary,
        GapStatus.excess => AppColors.warning,
        GapStatus.onTarget => AppColors.nutrition,
        GapStatus.unknown => AppColors.textMuted,
      };

  String _value(MacroGap g) => g.eaten == null
      ? 'hedef ${formatTr(g.target)} ${g.metric.unit}'
      : '${formatTr(g.eaten!)} / ${formatTr(g.target)} ${g.metric.unit}';

  String _state(MacroGap g) => switch (g.status) {
        GapStatus.deficit => '${formatTr(-g.diff!)} eksik',
        GapStatus.excess => '${formatTr(g.diff!)} fazla',
        GapStatus.onTarget => g.aboveTarget ? 'hedefin üstünde' : 'tamam',
        GapStatus.unknown => 'veri yok',
      };

  @override
  Widget build(BuildContext context) {
    final body = theme.textTheme.bodyMedium;
    final String? message = report.nothingLogged
        ? 'Henüz öğün girilmedi. Öğün ekledikçe eksik ve fazlalar burada '
            'görünür.'
        : report.allDone
            ? 'Bugünün hedefleri tamam.'
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in report.gaps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(g.metric.label,
                      style: body?.copyWith(color: AppColors.textPrimary)),
                ),
                Expanded(
                  child: Text(_value(g),
                      style: body?.copyWith(color: AppColors.textSecondary)),
                ),
                Text(
                  _state(g),
                  key: Key('fat-loss-gap-${g.metric.name}'),
                  style: body?.copyWith(
                    color: _color(g.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message, style: body?.copyWith(color: AppColors.textSecondary)),
        ],
        for (final a in report.advice) ...[
          const SizedBox(height: 10),
          Text(
            a.headline,
            style: theme.textTheme.titleSmall?.copyWith(
              color: _color(a.status),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(a.detail, style: body?.copyWith(color: AppColors.textPrimary)),
        ],
      ],
    );
  }
}

/// Beslenme günü kartının altındaki kısa satır; dokununca plan açılır.
/// Kilo yoksa görünmez.
class FatLossGapLine extends ConsumerWidget {
  const FatLossGapLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(todayMealGapProvider).valueOrNull;
    if (report == null) return const SizedBox.shrink();
    return InkWell(
      key: const Key('fat-loss-gap-line'),
      borderRadius: BorderRadius.circular(AppRadii.chip),
      onTap: () => FatLossScreen.open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                report.summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}


Color _healthColor(RateHealth h) => switch (h) {
      RateHealth.sustainable => AppColors.accent,
      RateHealth.fast => AppColors.warning,
      RateHealth.aggressive => AppColors.danger,
    };

/// Haftalık hız seçimi ve "Ne kadar sağlıklı?" açıklaması.
class FatLossRateCard extends ConsumerWidget {
  const FatLossRateCard({super.key, required this.state});

  final FatLossPlanState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = state.rateResult;
    final rate = result.rate;
    final kg = state.weight.weightKg;
    final weeklyKg = result.actualKgPerWeek;
    final health = classifyRate(weeklyKg, kg);
    final pct = ratePercentOfBodyWeight(weeklyKg, kg);
    final info = rateInfo(result);
    final macroNote = result.macroNote;
    final body = theme.textTheme.bodyMedium;
    return BentoCard(
      key: const Key('fat-loss-rate-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.speed_outlined,
            label: 'Haftalık hız',
            color: AppColors.fitness,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in FatLossRate.values)
                ChoiceChip(
                  key: Key('fat-loss-rate-${r.name}'),
                  label: Text(r.label),
                  selected: r == rate,
                  onSelected: (_) =>
                      ref.read(fatLossRateProvider.notifier).set(r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Ne kadar sağlıklı?',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 6),
          if (weeklyKg > 0)
            Row(
              children: [
                Container(
                  key: const Key('fat-loss-rate-badge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _healthColor(health).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Text(
                    health.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _healthColor(health),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '≈ ${formatTrDecimal2(weeklyKg)} kg/hafta · vücut '
                    'ağırlığının %${formatTrDecimal2(pct)}',
                    key: const Key('fat-loss-rate-pct'),
                    style: body?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            )
          else
            Text('Bu harcamayla kilo kaybı beklenmez.',
                style: body?.copyWith(color: AppColors.textSecondary)),
          if (rate == FatLossRate.classic) ...[
            const SizedBox(height: 6),
            Text(
              'Klasik: kilonun 26 katı sabit kalori '
              '(${formatTr(state.targets.kcal)} kcal).'
              '${weeklyKg > 0 ? ' Harcamana göre tahmini hız ≈${formatTrDecimal2(weeklyKg)} kg/hafta.' : ''}',
              key: const Key('fat-loss-rate-classic-info'),
              style: body?.copyWith(color: AppColors.textPrimary),
            ),
          ],
          if (result.classicBelowFloor) ...[
            const SizedBox(height: 6),
            Text(
              classicFloorWarning(state.targets.kcal),
              key: const Key('fat-loss-classic-floor'),
              style: body?.copyWith(color: AppColors.warning),
            ),
          ],
          if (result.clampedToFloor) ...[
            const SizedBox(height: 6),
            Text(
              rateFloorNote(weeklyKg),
              key: const Key('fat-loss-rate-floor'),
              style: body?.copyWith(color: AppColors.warning),
            ),
          ],
          if (macroNote != null) ...[
            const SizedBox(height: 6),
            Text(
              macroNote,
              key: const Key('fat-loss-rate-carbs'),
              style: body?.copyWith(color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 8),
          for (final p in info.pros)
            _Bullet(text: p, color: AppColors.accent, sign: '+'),
          for (final c in info.cons)
            _Bullet(text: c, color: AppColors.warning, sign: '−'),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.color, required this.sign});

  final String text;
  final Color color;
  final String sign;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(sign,
                style: body?.copyWith(
                    color: color, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(text,
                style: body?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// "Diyette günlük vitamin/mineral" bilgi kartı.
class SupplementCard extends StatelessWidget {
  const SupplementCard({super.key, required this.state});

  final FatLossPlanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guide = supplementGuide(
      weightKg: state.weight.weightKg,
      sex: state.sex,
      kcal: state.targets.kcal,
    );
    final title = theme.textTheme.titleSmall?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final body =
        theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    Widget item(String key, String head, String text, {bool hot = false}) =>
        Padding(
          key: Key('supplement-$key'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(head,
                  style: hot ? title?.copyWith(color: AppColors.warning) : title),
              const SizedBox(height: 2),
              Text(text, style: body),
            ],
          ),
        );
    return BentoCard(
      key: const Key('supplement-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BentoLabel(
            icon: Icons.medication_outlined,
            label: 'Diyette günlük vitamin/mineral',
            color: AppColors.nutrition,
          ),
          const SizedBox(height: 12),
          item('d3', 'D3 vitamini',
              '1.000–2.000 IU/gün (üst sınır 4.000 IU; kan değeri ölçtürmeden '
              'yüksek doz alma). Yağlı öğünle al.'),
          item('magnesium', 'Magnezyum',
              '${guide.magnesiumText}. Takviye genelde 200–350 mg; takviyeden '
              'günde 350 mg\'ı aşma. Sitrat/bisglisinat, akşam. Böbrek '
              'hastalığında doktora sor.'),
          item('omega3', 'Omega-3 (EPA+DHA)',
              '250–500 mg/gün. Haftada 2 porsiyon yağlı balık yemiyorsan '
              'takviye. Kan sulandırıcı kullanıyorsan doktora sor.'),
          item(
            'multivitamin',
            guide.multivitaminHighlighted
                ? 'Multivitamin · önerilir'
                : 'Multivitamin',
            guide.multivitaminHighlighted
                ? 'Günde 1. Kalorin 1.500 kcal\'nin altında; besin eksikliği '
                    'riskine karşı özellikle önerilir.'
                : 'Günde 1; kalori 1.500 kcal\'nin altına inerse özellikle '
                    'önerilir.',
            hot: guide.multivitaminHighlighted,
          ),
          item('water', 'Su',
              '≈ ${formatTr(guide.waterMl)} ml/gün (kilo × 35 ml, en çok 4.000 ml); '
              'yiyecek ve içecek dahil; kalp/böbrek hastalığında doktora sor.'),
          item('protein', 'Protein',
              'Günlük ${formatTr(state.targets.proteinG)} gramlık hedefi '
              'öğünlere böl; kas kaybını azaltır.'),
          item('fiber', 'Lif',
              'En az 25 g; hedefin: ${formatTr(state.targets.fiberG)} g. Sebze, '
              'baklagil ve tam tahıl.'),
          Text(
            supplementDisclaimer,
            key: const Key('supplement-disclaimer'),
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
