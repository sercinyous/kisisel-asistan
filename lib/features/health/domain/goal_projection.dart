import '../../settings/domain/user_settings.dart';
import 'energy_balance.dart' show Sex;
import 'fat_loss_plan.dart' show formatTr, formatTrDecimal2;
import 'fat_loss_rate.dart' show RateHealth;
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

  /// Bu değerin altındaki haftalık değişim (kg) "≈ sabit" sayılır; haftalık
  /// metin, ana cümle ve hedef süresi aynı eşiği kullanır.
  static const double stableKgPerWeek = 0.05;

  /// Hedef kiloya tahmini süre bu kadar haftayı aşarsa sayı gösterilmez.
  static const int maxEtaWeeks = 104;

  /// Haftalık değişim "≈ sabit" eşiğinin altında.
  bool get isStable => weeklyKg.abs() < stableKgPerWeek;

  /// Kayıp hızı vücut ağırlığına göre hızlı ya da agresif (ör. klasik
  /// formül yüksek harcamada): kartta uyarı gösterilir.
  bool get fastLoss {
    final h = targets.health;
    return weeklyKg < 0 && h != null && h != RateHealth.sustainable;
  }

  /// Hızlı kayıp uyarısı; yoksa `null`.
  String? get fastLossText => fastLoss
      ? '${targets.health!.label} kayıp: bu hız uzun süre sürdürülemez; '
          'daha yavaş bir hız seç'
      : null;

  int get kcal => targets.kcal;

  /// Tahmini haftalık değişim (kg; eksi = kayıp).
  double get weeklyKg => targets.weeklyChangeKg;

  /// [GoalRules.projectionWeeks] haftalık değişim (kg).
  double get horizonKg => weeklyKg * GoalRules.projectionWeeks;

  /// Hedef kiloya tahmini hafta; yön uymuyorsa, değişim yoksa ya da zaten
  /// hedefteyse `null`.
  int? get etaWeeks {
    final diff = targetWeightKg - targets.weightKg;
    if (diff.abs() < 0.05 || isStable) return null;
    if (diff.sign != weeklyKg.sign) return null;
    return (diff / weeklyKg).ceil();
  }

  /// "−0,50 kg/hafta" / "+0,25 kg/hafta" / "≈ sabit".
  String get weeklyText =>
      isStable ? '≈ sabit' : _kgText(weeklyKg, suffix: ' kg/hafta');

  /// Kartın ana cümlesi: "Bunu yaparsan ~12 haftada −6 kg" ya da
  /// "~12 haftada +3 kg, bir kısmı yağ" ya da "Kilon ~12 haftada sabit kalır".
  String get headline {
    const w = GoalRules.projectionWeeks;
    if (isStable) return 'Kilon ~$w haftada yaklaşık sabit kalır';
    final kg = _kgText(horizonKg, suffix: ' kg', decimals: false);
    if (weeklyKg > 0) return 'Bunu yaparsan ~$w haftada $kg, bir kısmı yağ';
    return 'Bunu yaparsan ~$w haftada $kg';
  }

  /// "Hedef kiloya ~14 haftada"; [maxEtaWeeks] üstünde "Hedef kiloya bu
  /// hızla 2 yıldan uzun"; yoksa `null`.
  String? get etaText {
    final eta = etaWeeks;
    if (eta == null) return null;
    if (eta > maxEtaWeeks) return 'Hedef kiloya bu hızla 2 yıldan uzun';
    return 'Hedef kiloya ~$eta haftada';
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
