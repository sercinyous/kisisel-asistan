import 'dart:math' as math;

/// Bazal hesabındaki cinsiyet katsayısı için kullanılan seçenekler. Adlar
/// `user_settings.sex` sütunundaki değerlerle birebir aynıdır
/// (`'female' | 'male' | 'unspecified'`).
enum Sex {
  female,
  male,
  unspecified;

  /// Veritabanı değerini çözer; `null` ve tanınmayan değer `null` döner
  /// ("henüz cevaplanmadı").
  static Sex? tryParse(String? value) {
    if (value == null) return null;
    for (final sex in Sex.values) {
      if (sex.name == value) return sex;
    }
    return null;
  }
}

/// Enerji dengesi yorumunun durumu. Metinler sunum katmanındadır.
enum EnergyVerdict {
  /// Net <= -1000: çok yüksek açık (uyarı, övgü değil).
  veryHighDeficit,

  /// -1000 < net <= -150: yağ yakılıyor.
  burning,

  /// -150 < net < +150: yerinde sayıldı.
  steady,

  /// +150 <= net < +500: biraz fazla, telafi edilebilir.
  slightOver,

  /// Net >= +500: fazla gün.
  over,

  /// O gün hiç öğün kaydı yok: yorum yok.
  noMeals,

  /// 18 yaşından küçük: yorum ve açık hedefi yok, yalnızca sayılar.
  underAge,
}

/// Enerji dengesinin tüm sabitleri tek yerde (bantlar, yağ eşdeğeri,
/// yürüyüş MET'i). Bantların uçları yön belirtir: açık ucun (`<=`) hangi
/// bantta olduğu [verdictFor] ve testlerle sabittir.
abstract final class EnergyBands {
  /// Net bu değere eşit ya da altındaysa [EnergyVerdict.veryHighDeficit].
  static const double veryHighDeficitMax = -1000;

  /// Net bu değere eşit ya da altındaysa (ve çok yüksek açık değilse)
  /// [EnergyVerdict.burning].
  static const double burningMax = -150;

  /// Net bu değerden küçükse (ve [burningMax]'tan büyükse)
  /// [EnergyVerdict.steady]; eşit ya da üstü [EnergyVerdict.slightOver].
  static const double steadyBelow = 150;

  /// Net bu değerden küçükse [EnergyVerdict.slightOver]; eşit ya da üstü
  /// [EnergyVerdict.over].
  static const double slightOverBelow = 500;

  /// Bir kg vücut yağının yaklaşık enerji eşdeğeri (kcal).
  static const double kcalPerKgFat = 7700;

  /// Bu yaşın altında yorum üretilmez.
  static const int adultAge = 18;

  /// Tempolu yürüyüşün MET değeri (telafi dakikası için).
  static const double walkingMet = 3.5;

  /// Net'e göre yorum bandı. Öğün bilgisi ve yaş burada değil, günü
  /// hesaplayan [computeEnergyDay] içinde değerlendirilir.
  static EnergyVerdict verdictFor(double net) {
    if (net <= veryHighDeficitMax) return EnergyVerdict.veryHighDeficit;
    if (net <= burningMax) return EnergyVerdict.burning;
    if (net < steadyBelow) return EnergyVerdict.steady;
    if (net < slightOverBelow) return EnergyVerdict.slightOver;
    return EnergyVerdict.over;
  }

  /// Dakikada yürüyüşle yakılan yaklaşık kcal: MET x 3,5 x kg / 200.
  static double walkingKcalPerMinute(double weightKg) =>
      walkingMet * 3.5 * weightKg / 200;
}

