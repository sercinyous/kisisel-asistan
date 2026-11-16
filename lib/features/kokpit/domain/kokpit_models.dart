/// Bugünün makro toplamları.
class NutritionSummary {
  const NutritionSummary({
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.entryCount = 0,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final int entryCount;

  factory NutritionSummary.fromRows(List<Map<String, dynamic>> rows) {
    double sum(String key) => rows.fold<double>(
          0,
          (total, row) => total + ((row[key] as num?)?.toDouble() ?? 0),
        );
    return NutritionSummary(
      calories: sum('calories'),
      proteinG: sum('protein_g'),
      carbsG: sum('carbs_g'),
      fatG: sum('fat_g'),
      entryCount: rows.length,
    );
  }
}
