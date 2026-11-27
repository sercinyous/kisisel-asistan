import '../../../core/templates/meal_templates.dart';

/// Hazır diyet paketleri (Sağlık > Plan). Paket sabit bir kalori ve makro
/// hedefidir; hedefleri yalnızca hedef motoru yazar ([presetWrite]). Menü
/// değerleri yaklaşıktır; bilgilendirme amaçlıdır, tıbbi tavsiye değildir.
enum DietPreset {
  highProtein1800(
    id: 'kcal_1800_high_protein',
    label: '1800 kcal · Yüksek protein',
    kcal: 1800,
    proteinG: 150,
    fatG: 60,
    carbsG: 165,
    fiberG: 30,
    meals: MealTemplates.highProtein1800,
  );

  const DietPreset({
    required this.id,
    required this.label,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.fiberG,
    required this.meals,
  });

  final String id;
  final String label;
  final int kcal;
  final int proteinG;
  final int fatG;
  final int carbsG;
  final int fiberG;

  /// Günün öğünleri (kahvaltı, öğle, akşam, ara öğün); öğün formunda şablon
  /// çipi olarak da görünür.
  final List<MealTemplate> meals;

  /// P×4 + Y×9 + K×4 (kcal).
  int get macroKcal => proteinG * 4 + fatG * 9 + carbsG * 4;

  /// Menünün toplam kalorisi.
  double get menuKcal => meals.fold(0, (sum, m) => sum + m.calories);

  /// Menünün toplam proteini (g).
  double get menuProteinG => meals.fold(0, (sum, m) => sum + m.proteinG);
}
