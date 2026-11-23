import '../../settings/domain/user_settings.dart';
import 'energy_balance.dart' show Sex;
import 'fat_loss_plan.dart' show formatTr, formatTrDecimal2;
import 'goal_mode.dart';
import 'targets_engine.dart';

/// Hedef türlerinin karşılaştırması: her hedef için kalori, haftalık ve
/// 12 haftalık tahmini değişim ve hedef kiloya kalan süre. Saf; yalnızca
/// [resolveTargets] sonucunu okur. Sayılar tahmindir.
class GoalProjection {
  const GoalProjection({
    required this.goal,
    required this.targets,
    required this.targetWeightKg,
  });

  final GoalMode goal;
  final ResolvedTargets targets;
  final double targetWeightKg;

  int get kcal => targets.kcal;

  /// Tahmini haftalık değişim (kg; eksi = kayıp).
  double get weeklyKg => targets.weeklyChangeKg;

  /// [GoalRules.projectionWeeks] haftalık değişim (kg).
  double get horizonKg => weeklyKg * GoalRules.projectionWeeks;

  /// Hedef kiloya tahmini hafta; yön uymuyorsa, değişim yoksa ya da zaten
  /// hedefteyse `null`.
  int? get etaWeeks {
    final diff = targetWeightKg - targets.weightKg;
    if (diff.abs() < 0.05 || weeklyKg == 0) return null;
    if (diff.sign != weeklyKg.sign) return null;
    return (diff / weeklyKg).ceil();
  }

  /// "−0,50 kg/hafta" / "+0,25 kg/hafta" / "≈ sabit".
  String get weeklyText => _kgText(weeklyKg, suffix: ' kg/hafta');

  /// Kartın ana cümlesi: "Bunu yaparsan ~12 haftada −6 kg" ya da
  /// "~12 haftada +3 kg, bir kısmı yağ" ya da "Kilon ~12 haftada sabit kalır".
  String get headline {
    const w = GoalRules.projectionWeeks;
    if (weeklyKg == 0) return 'Kilon ~$w haftada yaklaşık sabit kalır';
    final kg = _kgText(horizonKg, suffix: ' kg', decimals: false);
    if (weeklyKg > 0) return 'Bunu yaparsan ~$w haftada $kg, bir kısmı yağ';
    return 'Bunu yaparsan ~$w haftada $kg';
  }

  /// "Hedef kiloya ~14 haftada"; yoksa `null`.
  String? get etaText {
    final eta = etaWeeks;
    return eta == null ? null : 'Hedef kiloya ~$eta haftada';
  }

  /// Kalori satırı: "2.150 kcal".
  String get kcalText => '${formatTr(kcal)} kcal';

  static String _kgText(double kg,
      {required String suffix, bool decimals = true}) {
    if (kg.abs() < 0.005) return '≈ sabit';
    final sign = kg < 0 ? '−' : '+';
    final value = decimals ? formatTrDecimal2(kg.abs()) : _oneDecimal(kg.abs());
    return '$sign$value$suffix';
  }

  /// 6 → "6", 2,4 → "2,4".
  static String _oneDecimal(double v) {
    final rounded = (v * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1).replaceAll('.', ',');
  }
}

/// Her hedef türü için bugünkü ayar ve kiloyla projeksiyon (sıra
/// [GoalMode.values]).
List<GoalProjection> projectGoals({
  required UserSettings settings,
  double? latestWeightKg,
  int? age,
  Sex? sex,
}) =>
    [
      for (final g in GoalMode.values)
        GoalProjection(
          goal: g,
          targetWeightKg: settings.targetWeightKg,
          targets: resolveTargets(
            settings: settings.copyWith(goalMode: g),
            latestWeightKg: latestWeightKg,
            age: age,
            sex: sex,
          ),
        ),
    ];
