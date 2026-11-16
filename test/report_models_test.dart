import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/reports/data/reports_repository.dart';

/// Sunucunun (report_weekly_metrics) ürettiği biçimde tam bir örnek.
Map<String, dynamic> fullWeekly() => {
      'period': {'start': '2026-09-28', 'end': '2026-10-04'},
      'work': {
        'tasks_total': 4,
        'tasks_done': 3,
        'routines_planned': 16,
        'routines_done': 8,
        'rate': 55,
      },
      'form': {
        'workouts_planned': 3,
        'workouts_done': 4,
        'protein_days_hit': 2,
        'calorie_days_in_range': 2,
        'rate': 50,
      },
      'nutrition': {
        'calories': 1950.1,
        'protein_g': 156.6,
        'carbs_g': 170.0,
        'fat_g': 57.5,
        'days_logged': 4,
      },
      'health': {
        'steps': 10000,
        'sleep_minutes': 450,
        'active_kcal': 450,
        'days_with_data': 3,
      },
      'weight': {'start_kg': 83.8, 'end_kg': 83.1, 'change_kg': -0.7},
      'targets': {
        'calories': 2000,
        'protein_g': 170,
        'steps': 10000,
        'sleep_minutes': 450,
      },
      'days': [
        {
          'date': '2026-09-28',
          'work_rate': 75,
          'form_rate': 100,
          'calories': 1700.0,
          'protein_g': 153.0,
          'steps': 8000,
          'sleep_minutes': 420,
          'workouts': 2,
        },
        {
          'date': '2026-09-29',
          'work_rate': null,
          'form_rate': 0,
          'calories': 2200.5,
          'protein_g': 140.5,
          'steps': 12000,
          'sleep_minutes': 0,
          'workouts': 1,
        },
      ],
    };