/// Mifflin-St Jeor bazal enerji (kcal/gün): 10·kg + 6,25·cm − 5·yaş + k;
/// k: erkek +5, kadın −161, belirtmeyen −78. Sonuç 0'ın altına inmez.
///
/// Geçersiz (sıfır, negatif ya da sonlu olmayan) kilo ya da boy
/// [ArgumentError] fırlatır: sessizce yanlış sayı üretmek yerine hata
/// sağlayıcıya ulaşır.
double basalKcal({
  required double weightKg,
  required int heightCm,
  required int age,
  required Sex sex,
}) {
  if (!weightKg.isFinite || weightKg <= 0) {
    throw ArgumentError.value(weightKg, 'weightKg', 'must be positive');
  }
  if (heightCm <= 0) {
    throw ArgumentError.value(heightCm, 'heightCm', 'must be positive');
  }
  final offset = switch (sex) {
    Sex.male => 5.0,
    Sex.female => -161.0,
    Sex.unspecified => -78.0,
  };
  final value = 10 * weightKg + 6.25 * heightCm - 5 * age + offset;
  return math.max(0.0, value);
}

/// Tek bir günün enerji dengesi. Saf değer sınıfı; ekrandan bağımsız.
class EnergyDay {
  const EnergyDay({
    required this.day,
    required this.intake,
    required this.basal,
    required this.active,
    required this.activeDataMissing,
    required this.net,
    required this.verdict,
    required this.isToday,
    required this.walkingMinutesToCompensate,
    required this.tomorrowCutKcal,
  });

  /// Yalnızca tarih (saat 00:00, yerel).
  final DateTime day;

  /// Alınan kcal; o gün öğün kaydı yoksa `null`.
  final double? intake;

  /// Bazal yakım. Bugün için günün geçen oranıyla ölçeklenmiştir.
  final double basal;

  /// Aktif kalori: sağlık kaynağından gelen değer, yoksa/0 ise antrenman
  /// kayıtlarının kalorisi, o da yoksa 0.
  final double active;

  /// Sağlık kaynağından pozitif aktif kalori gelmedi; yakılan tahmini
  /// bazala (ve varsa antrenman kayıtlarına) dayanıyor.
  final bool activeDataMissing;

  /// Alınan − yakılan; öğün yoksa `null`.
  final double? net;

  final EnergyVerdict verdict;

  /// Gün, hesaplamanın yapıldığı "şimdi"nin takvim günü.
  final bool isToday;

  /// Yalnızca [EnergyVerdict.slightOver]: fazlayı yürüyüşle yakmak için
  /// gereken dakika (yukarı yuvarlanır).
  final int? walkingMinutesToCompensate;

  /// Yalnızca [EnergyVerdict.slightOver]: ertesi gün bu kadar az yemek
  /// fazlayı dengeler (kcal).
  final double? tomorrowCutKcal;

  /// Yakılan toplam kcal (bazal + aktif).
  double get burned => basal + active;

  @override
  bool operator ==(Object other) =>
      other is EnergyDay &&
      other.day == day &&
      other.intake == intake &&
      other.basal == basal &&
      other.active == active &&
      other.activeDataMissing == activeDataMissing &&
      other.net == net &&
      other.verdict == verdict &&
      other.isToday == isToday &&
      other.walkingMinutesToCompensate == walkingMinutesToCompensate &&
      other.tomorrowCutKcal == tomorrowCutKcal;

  @override
  int get hashCode => Object.hash(
        day,
        intake,
        basal,
        active,
        activeDataMissing,
        net,
        verdict,
        isToday,
        walkingMinutesToCompensate,
        tomorrowCutKcal,
      );

  @override
  String toString() =>
      'EnergyDay($day, intake: $intake, basal: $basal, active: $active, '
      'net: $net, ${verdict.name})';
}

