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
  /// "1800 kcal · Yüksek protein" paketinin günlük menüsü: toplam 1.800 kcal,
  /// 150 g protein, 165 g karbonhidrat, 60 g yağ (yaklaşık).
  static const List<MealTemplate> highProtein1800 = [
    MealTemplate(
      label: '1800 · Kahvaltı',
      mealType: 'breakfast',
      foodName: 'Yumurta + lor + tam buğday ekmek',
      quantityText: '3 yumurta, 80 g lor peyniri, 1 dilim ekmek, domates',
      calories: 420,
      proteinG: 35,
      carbsG: 25,
      fatG: 20,
    ),
    MealTemplate(
      label: '1800 · Öğle',
      mealType: 'lunch',
      foodName: 'Izgara tavuk + bulgur pilavı + salata',
      quantityText: '180 g tavuk göğsü, 150 g bulgur pilavı, salata',
      calories: 548,
      proteinG: 50,
      carbsG: 60,
      fatG: 12,
    ),
    MealTemplate(
      label: '1800 · Akşam',
      mealType: 'dinner',
      foodName: 'Fırın levrek + patates + cacık',
      quantityText: '200 g levrek, 200 g haşlanmış patates, 150 g cacık',
      calories: 502,
      proteinG: 40,
      carbsG: 45,
      fatG: 18,
    ),
    MealTemplate(
      label: '1800 · Ara öğün',
      mealType: 'snack',
      foodName: 'Süzme yoğurt + yulaf + muz',
      quantityText: '200 g süzme yoğurt, 30 g yulaf, 1 küçük muz',
      calories: 330,
      proteinG: 25,
      carbsG: 35,
      fatG: 10,
    ),
  ];

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
    ...highProtein1800,
  ];
}
