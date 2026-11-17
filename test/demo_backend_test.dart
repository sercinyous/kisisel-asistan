import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/utils/date_utils.dart';
import 'package:kisisel_asistan/demo/demo_backend.dart';
import 'package:kisisel_asistan/demo/demo_data.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/health/data/health_repository.dart';
import 'package:kisisel_asistan/features/kokpit/domain/kokpit_models.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

void main() {
  final day = DateTime(2026, 11, 16);

  group('FakeHealthRepository', () {
    late FakeHealthRepository health;
    setUp(() => health = FakeHealthRepository());

    NutritionLog meal(String name, DateTime at, {double calories = 100, double protein = 10}) =>
        NutritionLog(id: '', foodName: name, calories: calories, proteinG: protein, eatenAt: at);

    test('öğün: ekle → oku → güncelle → sil', () async {
      final created = await health.createNutritionLog(
        meal('Yulaf', day.add(const Duration(hours: 8))),
      );
      expect(created.id, isNotEmpty);
      expect((await health.fetchNutritionLogs(day)).single.foodName, 'Yulaf');

      await health.updateNutritionLog(created.copyWith(foodName: 'Yulaf ezmesi'));
      expect((await health.fetchNutritionLogs(day)).single.foodName, 'Yulaf ezmesi');

      await health.deleteNutritionLog(created.id);
      expect(await health.fetchNutritionLogs(day), isEmpty);
      expect(health.deletedIds, [created.id]);
    });

    test('gün toplamı: hazır toplamlara öğün kayıtları eklenir', () async {
      health.nutrition = [
        DailyNutritionTotal(
          day: DateTime(2026, 11, 15),
          calories: 1900,
          proteinG: 150,
          entryCount: 4,
        ),
      ];
      await health.createNutritionLog(
          meal('a', day.add(const Duration(hours: 8)), calories: 400, protein: 30));
      await health.createNutritionLog(
          meal('b', day.add(const Duration(hours: 13)), calories: 600, protein: 50));
      final totals = await health.fetchNutritionTotals(
        DateTime(2026, 11, 1),
        DateTime(2026, 12, 1),
      );
      expect(totals.map((t) => t.day), [DateTime(2026, 11, 15), day]);
      expect(totals.last.calories, 1000);
      expect(totals.last.proteinG, 80);
      expect(totals.last.entryCount, 2);
      expect(totals.first.calories, 1900);
    });

    test('antrenman: ekle → güncelle → sil; liste yeniden eskiye', () async {
      final first = await health.createWorkout(
        WorkoutLog(id: '', workoutType: 'running', loggedAt: day.add(const Duration(hours: 7))),
      );
      final second = await health.createWorkout(
        WorkoutLog(id: '', workoutType: 'weights', loggedAt: day.add(const Duration(hours: 19))),
      );
      expect(first.id, isNot(second.id));
      var list = await health.fetchWorkouts(day, AppDates.endOfDay(day));
      expect(list.map((w) => w.workoutType), ['weights', 'running']);

      await health.updateWorkout(first.copyWith(durationMin: 40));
      list = await health.fetchWorkouts(day, AppDates.endOfDay(day));
      expect(list.last.durationMin, 40);

      await health.deleteWorkout(second.id);
      expect(await health.fetchWorkouts(day, AppDates.endOfDay(day)), hasLength(1));
    });

    test('antrenman: aynı oturumun Google kopyası kullanıcı kaydı eklenince silinir',
        () async {
      await health.importExternalWorkouts([
        ExternalWorkout(
          source: 'google',
          externalId: 'kick-1',
          workout: WorkoutLog(
            id: '',
            workoutType: 'kickboxing',
            loggedAt: day.add(const Duration(hours: 19, minutes: 2)),
            durationMin: 59,
          ),
        ),
        ExternalWorkout(
          source: 'google',
          externalId: 'run-1',
          workout: WorkoutLog(
            id: '',
            workoutType: 'running',
            loggedAt: day.add(const Duration(hours: 7)),
            durationMin: 40,
          ),
        ),
      ]);
      expect(health.workouts, hasLength(2));

      final created = await health.createWorkout(
        WorkoutLog(
          id: '',
          workoutType: 'kickboxing',
          loggedAt: day.add(const Duration(hours: 20, minutes: 10)),
          durationMin: 60,
        ),
      );

      expect(health.workouts.map((w) => w.workoutType).toSet(),
          {'kickboxing', 'running'});
      expect(health.workouts.where((w) => w.isFromGoogle).single.workoutType,
          'running');
      expect(health.workouts.any((w) => w.id == created.id), isTrue);
      expect(health.externalWorkoutIds.keys, [('google', 'run-1')]);
    });

    test('kilo: ekle ve sil', () async {
      final entry = await health.addWeight(83.4, at: day.add(const Duration(hours: 8)));
      expect(entry.weightKg, 83.4);
      expect(await health.fetchWeights(day, AppDates.endOfDay(day)), hasLength(1));
      await health.deleteWeight(entry.id);
      expect(await health.fetchWeights(day, AppDates.endOfDay(day)), isEmpty);
    });

    test('writeError yazmaları durdurur ve durum değişmez', () async {
      health.writeError = Exception('yazılamadı');
      final at = day.add(const Duration(hours: 8));
      await expectLater(health.createNutritionLog(meal('x', at)), throwsException);
      await expectLater(
        health.createWorkout(WorkoutLog(id: '', loggedAt: at)),
        throwsException,
      );
      await expectLater(health.addWeight(80), throwsException);
      expect(health.nutritionLogs, isEmpty);
      expect(health.workouts, isEmpty);
      expect(health.weights, isEmpty);
    });
  });

  // Gerçek veritabanında aynı işi routines_frequency_changed tetikleyicisi
  // yapar (supabase/tests/reports_test.sql). Dönem anahtarı günlükte "o gün",
  // aylıkta "ayın 1'i" olduğu için eski işaret yeni sıklıkta yanlış okunur.
  group('FakeRoutinesRepository: sıklık değişince işaretler sıfırlanır', () {
    final first = DateTime(2026, 11);
    const daily = Routine(id: 'r1', title: 'Fatura kontrolü');
    const other = Routine(id: 'r2', title: 'Dokunulmayan');

    FakeRoutinesRepository seeded(Routine edited) => FakeRoutinesRepository(
          routines: [edited, other],
          completions: [
            RoutineCompletionKey('r1', first),
            RoutineCompletionKey('r2', first),
          ],
        );

    test('günlük → aylık: ayın 1\'indeki günlük işaret dönemi yapılmış göstermez',
        () async {
      final repo = seeded(daily);
      await repo.update(
        daily.copyWith(frequency: RoutineFrequency.monthly, dayOfMonth: 20),
      );

      expect(repo.completions, {RoutineCompletionKey('r2', first)});
      final month = monthlyForMonth(
        await repo.fetchActive(),
        await repo.fetchCompletions(first, DateTime(2026, 11, 30)),
        2026,
        11,
        DateTime(2026, 11, 10),
      );
      expect(month.single.routine.id, 'r1');
      expect(month.single.completed, isFalse);
      expect(month.single.status, OccurrenceStatus.upcoming);
    });

    test('aylık → günlük: aylık işaret ayın 1\'ini yapılmış göstermez',
        () async {
      final monthly = daily.copyWith(
        frequency: RoutineFrequency.monthly,
        dayOfMonth: 20,
      );
      final repo = seeded(monthly);
      await repo.update(
        monthly.copyWith(frequency: RoutineFrequency.weekly),
      );

      final day = occurrencesForDay(
        await repo.fetchActive(),
        await repo.fetchCompletions(first, first),
        first,
      );
      expect(
        {for (final o in day) o.routine.id: o.completed},
        {'r1': false, 'r2': true},
      );
    });

    test('sıklık aynı kalan düzenleme işaretleri korur', () async {
      final repo = seeded(daily);
      await repo.update(daily.copyWith(title: 'Fatura', daysOfWeek: [1, 3]));

      expect(repo.completions, hasLength(2));
      expect(repo.routines.first.title, 'Fatura');
    });
  });

  group('FakeKokpitRepository', () {
    test('sağlık deposuna bağlıyken özet öğün kayıtlarından hesaplanır', () async {
      final health = FakeHealthRepository(nutritionLogs: [
        NutritionLog(
          id: 'a',
          foodName: 'a',
          calories: 400,
          proteinG: 30,
          carbsG: 40,
          fatG: 10,
          eatenAt: day.add(const Duration(hours: 8)),
        ),
        NutritionLog(
          id: 'dün',
          foodName: 'dün',
          calories: 999,
          eatenAt: day.subtract(const Duration(hours: 1)),
        ),
      ]);
      final kokpit = FakeKokpitRepository(health: health);
      final summary = await kokpit.fetchNutritionFor(day);
      expect(summary.calories, 400);
      expect(summary.proteinG, 30);
      expect(summary.carbsG, 40);
      expect(summary.fatG, 10);
      expect(summary.entryCount, 1);
    });

    test('bağlı değilken sabit özeti döner', () async {
      final kokpit = FakeKokpitRepository(
        nutrition: const NutritionSummary(calories: 1450, entryCount: 5),
      );
      expect((await kokpit.fetchNutritionFor(day)).calories, 1450);
    });
  });

  group('FakeReportsRepository', () {
    final monday = DateTime(2026, 11, 9);

    test('regenerate: üretici verilmişse raporu yazar (aynı haftayı değiştirir)', () async {
      var rate = 40;
      final reports = FakeReportsRepository(
        weeklyBuilder: (weekStart) => WeeklyReport(
          weekStart: weekStart,
          metrics: ReportMetrics(workRate: rate),
        ),
      );
      await reports.regenerate(kind: ReportKind.weekly, date: DateTime(2026, 11, 12));
      rate = 80;
      await reports.regenerate(kind: ReportKind.weekly, date: monday);
      expect(reports.weekly, hasLength(1));
      expect((await reports.fetchWeekly(monday))!.metrics.workRate, 80);
      expect(reports.regenerated, [
        (kind: ReportKind.weekly, date: monday),
        (kind: ReportKind.weekly, date: monday),
      ]);
    });

    test('regenerateDelay: rapor ancak süre dolunca yazılır', () async {
      final day = DateTime(2026, 11, 12);
      final reports = FakeReportsRepository(
        dailyBuilder: (d) => demoDailyReport(d, DateTime(2026, 11, 13)),
        regenerateDelay: const Duration(milliseconds: 60),
      );
      final pending = reports.regenerate(kind: ReportKind.daily, date: day);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await reports.fetchDaily(day), isNull);
      await pending;
      expect(await reports.fetchDaily(day), isNotNull);
    });

    test('FakeNotificationService: durumu okumak izin istemek sayılmaz', () async {
      final service = FakeNotificationService(permissionGranted: false);
      expect(await service.hasPermission(), isFalse);
      expect(service.permissionRequests, 0);
      expect(await service.requestPermission(), isFalse);
      expect(service.permissionRequests, 1);
    });

    test('regenerateError: hata verir, rapor değişmez', () async {
      final reports = FakeReportsRepository(
        dailyBuilder: (d) => DailyReport(reportDate: d, metrics: ReportMetrics.empty),
      )..regenerateError = const ReportGenerationException('olmadı');
      await expectLater(
        reports.regenerate(kind: ReportKind.daily, date: day),
        throwsA(isA<ReportGenerationException>()),
      );
      expect(reports.daily, isEmpty);
      expect(await reports.fetchDaily(day), isNull);
    });

    test('fetchWeeklyList limit uygular', () async {
      final reports = FakeReportsRepository(weekly: [
        for (var i = 0; i < 5; i++)
          WeeklyReport(
            weekStart: AppDates.addDays(monday, -7 * i),
            metrics: ReportMetrics.empty,
          ),
      ]);
      final list = await reports.fetchWeeklyList(limit: 2);
      expect(list.map((r) => r.weekStart), [monday, DateTime(2026, 11, 2)]);
    });
  });

  group('DemoData.seed', () {
    // Çarşamba öğleden sonra: içinde bulunulan hafta kısmi.
    final now = DateTime(2026, 11, 18, 15, 34);
    final today = DateTime(2026, 11, 18);
    late DemoData data;
    setUp(() => data = DemoData.seed(now));

    test('3 haftalık rapor: bu hafta (kısmi) ve önceki iki hafta', () async {
      final list = await data.reports.fetchWeeklyList();
      expect(list.map((r) => r.weekStart), [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 9),
        DateTime(2026, 11, 2),
      ]);
      for (final report in list) {
        expect(report.aiStatus, ReportAiStatus.ok);
        expect(report.aiSummary, isNotEmpty);
        expect(report.metrics.days, hasLength(7));
        expect(report.metrics.workRate, inInclusiveRange(0, 100));
        expect(report.metrics.formRate, inInclusiveRange(0, 100));
        expect(report.metrics.targetCalories, 2000);
        expect(report.metrics.periodStart, report.weekStart);
        expect(report.metrics.periodEnd, report.weekEnd);
      }
      // Bu haftanın gelmemiş günleri boş.
      final current = list.first.metrics.days;
      expect(current.take(3).every((d) => d.workRate != null), isTrue);
      expect(current.skip(3).every((d) => d.workRate == null && d.steps == 0), isTrue);
    });

    test('7 günlük rapor: dünle biten 7 gün; bugününki yok', () async {
      final range = (from: AppDates.addDays(today, -7), to: today);
      final list = await data.reports.fetchDailyList(range.from, range.to);
      expect(list, hasLength(7));
      expect(list.first.reportDate, DateTime(2026, 11, 17));
      expect(list.last.reportDate, DateTime(2026, 11, 11));
      expect(await data.reports.fetchDaily(today), isNull);
      for (final report in list) {
        expect(report.hasSummary, isTrue);
        expect(report.metrics.hasNutrition, isTrue);
        expect(report.metrics.hasHealth, isTrue);
      }
    });

    test('yeniden oluşturma bugünün raporunu üretir', () async {
      await data.reports.regenerate(kind: ReportKind.daily, date: today);
      expect(await data.reports.fetchDaily(today), isNotNull);
    });

    test('bugünün öğünleri kalem kalem; Kokpit özeti aynı kayıtlardan', () async {
      final logs = await data.health.fetchNutritionLogs(today);
      expect(logs.map((l) => l.mealType).toSet(), {'breakfast', 'lunch'});
      final summary = await data.kokpit.fetchNutritionFor(today);
      expect(summary.entryCount, logs.length);
      expect(summary.calories, logs.fold<double>(0, (s, l) => s + l.calories));
      expect(summary.calories, 880);
    });

    test('kilo serisi 90 günü kapsar ve bugünkü ölçümle biter', () async {
      final series = await data.health.fetchWeights(
        AppDates.addDays(today, -90),
        AppDates.endOfDay(today),
      );
      expect(series.length, greaterThan(25));
      expect(series.last.weightKg, 83.6);
      expect(series.first.weightKg, greaterThan(85));
      for (final w in series) {
        expect(w.weightKg, inInclusiveRange(WeightLimits.minKg, WeightLimits.maxKg));
      }
    });

    test('antrenmanlar ve 7 günlük sağlık özeti dolu', () async {
      final workouts = await data.health.fetchWorkouts(
        AppDates.addDays(today, -13),
        AppDates.endOfDay(today),
      );
      expect(workouts, isNotEmpty);
      expect(workouts.every((w) => WorkoutLog.workoutTypes.contains(w.workoutType)), isTrue);
      final metrics =
          await data.health.fetchDailyMetrics(AppDates.addDays(today, -6), today);
      expect(metrics, hasLength(7));
      expect(metrics.every((m) => m.steps > 0), isTrue);
    });

    test('hızlı giriş: öğün ve antrenman Sağlık deposuna yazılır', () async {
      final before = await data.kokpit.fetchNutritionFor(today);
      final entry = ParsedEntry.fromJson({
        'nutrition': [
          {
            'meal_type': 'dinner',
            'food_name': 'Makarna',
            'calories': 300,
            'protein_g': 11,
            'carbs_g': 60,
            'fat_g': 2,
            'eaten_at': today.add(const Duration(hours: 19)).toIso8601String(),
          },
        ],
        'workouts': [
          {
            'workout_type': 'running',
            'title': 'Koşu',
            'duration_min': 30,
            'performed_at': today.add(const Duration(hours: 7)).toIso8601String(),
          },
        ],
      });
      final result = await DemoQuickAddRepository(data).saveAll(entry);
      expect(result.nutritionCount, 1);
      expect(result.workoutCount, 1);

      final logs = await data.health.fetchNutritionLogs(today);
      expect(logs.last.foodName, 'Makarna');
      expect(logs.last.mealType, 'dinner');
      expect(logs.last.source, 'ai');
      final after = await data.kokpit.fetchNutritionFor(today);
      expect(after.calories, before.calories + 300);
      expect(after.entryCount, before.entryCount + 1);

      final workouts =
          await data.health.fetchWorkouts(today, AppDates.endOfDay(today));
      expect(workouts.map((w) => w.title), contains('Koşu'));
    });
  });
}