/// Bir gün için alınan/yakılan/net ve yorumu hesaplar.
///
/// - Yaş = `day.year - birthYear` (yalnızca doğum yılı bilinir).
/// - Bugün ([day] ile [now]'ın takvim günü aynıysa) bazal, günün geçen
///   oranıyla çarpılır ("şu ana kadar"); geçmiş günde tam gün bazal alınır.
///   [now] dışarıdan verilir: gece yarısını geçince bugün/dün ve bazal oranı
///   çağıran tarafın [now]'ıyla doğru yeniden hesaplanır.
/// - Aktif kalori: [activeKcalFromMetrics] pozitifse yalnızca o (antrenman
///   zaten içindedir, çift sayım yok); `null` ya da 0 ise [workoutKcal]
///   yedek olur ve [EnergyDay.activeDataMissing] true olur.
/// - O gün [mealEntryCount] 0 ise yorum yok ([EnergyVerdict.noMeals]),
///   [EnergyDay.intake] ve [EnergyDay.net] `null`. Aksi hâlde 18 yaş altı
///   [EnergyVerdict.underAge] (sayılar dolu, telafi yok), diğerleri net'e
///   göre bant alır.
/// - Negatif ya da sonlu olmayan [intakeKcal] 0 sayılır.
EnergyDay computeEnergyDay({
  required DateTime day,
  required DateTime now,
  required double weightKg,
  required int heightCm,
  required int birthYear,
  required Sex sex,
  required int mealEntryCount,
  required double intakeKcal,
  int? activeKcalFromMetrics,
  int workoutKcal = 0,
}) {
  final dayOnly = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final isToday = dayOnly == today;

  final age = dayOnly.year - birthYear;
  final fullBasal = basalKcal(
    weightKg: weightKg,
    heightCm: heightCm,
    age: math.max(0, age),
    sex: sex,
  );
  final basal = isToday ? fullBasal * _elapsedDayFraction(now) : fullBasal;

  final metrics = activeKcalFromMetrics;
  final hasMetrics = metrics != null && metrics > 0;
  final fallback = workoutKcal > 0 ? workoutKcal : 0;
  final active = (hasMetrics ? metrics : fallback).toDouble();

  final hasMeals = mealEntryCount > 0;
  final double? intake = hasMeals
      ? (intakeKcal.isFinite && intakeKcal > 0 ? intakeKcal : 0.0)
      : null;
  final double? net = intake == null ? null : intake - (basal + active);

  final EnergyVerdict verdict;
  if (net == null) {
    verdict = EnergyVerdict.noMeals;
  } else if (age < EnergyBands.adultAge) {
    verdict = EnergyVerdict.underAge;
  } else {
    verdict = EnergyBands.verdictFor(net);
  }

  int? walkingMinutes;
  double? tomorrowCut;
  if (verdict == EnergyVerdict.slightOver && net != null) {
    final perMinute = EnergyBands.walkingKcalPerMinute(weightKg);
    // Kayan nokta artığı tam bölünen dakikayı bir yukarı atmasın.
    walkingMinutes = (net / perMinute - 1e-9).ceil();
    tomorrowCut = net;
  }

  return EnergyDay(
    day: dayOnly,
    intake: intake,
    basal: basal,
    active: active,
    activeDataMissing: !hasMetrics,
    net: net,
    verdict: verdict,
    isToday: isToday,
    walkingMinutesToCompensate: walkingMinutes,
    tomorrowCutKcal: tomorrowCut,
  );
}

/// Günün geçen oranı (0..1), saat duvar saatine göre.
double _elapsedDayFraction(DateTime now) {
  final seconds = now.hour * 3600 + now.minute * 60 + now.second;
  return (seconds / 86400).clamp(0.0, 1.0);
}

/// Bir aralığın enerji özeti: yalnızca yorum üretilebilen (net'i olan,
/// yani öğünü olan) günler sayılır; 7 güne ölçeklenmez.
class EnergyRangeSummary {
  const EnergyRangeSummary({
    required this.days,
    required this.sumNet,
    required this.estimatedFatKg,
  });

  /// Net'i olan gün sayısı ("N gün üzerinden").
  final int days;

  /// Bu günlerin net toplamı (kcal).
  final double sumNet;

  /// Tahmini yağ değişimi (kg) = [sumNet] / 7700; negatif = azalma.
  final double estimatedFatKg;

  @override
  bool operator ==(Object other) =>
      other is EnergyRangeSummary &&
      other.days == days &&
      other.sumNet == sumNet &&
      other.estimatedFatKg == estimatedFatKg;

  @override
  int get hashCode => Object.hash(days, sumNet, estimatedFatKg);

  @override
  String toString() =>
      'EnergyRangeSummary($days gün, net: $sumNet, yağ: $estimatedFatKg kg)';
}

