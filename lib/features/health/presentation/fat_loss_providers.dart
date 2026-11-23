import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/settings_providers.dart';
import '../domain/energy_balance.dart';
import '../domain/fat_loss_plan.dart';
import 'energy_providers.dart' show energyWeightLookbackDays;
import 'health_providers.dart';

export '../domain/fat_loss_plan.dart';

/// Son tartı (son [energyWeightLookbackDays] gün); yoksa `null`. Kilo
/// eklenince ya da silinince [weightSeriesProvider] yenilendiği için plan
/// kendiliğinden güncellenir.
final fatLossWeightProvider = FutureProvider<WeightEntry?>((ref) async {
  final series =
      await ref.watch(weightSeriesProvider(energyWeightLookbackDays).future);
  if (series.isEmpty) return null;
  return series.reduce((a, b) => b.loggedAt.isBefore(a.loggedAt) ? a : b);
});

const String _expenditureKey = 'fat_loss_expenditure_kcal';

/// Profil eksikken kullanıcının girdiği günlük harcama; cihazda saklanır.
final manualExpenditureProvider =
    StateNotifierProvider<ManualExpenditureNotifier, int>(
  (ref) => ManualExpenditureNotifier(),
);

class ManualExpenditureNotifier extends StateNotifier<int> {
  ManualExpenditureNotifier() : super(FatLossRules.defaultExpenditure) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_expenditureKey);
      if (stored != null && mounted) state = stored;
    } on Object {
      // Saklama kullanılamıyorsa varsayılan değerle devam edilir.
    }
  }

  Future<void> set(int kcal) async {
    state = kcal
        .clamp(FatLossRules.expenditureMin, FatLossRules.expenditureMax)
        .toInt();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_expenditureKey, state);
    } on Object {
      // Kalıcı yazılamazsa değer bu oturumda geçerli kalır.
    }
  }
}

/// Günlük harcama ve kaynağı.
typedef FatLossExpenditure = ({int kcal, bool fromProfile});

/// Profil (boy, doğum yılı, cinsiyet, hareket düzeyi) tamsa Mifflin–St Jeor
/// × hareket katsayısı; değilse elle girilen harcama.
FatLossExpenditure fatLossExpenditure(
  Ref ref,
  double weightKg,
) {
  final settings = ref.watch(settingsOrDefaultProvider);
  final sex = Sex.tryParse(settings.sex);
  final height = settings.heightCm;
  final birthYear = settings.birthYear;
  final activity = settings.activityLevel;
  if (sex != null && height != null && birthYear != null && activity != null) {
    final age = DateTime.now().year - birthYear;
    final basal = basalKcal(
      weightKg: weightKg,
      heightCm: height,
      age: age < 0 ? 0 : age,
      sex: sex,
    );
    return (kcal: (basal * activity.factor).round(), fromProfile: true);
  }
  return (kcal: ref.watch(manualExpenditureProvider), fromProfile: false);
}

/// Plan: son tartı + hedefler + harcama. Tartı yoksa `null`.
class FatLossPlanState {
  const FatLossPlanState({
    required this.weight,
    required this.targets,
    required this.expenditure,
  });

  final WeightEntry weight;
  final FatLossTargets targets;
  final FatLossExpenditure expenditure;

  WeeklyLossEstimate get weekly => estimateWeeklyLoss(
        expenditureKcal: expenditure.kcal,
        targetKcal: targets.kcal,
      );
}

final fatLossPlanProvider = FutureProvider<FatLossPlanState?>((ref) async {
  final weight = await ref.watch(fatLossWeightProvider.future);
  if (weight == null) return null;
  return FatLossPlanState(
    weight: weight,
    targets: computeFatLossTargets(weight.weightKg),
    expenditure: fatLossExpenditure(ref, weight.weightKg),
  );
});
