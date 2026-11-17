/// Öğün formundaki şablon çipi: seçilince öğün türü, ad, miktar, kalori ve
/// makrolar dolar. Değerler yaygın porsiyonlar için YAKLAŞIKTIR; elle
/// düzenlenir (paketli besin listesindeki doğrulanmış satırların yerini tutmaz).
class MealTemplate {
  const MealTemplate({
    required this.label,
    required this.mealType,
    required this.foodName,
    required this.quantityText,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  /// Çipte görünen ad.
  final String label;

  /// 'breakfast' | 'lunch' | 'dinner' | 'snack'
  final String mealType;
  final String foodName;
  final String quantityText;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

/// Türkçe, sabit öğün şablonları (sunucuya gitmez).
abstract final class MealTemplates {
  static const List<MealTemplate> all = [
    MealTemplate(
      label: 'Yumurta + ekmek',
      mealType: 'breakfast',
      foodName: 'Yumurta + ekmek',
      quantityText: '2 yumurta, 2 dilim ekmek',
      calories: 316,
      proteinG: 18,
      carbsG: 31,
      fatG: 13,
    ),
    MealTemplate(
      label: 'Yulaf + süt',
      mealType: 'breakfast',
      foodName: 'Yulaf + süt',
      quantityText: '50 g yulaf, 200 ml süt',
      calories: 312,
      proteinG: 13,
      carbsG: 42,
      fatG: 10,
    ),
    MealTemplate(
      label: 'Yoğurt + muz',
      mealType: 'snack',
      foodName: 'Yoğurt + muz',
      quantityText: '200 g yoğurt, 1 muz',
      calories: 227,
      proteinG: 8,
      carbsG: 36,
      fatG: 7,
    ),
    MealTemplate(
      label: 'Tavuk + pilav',
      mealType: 'lunch',
      foodName: 'Izgara tavuk + pilav',
      quantityText: '150 g tavuk, 150 g pilav',
      calories: 443,
      proteinG: 51,
      carbsG: 42,
      fatG: 6,
    ),
    MealTemplate(
      label: 'Fıstık ezmeli ekmek',
      mealType: 'snack',
      foodName: 'Fıstık ezmeli ekmek',
      quantityText: '2 dilim ekmek, 1 yemek kaşığı fıstık ezmesi',
      calories: 254,
      proteinG: 9,
      carbsG: 33,
      fatG: 10,
    ),
    MealTemplate(
      label: 'Protein shake',
      mealType: 'snack',
      foodName: 'Protein shake',
      quantityText: '1 ölçek protein tozu, 250 ml süt',
      calories: 272,
      proteinG: 32,
      carbsG: 15,
      fatG: 10,
    ),
    MealTemplate(
      label: 'Kuruyemiş',
      mealType: 'snack',
      foodName: 'Karışık kuruyemiş',
      quantityText: '30 g',
      calories: 180,
      proteinG: 5,
      carbsG: 6,
      fatG: 16,
    ),
  ];
}