void main() {
  group('ReportMetrics.fromJson', () {
    test('tam örnek bütün alanlarıyla okunur', () {
      final m = ReportMetrics.fromJson(fullWeekly());
      expect(m.periodStart, DateTime(2026, 9, 28));
      expect(m.periodEnd, DateTime(2026, 10, 4));
      expect(m.tasksTotal, 4);
      expect(m.tasksDone, 3);
      expect(m.routinesPlanned, 16);
      expect(m.routinesDone, 8);
      expect(m.workRate, 55);
      expect(m.workoutsPlanned, 3);
      expect(m.workoutsDone, 4);
      expect(m.proteinDaysHit, 2);
      expect(m.calorieDaysInRange, 2);
      expect(m.formRate, 50);
      expect(m.calories, 1950.1);
      expect(m.proteinG, 156.6);
      expect(m.carbsG, 170.0);
      expect(m.fatG, 57.5);
      expect(m.daysLogged, 4);
      expect(m.steps, 10000);
      expect(m.sleepMinutes, 450);
      expect(m.activeKcal, 450);
      expect(m.daysWithData, 3);
      expect(m.weightStartKg, 83.8);
      expect(m.weightEndKg, 83.1);
      expect(m.weightChangeKg, -0.7);
      expect(m.targetCalories, 2000);
      expect(m.targetProteinG, 170);
      expect(m.targetSteps, 10000);
      expect(m.targetSleepMinutes, 450);
      expect(m.hasNutrition, isTrue);
      expect(m.hasHealth, isTrue);

      expect(m.days, hasLength(2));
      final monday = m.days.first;
      expect(monday.date, DateTime(2026, 9, 28));
      expect(monday.workRate, 75);
      expect(monday.formRate, 100);
      expect(monday.calories, 1700.0);
      expect(monday.proteinG, 153.0);
      expect(monday.steps, 8000);
      expect(monday.sleepMinutes, 420);
      expect(monday.workouts, 2);
      expect(m.days.last.workRate, isNull);
      expect(m.days.last.formRate, 0);
    });

    test('türetilen oranlar: rutin ve görev yüzdesi', () {
      final m = ReportMetrics.fromJson(fullWeekly());
      expect(m.routineRate, 50);
      expect(m.taskRate, 75);
    });

    test('null, boş ve harita olmayan girdi boş rapor verir', () {
      for (final input in <Object?>[null, const <String, dynamic>{}, 'metin', 42, const <int>[1]]) {
        final m = ReportMetrics.fromJson(input);
        expect(m.workRate, isNull, reason: '$input');
        expect(m.formRate, isNull);
        expect(m.tasksTotal, 0);
        expect(m.calories, 0);
        expect(m.weightChangeKg, isNull);
        expect(m.targetCalories, isNull);
        expect(m.periodStart, isNull);
        expect(m.days, isEmpty);
        expect(m.hasNutrition, isFalse);
        expect(m.hasHealth, isFalse);
        expect(m.routineRate, isNull);
        expect(m.taskRate, isNull);
      }
    });

    test('eksik bölümler ve eksik anahtarlar varsayılana düşer', () {
      final m = ReportMetrics.fromJson({
        'work': {'tasks_total': 2},
        'weight': <String, dynamic>{},
      });
      expect(m.tasksTotal, 2);
      expect(m.tasksDone, 0);
      expect(m.workRate, isNull);
      expect(m.formRate, isNull);
      expect(m.steps, 0);
      expect(m.weightStartKg, isNull);
      expect(m.days, isEmpty);
    });

    test('null değerler: oranlar ve kilo null, sayaçlar sıfır', () {
      final m = ReportMetrics.fromJson({
        'work': {'tasks_total': null, 'rate': null},
        'form': {'rate': null, 'workouts_done': null},
        'nutrition': {'calories': null, 'days_logged': null},
        'weight': {'start_kg': null, 'end_kg': null, 'change_kg': null},
        'targets': {'calories': null},
        'days': null,
      });
      expect(m.tasksTotal, 0);
      expect(m.workRate, isNull);
      expect(m.formRate, isNull);
      expect(m.workoutsDone, 0);
      expect(m.calories, 0);
      expect(m.daysLogged, 0);
      expect(m.weightStartKg, isNull);
      expect(m.weightEndKg, isNull);
      expect(m.weightChangeKg, isNull);
      expect(m.targetCalories, isNull);
      expect(m.days, isEmpty);
    });

    test('int / double farkı: tam sayı double alana, kesirli tam sayı alana', () {
      final m = ReportMetrics.fromJson({
        'work': {'tasks_total': 4.0, 'rate': 54.6},
        'nutrition': {'calories': 1950, 'protein_g': 156},
        'health': {'steps': 9999.6, 'sleep_minutes': 450.0},
        'weight': {'start_kg': 84, 'end_kg': 83, 'change_kg': -1},
        'targets': {'calories': 2000.0},
      });
      expect(m.tasksTotal, 4);
      expect(m.workRate, 55);
      expect(m.calories, 1950.0);
      expect(m.calories, isA<double>());
      expect(m.proteinG, 156.0);
      expect(m.steps, 10000);
      expect(m.sleepMinutes, 450);
      expect(m.weightStartKg, 84.0);
      expect(m.weightChangeKg, -1.0);
      expect(m.targetCalories, 2000);
    });

    test('metin olarak gelen sayılar okunur; sayı olmayan metin yok sayılır', () {
      final m = ReportMetrics.fromJson({
        'work': {'tasks_total': '7', 'tasks_done': 'yedi', 'rate': '81'},
        'nutrition': {'calories': ' 1800.5 '},
        'weight': {'end_kg': '83.1'},
      });
      expect(m.tasksTotal, 7);
      expect(m.tasksDone, 0);
      expect(m.workRate, 81);
      expect(m.calories, 1800.5);
      expect(m.weightEndKg, 83.1);
    });

    test('yanlış türdeki bölümler (liste, metin, bool) yok sayılır', () {
      final m = ReportMetrics.fromJson({
        'work': [1, 2],
        'form': 'yok',
        'nutrition': true,
        'days': {'date': '2026-09-28'},
        'health': {'steps': true, 'sleep_minutes': <int>[]},
      });
      expect(m.tasksTotal, 0);
      expect(m.formRate, isNull);
      expect(m.calories, 0);
      expect(m.steps, 0);
      expect(m.sleepMinutes, 0);
      expect(m.days, isEmpty);
    });

    test('oranlar 0..100 aralığına sıkıştırılır', () {
      final m = ReportMetrics.fromJson({
        'work': {'rate': 140},
        'form': {'rate': -5},
      });
      expect(m.workRate, 100);
      expect(m.formRate, 0);
    });

    test('change_kg yoksa iki uçtan hesaplanır', () {
      final m = ReportMetrics.fromJson({
        'weight': {'start_kg': 84.0, 'end_kg': 83.5},
      });
      expect(m.weightChangeKg, closeTo(-0.5, 1e-9));
    });

    test('days: tarihi bozuk kalemler atlanır, günler sıralanır', () {
      final m = ReportMetrics.fromJson({
        'days': [
          {'date': '2026-09-30', 'work_rate': 67},
          {'date': 'bozuk', 'work_rate': 10},
          'metin',
          null,
          {'work_rate': 10},
          {'date': '2026-09-28', 'work_rate': '75', 'steps': 8000.0},
        ],
      });
      expect(m.days.map((d) => d.date), [DateTime(2026, 9, 28), DateTime(2026, 9, 30)]);
      expect(m.days.first.workRate, 75);
      expect(m.days.first.steps, 8000);
      expect(m.days.first.formRate, isNull);
      expect(m.days.first.calories, 0);
    });

    test('anahtarları String olmayan harita (Map<dynamic, dynamic>) okunur', () {
      final Map<dynamic, dynamic> raw = {
        'work': <dynamic, dynamic>{'tasks_total': 3, 'rate': 33},
      };
      final m = ReportMetrics.fromJson(raw);
      expect(m.tasksTotal, 3);
      expect(m.workRate, 33);
    });
  });

  group('ReportAiStatus.fromDb', () {
    test('bilinen değerler', () {
      expect(ReportAiStatus.fromDb('ok'), ReportAiStatus.ok);
      expect(ReportAiStatus.fromDb('failed'), ReportAiStatus.failed);
      expect(ReportAiStatus.fromDb('pending'), ReportAiStatus.pending);
    });
    test('bilinmeyen ya da eksik değer pending', () {
      expect(ReportAiStatus.fromDb(null), ReportAiStatus.pending);
      expect(ReportAiStatus.fromDb('bitti'), ReportAiStatus.pending);
      expect(ReportAiStatus.fromDb(1), ReportAiStatus.pending);
    });
  });

  test('ReportKind.apiValue Edge Function değerleriyle aynı', () {
    expect(ReportKind.daily.apiValue, 'daily');
    expect(ReportKind.weekly.apiValue, 'weekly');
  });

  group('WeeklyReport.fromMap', () {
    test('satır okunur; hafta sonu ve yorum durumu', () {
      final r = WeeklyReport.fromMap({
        'week_start': '2026-09-28',
        'metrics': fullWeekly(),
        'ai_summary': '  İyi bir hafta.  ',
        'ai_status': 'ok',
        'generated_at': '2026-10-05T04:00:03+00:00',
      });
      expect(r.weekStart, DateTime(2026, 9, 28));
      expect(r.weekEnd, DateTime(2026, 10, 4));
      expect(r.metrics.workRate, 55);
      expect(r.aiSummary, 'İyi bir hafta.');
      expect(r.aiStatus, ReportAiStatus.ok);
      expect(r.hasSummary, isTrue);
      expect(r.generatedAt!.isUtc, isFalse);
      expect(r.generatedAt!.toUtc(), DateTime.utc(2026, 10, 5, 4, 0, 3));
    });

    test('yorum üretilemediyse sayılar durur, özet yok', () {
      final r = WeeklyReport.fromMap({
        'week_start': '2026-09-28',
        'metrics': fullWeekly(),
        'ai_summary': null,
        'ai_status': 'failed',
        'generated_at': null,
      });
      expect(r.aiStatus, ReportAiStatus.failed);
      expect(r.aiSummary, isNull);
      expect(r.hasSummary, isFalse);
      expect(r.generatedAt, isNull);
      expect(r.metrics.tasksTotal, 4);
    });

    test('sürüm 2 satırı: metrics boş, ai_status yok', () {
      final r = WeeklyReport.fromMap({
        'week_start': '2026-09-21',
        'metrics': <String, dynamic>{},
        'ai_summary': 'eski özet',
      });
      expect(r.aiStatus, ReportAiStatus.pending);
      // Durum 'ok' değilse eski metin yorum olarak gösterilmez.
      expect(r.hasSummary, isFalse);
      expect(r.metrics.workRate, isNull);
    });
  });

  group('DailyReport.fromMap', () {
    test('satır okunur', () {
      final r = DailyReport.fromMap({
        'report_date': '2026-09-28',
        'metrics': {
          'work': {'rate': 75},
          'form': {'rate': 100},
        },
        'ai_summary': 'Güzel bir gün.',
        'ai_status': 'ok',
        'generated_at': '2026-09-28T20:45:02Z',
      });
      expect(r.reportDate, DateTime(2026, 9, 28));
      expect(r.metrics.workRate, 75);
      expect(r.metrics.formRate, 100);
      expect(r.metrics.days, isEmpty);
      expect(r.hasSummary, isTrue);
      expect(r.generatedAt!.toUtc(), DateTime.utc(2026, 9, 28, 20, 45, 2));
    });

    test('boş özet metni yok sayılır', () {
      final r = DailyReport.fromMap({
        'report_date': '2026-09-28',
        'metrics': null,
        'ai_summary': '   ',
        'ai_status': 'ok',
      });
      expect(r.aiSummary, isNull);
      expect(r.hasSummary, isFalse);
      expect(r.metrics.workRate, isNull);
    });
  });

  group('reportErrorMessage', () {
    test('400: sunucunun Türkçe iletisi', () {
      expect(
        reportErrorMessage(400, {'ok': false, 'error': 'Gelecekteki bir tarih için rapor üretilemez.'}),
        'Gelecekteki bir tarih için rapor üretilemez.',
      );
    });
    test('400 ama ileti yoksa genel metin', () {
      expect(reportErrorMessage(400, 'düz metin'), contains('oluşturulamadı'));
      expect(reportErrorMessage(400, null), contains('oluşturulamadı'));
    });
    test('bağlantı, yetki, kurulum ve sunucu hataları', () {
      expect(reportErrorMessage(0, null), contains('Bağlantı'));
      expect(reportErrorMessage(401, null), contains('Oturum'));
      expect(reportErrorMessage(403, null), contains('Oturum'));
      expect(reportErrorMessage(404, null), contains('generate-reports'));
      expect(reportErrorMessage(500, {'error': 'iç ayrıntı'}), isNot(contains('iç ayrıntı')));
      expect(reportErrorMessage(500, null), contains('oluşturulamadı'));
    });
  });
}