EnergyRangeSummary summarize(Iterable<EnergyDay> days) {
  var count = 0;
  var sum = 0.0;
  for (final day in days) {
    final net = day.net;
    if (net == null) continue;
    count++;
    sum += net;
  }
  return EnergyRangeSummary(
    days: count,
    sumNet: sum,
    estimatedFatKg: sum / EnergyBands.kcalPerKgFat,
  );
}

/// Harcamanın kaynağı.
enum ExpenditureSource {
  /// Kullanıcının elle girdiği değer (`expenditure_kcal_manual`).
  manual,

  /// Bazal (Mifflin) + sağlık kaynağından gelen aktif kalori.
  health,

  /// Model: bazal × hareket katsayısı ya da bazal × 1,2 + adım × 0,04.
  estimate,

  /// Profil eksik: varsayılan harcama.
  fallback,
}

/// Bir harcama değeri ve kaynağı.
class Expenditure {
  const Expenditure(this.kcal, this.source);

  final int kcal;
  final ExpenditureSource source;

  @override
  bool operator ==(Object other) =>
      other is Expenditure && other.kcal == kcal && other.source == source;

  @override
  int get hashCode => Object.hash(kcal, source);

  @override
  String toString() => 'Expenditure($kcal, ${source.name})';
}

/// Tek harcama modelinin sabitleri.
abstract final class ExpenditureModel {
  /// Hareket bilgisi yokken bazal katsayısı.
  static const double baseFactor = 1.2;

  /// Adım başına kcal.
  static const double kcalPerStep = 0.04;

  /// Profil eksikse planın kullandığı günlük harcama.
  static const int fallbackKcal = 3000;
  static const int minKcal = 1200;
  static const int maxKcal = 6000;
}

/// Planın (tipik bir günün) harcaması. Sıra: elle girilen; bazal × hareket
/// katsayısı; bazal × 1,2 + hedef adım × 0,04; profil yoksa 3.000.
/// Sonuç 1.200–6.000 aralığına sıkıştırılır.
Expenditure planExpenditure({
  int? manualKcal,
  double? basal,
  double? activityFactor,
  int stepsTarget = 0,
}) {
  int clamp(num v) => v
      .round()
      .clamp(ExpenditureModel.minKcal, ExpenditureModel.maxKcal)
      .toInt();
  if (manualKcal != null) {
    return Expenditure(clamp(manualKcal), ExpenditureSource.manual);
  }
  if (basal != null && basal.isFinite && basal > 0) {
    final kcal = activityFactor != null
        ? basal * activityFactor
        : basal * ExpenditureModel.baseFactor +
            math.max(0, stepsTarget) * ExpenditureModel.kcalPerStep;
    return Expenditure(clamp(kcal), ExpenditureSource.estimate);
  }
  return const Expenditure(
      ExpenditureModel.fallbackKcal, ExpenditureSource.fallback);
}

/// Bir günün gerçek harcaması (gün dengesi, haftalık açık ve seriler aynı
/// modeli kullanır). Sıra: elle girilen; bazal + sağlık kaynağının aktif
/// kalorisi; bazal × 1,2 + adım × 0,04. Bugün için bazal (ve elle girilen
/// değer) günün geçen oranıyla ölçeklenir ("şu ana kadar"). Bazal da elle
/// değer de yoksa `null`.
Expenditure? dayExpenditure({
  required DateTime day,
  required DateTime now,
  int? manualKcal,
  double? basal,
  int? activeKcal,
  int steps = 0,
}) {
  final dayOnly = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final fraction = dayOnly == today ? _elapsedDayFraction(now) : 1.0;
  if (manualKcal != null && manualKcal > 0) {
    return Expenditure(
        (manualKcal * fraction).round(), ExpenditureSource.manual);
  }
  if (basal == null || !basal.isFinite || basal <= 0) return null;
  if (activeKcal != null && activeKcal > 0) {
    return Expenditure(
        (basal * fraction + activeKcal).round(), ExpenditureSource.health);
  }
  return Expenditure(
    (basal * ExpenditureModel.baseFactor * fraction +
            math.max(0, steps) * ExpenditureModel.kcalPerStep)
        .round(),
    ExpenditureSource.estimate,
  );
}
