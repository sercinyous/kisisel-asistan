import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  group('ParsedEntry.fromJson toleransı', () {
    test('boş nesne -> boş girdi', () {
      final entry = ParsedEntry.fromJson(const {});
      expect(entry.isEmpty, isTrue);
      expect(entry.totalCount, 0);
    });

    test('dizi yerine yanlış tipler yok sayılır', () {
      final entry = ParsedEntry.fromJson(const {
        'tasks': 'yok',
        'nutrition': 42,
        'workouts': null,
        'weights': {'weight_kg': 80},
        'notes': true,
      });
      expect(entry.isEmpty, isTrue);
    });

    test('dizi içindeki nesne olmayan öğeler atlanır', () {
      final entry = ParsedEntry.fromJson({
        'tasks': [
          null,
          'metin',
          7,
          {'title': 'Geçerli'},
        ],
      });
      expect(entry.tasks.map((t) => t.title), ['Geçerli']);
    });

    test('jsonDecode çıktısı (Map<String, dynamic>) doğrudan okunur', () {
      final decoded = jsonDecode('''
        {"tasks":[{"title":"Rapor","category":"Finans","priority":"high",
                   "due_at":"2026-11-17T15:00:00+03:00","remind_at":null}],
         "nutrition":[],"workouts":[],"weights":[],"notes":[]}''') as Map;
      final entry = ParsedEntry.fromJson(Map<String, dynamic>.from(decoded));
      expect(entry.totalCount, 1);
      expect(entry.tasks.single.category, 'Finans');
    });
  });

  group('ParsedTask', () {
    test('başlıksız ya da boş başlıklı görev atılır', () {
      expect(ParsedTask.fromJson(const {}), isNull);
      expect(ParsedTask.fromJson(const {'title': '   '}), isNull);
      expect(ParsedTask.fromJson(const {'title': 12}), isNull);
    });

    test('varsayılanlar: Kişisel / medium / tarihsiz', () {
      final task = ParsedTask.fromJson(const {'title': '  Süt al  '})!;
      expect(task.title, 'Süt al');
      expect(task.category, 'Kişisel');
      expect(task.priority, 'medium');
      expect(task.description, isNull);
      expect(task.assignee, isNull);
      expect(task.dueAt, isNull);
      expect(task.remindAt, isNull);
    });

    test('bilinmeyen enum değerleri varsayılana düşer', () {
      final task = ParsedTask.fromJson(const {
        'title': 'x',
        'category': 'Spor',
        'priority': 'urgent',
      })!;
      expect(task.category, 'Kişisel');
      expect(task.priority, 'medium');
    });

    test('enum eşleşmesi büyük/küçük harfe duyarsızdır (ASCII)', () {
      final task = ParsedTask.fromJson(const {
        'title': 'x',
        'category': 'pusholder',
        'priority': 'HIGH',
      })!;
      expect(task.category, 'Pusholder');
      expect(task.priority, 'high');
    });

    test('Türkçe küçük harfli enum: "kişisel" ve "toplantı"', () {
      expect(
        ParsedTask.fromJson(const {'title': 'x', 'category': 'kişisel'})!
            .category,
        'Kişisel',
      );
      expect(
        ParsedNote.fromJson(const {'title': 'x', 'category': 'toplantı'})!
            .category,
        'Toplantı',
      );
    });

    test('Türkçe büyük harfli enum: "KİŞİSEL" ve "FİKİR"', () {
      expect(
        ParsedTask.fromJson(const {'title': 'x', 'category': 'KİŞİSEL'})!
            .category,
        'Kişisel',
      );
      expect(
        ParsedNote.fromJson(const {'title': 'x', 'category': 'FİKİR'})!
            .category,
        'Fikir',
      );
    });

    test(
      'noktasız I içeren büyük harfli not kategorisi: "TOPLANTI"',
      () {
        expect(
          ParsedNote.fromJson(const {'title': 'x', 'category': 'TOPLANTI'})!
              .category,
          'Toplantı',
        );
      },
    );

    test('geçersiz tarih null olur, hata fırlatmaz', () {
      final task = ParsedTask.fromJson(const {
        'title': 'x',
        'due_at': 'yarın öğlen',
        'remind_at': 1700000000,
      })!;
      expect(task.dueAt, isNull);
      expect(task.remindAt, isNull);
    });

    // remind_at boşsa bildirim anını ayarlardaki "randevu kaç dk önce" süresi
    // belirler (buildNotificationPlan); burada termin kopyalanmaz.
    test('remind_at yoksa boş kalır', () {
      final task = ParsedTask.fromJson(const {
        'title': 'Toplantı',
        'due_at': '2026-11-17T15:00:00+03:00',
        'remind_at': null,
      })!;
      expect(task.dueAt, DateTime.utc(2026, 11, 17, 12));
      expect(task.remindAt, isNull);
      expect(task.toJson()['remind_at'], isNull);
    });

    test('remind_at geçersizse boş kalır', () {
      final task = ParsedTask.fromJson(const {
        'title': 'Toplantı',
        'due_at': '2026-11-17T15:00:00+03:00',
        'remind_at': '',
      })!;
      expect(task.dueAt, DateTime.utc(2026, 11, 17, 12));
      expect(task.remindAt, isNull);
    });

    test('remind_at terminle aynı ansa (model yinelemesi) boş kalır', () {
      for (final remind in const [
        '2026-11-17T15:00:00+03:00',
        // Aynı an, farklı yazım.
        '2026-11-17T12:00:00Z',
      ]) {
        final task = ParsedTask.fromJson({
          'title': 'Toplantı',
          'due_at': '2026-11-17T15:00:00+03:00',
          'remind_at': remind,
        })!;
        expect(task.dueAt, DateTime.utc(2026, 11, 17, 12), reason: remind);
        expect(task.remindAt, isNull, reason: remind);
      }
    });

    test('yalnızca tarih yinelenmişse saat 09:00 olur, hatırlatma boş kalır',
        () {
      final task = ParsedTask.fromJson(const {
        'title': 'Rapor',
        'due_at': '2099-01-05T00:00:00',
        'remind_at': '2099-01-05T00:00:00',
      })!;
      expect(task.dueAt, DateTime(2099, 1, 5, 9));
      expect(task.remindAt, isNull);
    });

    test('yalnızca remind_at verilmişse korunur', () {
      final task = ParsedTask.fromJson(const {
        'title': 'İlacı al',
        'remind_at': '2026-11-17T09:00:00+03:00',
      })!;
      expect(task.dueAt, isNull);
      expect(task.remindAt, DateTime.utc(2026, 11, 17, 6));
    });

    test('remind_at verilmişse korunur', () {
      final task = ParsedTask.fromJson(const {
        'title': 'Toplantı',
        'due_at': '2026-11-17T15:00:00+03:00',
        'remind_at': '2026-11-17T14:45:00+03:00',
      })!;
      expect(task.remindAt, DateTime.utc(2026, 11, 17, 11, 45));
    });

    test('toJson: RPC sütun adları ve UTC ISO tarihleri', () {
      final json = ParsedTask.fromJson(const {
        'title': 'Toplantı',
        'description': 'Vardiya planı',
        'category': 'Ekip',
        'priority': 'high',
        'assignee': 'Duhan',
        'due_at': '2026-11-17T15:00:00+03:00',
        'remind_at': '2026-11-17T14:30:00+03:00',
      })!
          .toJson();
      // quick_add_entries: x(title, description, category, priority,
      //                      assignee, due_at, remind_at)
      expect(json.keys.toSet(), {
        'title',
        'description',
        'category',
        'priority',
        'assignee',
        'due_at',
        'remind_at',
      });
      expect(json['due_at'], '2026-11-17T12:00:00.000Z');
      expect(json['remind_at'], '2026-11-17T11:30:00.000Z');
      expect(json['assignee'], 'Duhan');
    });

    test('toJson: boş tarihler null gider', () {
      final json = ParsedTask.fromJson(const {'title': 'x'})!.toJson();
      expect(json['due_at'], isNull);
      expect(json['remind_at'], isNull);
    });
  });

  group('ParsedNutrition', () {
    test('food_name yoksa atılır', () {
      expect(ParsedNutrition.fromJson(const {'calories': 100}), isNull);
    });

    test('metin olarak gelen sayılar (virgüllü dahil) okunur', () {
      final n = ParsedNutrition.fromJson(const {
        'food_name': 'Tavuk göğsü',
        'meal_type': 'LUNCH',
        'calories': '330',
        'protein_g': '62,5',
        'carbs_g': 0,
        'fat_g': 7.2,
      })!;
      expect(n.mealType, 'lunch');
      expect(n.mealLabel, 'Öğle');
      expect(n.calories, 330);
      expect(n.proteinG, 62.5);
      expect(n.carbsG, 0);
      expect(n.fatG, 7.2);
    });

    test('eksik/yanlış tipli makrolar 0 olur, öğün snack olur', () {
      final n = ParsedNutrition.fromJson(const {
        'food_name': 'Elma',
        'meal_type': 'brunch',
        'calories': null,
        'protein_g': 'çok',
        'carbs_g': [1],
      })!;
      expect(n.mealType, 'snack');
      expect(n.mealLabel, 'Ara öğün');
      expect([n.calories, n.proteinG, n.carbsG, n.fatG], [0, 0, 0, 0]);
      expect(n.eatenAt, isNull);
    });

    test('değerler şema sınırlarına kırpılır', () {
      final n = ParsedNutrition.fromJson(const {
        'food_name': 'Abartı',
        'calories': 99999,
        'protein_g': -5,
        'carbs_g': 801,
        'fat_g': 400.5,
      })!;
      expect(n.calories, 5000);
      expect(n.proteinG, 0);
      expect(n.carbsG, 800);
      expect(n.fatG, 400);
    });

    test('toJson: RPC sütun adları', () {
      final json = ParsedNutrition.fromJson(const {
        'food_name': 'Yulaf',
        'meal_type': 'breakfast',
        'quantity_text': '60 gr',
        'calories': 230,
        'protein_g': 8,
        'carbs_g': 40,
        'fat_g': 4,
        'eaten_at': '2026-11-16T08:30:00+03:00',
      })!
          .toJson();
      expect(json.keys.toSet(), {
        'meal_type',
        'food_name',
        'quantity_text',
        'calories',
        'protein_g',
        'carbs_g',
        'fat_g',
        'eaten_at',
      });
      expect(json['eaten_at'], '2026-11-16T05:30:00.000Z');
      expect(() => jsonEncode(json), returnsNormally);
    });
  });

  group('ParsedWorkout', () {
    test('varsayılanlar', () {
      final w = ParsedWorkout.fromJson(const {})!;
      expect(w.workoutType, 'other');
      expect(w.typeLabel, 'Antrenman');
      expect(w.title, 'Antrenman');
      expect(w.durationMin, isNull);
      expect(w.distanceKm, isNull);
      expect(w.caloriesBurned, isNull);
    });

    test('süre 1..600 dışındaysa null (fitness_logs check kısıtı)', () {
      ParsedWorkout parse(Object? d) =>
          ParsedWorkout.fromJson({'duration_min': d})!;
      expect(parse(0).durationMin, isNull);
      expect(parse(-10).durationMin, isNull);
      expect(parse(601).durationMin, isNull);
      expect(parse(1).durationMin, 1);
      expect(parse(600).durationMin, 600);
      expect(parse(44.6).durationMin, 45);
      expect(parse('45').durationMin, 45);
      expect(parse('kırk beş').durationMin, isNull);
    });

    test('mesafe 0 ya da negatifse null', () {
      expect(ParsedWorkout.fromJson(const {'distance_km': 0})!.distanceKm,
          isNull);
      expect(ParsedWorkout.fromJson(const {'distance_km': -3})!.distanceKm,
          isNull);
      expect(ParsedWorkout.fromJson(const {'distance_km': '5,2'})!.distanceKm,
          5.2);
    });

    test('toJson: negatif kalori null gider, sütun adları RPC ile aynı', () {
      final json = ParsedWorkout.fromJson(const {
        'workout_type': 'running',
        'title': 'Sabah koşusu',
        'duration_min': 30,
        'distance_km': 5,
        'calories_burned': -1,
        'notes': 'tempo',
        'performed_at': '2026-11-16T07:00:00Z',
      })!
          .toJson();
      expect(json.keys.toSet(), {
        'workout_type',
        'title',
        'duration_min',
        'distance_km',
        'calories_burned',
        'notes',
        'performed_at',
      });
      expect(json['calories_burned'], isNull);
      expect(json['performed_at'], '2026-11-16T07:00:00.000Z');
    });
  });

  group('ParsedWeight', () {
    test('30..250 kg dışı atılır', () {
      expect(ParsedWeight.fromJson(const {'weight_kg': 29.9}), isNull);
      expect(ParsedWeight.fromJson(const {'weight_kg': 250.1}), isNull);
      expect(ParsedWeight.fromJson(const {'weight_kg': null}), isNull);
      expect(ParsedWeight.fromJson(const {'weight_kg': 'ağır'}), isNull);
      expect(ParsedWeight.fromJson(const {'weight_kg': 30})!.weightKg, 30);
      expect(ParsedWeight.fromJson(const {'weight_kg': 250})!.weightKg, 250);
    });

    test('metin olarak gelen kilo okunur ve toJson sütunları doğrudur', () {
      final w = ParsedWeight.fromJson(const {
        'weight_kg': '83,9',
        'measured_at': '2026-11-16T08:00:00+03:00',
      })!;
      expect(w.weightKg, 83.9);
      expect(w.toJson(), {
        'weight_kg': 83.9,
        'measured_at': '2026-11-16T05:00:00.000Z',
      });
    });
  });

  group('ParsedNote', () {
    test('başlık yoksa içerik başlık olur; ikisi de yoksa atılır', () {
      expect(ParsedNote.fromJson(const {}), isNull);
      final note = ParsedNote.fromJson(const {'content': 'Sadece içerik'})!;
      expect(note.title, 'Sadece içerik');
      expect(note.content, 'Sadece içerik');
      expect(note.category, 'Kişisel');
    });

    test('başlık 200 karaktere kırpılır (notes.title check kısıtı)', () {
      final note = ParsedNote.fromJson({'content': 'a' * 500})!;
      expect(note.title.length, 200);
      expect(note.content.length, 500);
    });

    test('toJson sütunları', () {
      final note = ParsedNote.fromJson(const {
        'title': 'Şablon fikri',
        'content': 'Son dakika başlıkları',
        'category': 'Fikir',
      })!;
      expect(note.toJson(), {
        'title': 'Şablon fikri',
        'content': 'Son dakika başlıkları',
        'category': 'Fikir',
      });
    });
  });

  group('ParsedEntry.toJson / without', () {
    ParsedEntry sample() => ParsedEntry.fromJson(const {
          'tasks': [
            {'title': 'G1'},
            {'title': 'G2'},
          ],
          'nutrition': [
            {'food_name': 'B1'},
          ],
          'workouts': [
            {'title': 'A1'},
          ],
          'weights': [
            {'weight_kg': 84},
          ],
          'notes': [
            {'title': 'N1'},
          ],
        });

    test('toJson üst düzey anahtarları RPC payload ile aynıdır', () {
      final json = sample().toJson();
      // quick_add_entries'in okuduğu altı dizi; other_domain veritabanına gitmez.
      expect(json.keys.toSet(),
          {'tasks', 'nutrition', 'workouts', 'weights', 'notes', 'routines'});
      expect(() => jsonEncode(json), returnsNormally);
      expect((json['tasks'] as List).length, 2);
      expect(json['routines'], isEmpty);
    });

    test('toJson other_domain alanlarını yüke koymaz', () {
      final json = ParsedEntry.fromJson(const {
        'notes': [
          {'title': 'N1'},
        ],
        'other_domain': true,
        'other_domain_summary': 'öğle yemeği',
      }).toJson();
      expect(json.containsKey('other_domain'), isFalse);
      expect(json.containsKey('other_domain_summary'), isFalse);
    });

    test('without rutin kalemini çıkarır, diğer alan bilgisini korur', () {
      final entry = ParsedEntry.fromJson(const {
        'routines': [
          {'title': 'R1'},
          {'title': 'R2'},
        ],
        'other_domain': true,
        'other_domain_summary': 'öğle yemeği',
      });
      final next = entry.without(ParsedKind.routine, 0);
      expect(next.routines.single.title, 'R2');
      expect(next.otherDomain, isTrue);
      expect(next.otherDomainSummary, 'öğle yemeği');
      expect(entry.routines, hasLength(2));
    });

    test('without yalnızca istenen kalemi çıkarır ve kaynağı değiştirmez', () {
      final entry = sample();
      final next = entry.without(ParsedKind.task, 0);
      expect(next.tasks.map((t) => t.title), ['G2']);
      expect(next.totalCount, entry.totalCount - 1);
      expect(entry.tasks.length, 2);
      expect(next.nutrition, same(entry.nutrition));
    });

    test('without her tür için çalışır', () {
      var entry = sample();
      entry = entry.without(ParsedKind.nutrition, 0);
      entry = entry.without(ParsedKind.workout, 0);
      entry = entry.without(ParsedKind.weight, 0);
      entry = entry.without(ParsedKind.note, 0);
      expect(entry.totalCount, 2);
      entry = entry.without(ParsedKind.task, 1).without(ParsedKind.task, 0);
      expect(entry.isEmpty, isTrue);
    });

    test('without aralık dışı indekste hiçbir şey yapmaz', () {
      final entry = sample();
      expect(entry.without(ParsedKind.task, 5).totalCount, entry.totalCount);
      expect(entry.without(ParsedKind.note, -1).totalCount, entry.totalCount);
    });
  });

  group('ParsedRoutine', () {
    ParsedRoutine parse(Map<String, dynamic> json) =>
        ParsedRoutine.fromJson(json)!;

    test('aylık iş: tüm alanlar', () {
      final r = parse(const {
        'title': '  Maaş ödemeleri ',
        'scope': 'Pusholder',
        'category': 'finans',
        'frequency': 'monthly',
        'days_of_week': [1, 2, 3, 4, 5, 6, 7],
        'day_of_month': 15,
        'time_of_day': '10:00',
      });
      expect(r.title, 'Maaş ödemeleri');
      expect(r.scope, 'Pusholder');
      expect(r.category, 'finans');
      expect(r.frequency, RoutineFrequency.monthly);
      expect(r.isMonthly, isTrue);
      expect(r.dayOfMonth, 15);
      expect(r.time, const TimeOfDayValue(10, 0));
      expect(r.scheduleLabel, 'Her ayın 15. günü · 10:00');
    });

    test('başlık yoksa ya da boşsa kalem atılır', () {
      expect(ParsedRoutine.fromJson(const {'frequency': 'weekly'}), isNull);
      expect(ParsedRoutine.fromJson(const {'title': '   '}), isNull);
      expect(ParsedRoutine.fromJson(const {'title': 7}), isNull);
    });

    test('başlık 200 kod noktasına kırpılır', () {
      final r = parse({'title': '😀' * 250});
      expect(r.title.runes.length, 200);
    });

    test('ayın günü 1..31 aralığına sıkıştırılır', () {
      int? dayFor(Object? value) => parse({
            'title': 'x',
            'frequency': 'monthly',
            'day_of_month': value,
          }).dayOfMonth;

      expect(dayFor(0), 1);
      expect(dayFor(-4), 1);
      expect(dayFor(1), 1);
      expect(dayFor(31), 31);
      expect(dayFor(32), 31);
      expect(dayFor(99), 31);
      expect(dayFor(15.0), 15);
      expect(dayFor('28'), 28);
    });

    test('günü okunamayan aylık iş atılır (gün uydurulmaz)', () {
      for (final value in [null, 'on beş', <int>[], double.nan]) {
        expect(
          ParsedRoutine.fromJson({
            'title': 'x',
            'frequency': 'monthly',
            'day_of_month': value,
          }),
          isNull,
          reason: '$value',
        );
      }
    });

    test('aylıkta haftanın günleri yok sayılır', () {
      final r = parse(const {
        'title': 'x',
        'frequency': 'monthly',
        'day_of_month': 1,
        'days_of_week': [2],
      });
      expect(r.daysOfWeek, Routine.everyDay);
      expect(r.toJson()['days_of_week'], [1, 2, 3, 4, 5, 6, 7]);
    });

    test('haftalıkta günler ISO 1..7, sıralı ve tekrarsız olur', () {
      List<int> daysFor(Object? value) => parse({
            'title': 'x',
            'frequency': 'weekly',
            'days_of_week': value,
          }).daysOfWeek;

      expect(daysFor([1]), [1]);
      expect(daysFor([5, 1, 3]), [1, 3, 5]);
      expect(daysFor([2, 2, 4, 4]), [2, 4]);
      expect(daysFor([0]), [7], reason: 'Pazar = 0 yazımı ISO 7 olur');
      expect(daysFor([0, 6]), [6, 7]);
      expect(daysFor([1, 8, -1, 42]), [1]);
      expect(daysFor(['3', 4.0, 'salı', null]), [3, 4]);
    });

    test('haftalıkta geçerli gün yoksa her gün varsayılır', () {
      for (final value in [null, <int>[], [9, 12], 'pazartesi', 3]) {
        final r = parse({
          'title': 'x',
          'frequency': 'weekly',
          'days_of_week': value,
        });
        expect(r.daysOfWeek, [1, 2, 3, 4, 5, 6, 7], reason: '$value');
      }
    });

    test('haftalıkta ayın günü taşınmaz', () {
      final r = parse(const {
        'title': 'x',
        'frequency': 'weekly',
        'days_of_week': [1],
        'day_of_month': 15,
      });
      expect(r.isMonthly, isFalse);
      expect(r.dayOfMonth, isNull);
      expect(r.toJson()['day_of_month'], isNull);
    });

    test('sıklık yazılmamışsa eldeki alandan çıkarılır', () {
      expect(parse(const {'title': 'x'}).frequency, RoutineFrequency.weekly);
      expect(
        parse(const {'title': 'x', 'day_of_month': 5}).frequency,
        RoutineFrequency.monthly,
      );
      expect(
        parse(const {
          'title': 'x',
          'day_of_month': 5,
          'days_of_week': [1],
        }).frequency,
        RoutineFrequency.weekly,
      );
      expect(
        parse(const {'title': 'x', 'frequency': 'yearly', 'days_of_week': [2]})
            .frequency,
        RoutineFrequency.weekly,
      );
    });

    test('sıklık büyük/küçük harfe duyarsızdır; "daily" her gün demektir', () {
      expect(
        parse(const {'title': 'x', 'frequency': 'MONTHLY', 'day_of_month': 3})
            .isMonthly,
        isTrue,
      );
      final daily = parse(const {
        'title': 'x',
        'frequency': 'daily',
        'days_of_week': [1],
      });
      expect(daily.frequency, RoutineFrequency.weekly);
      expect(daily.daysOfWeek, Routine.everyDay);
      expect(daily.toJson()['frequency'], 'weekly');
    });

    test('saat "HH:MM" olarak doğrulanır', () {
      TimeOfDayValue? timeFor(Object? value) =>
          parse({'title': 'x', 'time_of_day': value}).time;

      expect(timeFor('10:00'), const TimeOfDayValue(10, 0));
      expect(timeFor('00:00'), const TimeOfDayValue(0, 0));
      expect(timeFor('23:59'), const TimeOfDayValue(23, 59));
      expect(timeFor('9:05'), const TimeOfDayValue(9, 5));
      expect(timeFor(' 11:30 '), const TimeOfDayValue(11, 30));
      expect(timeFor('11.30'), const TimeOfDayValue(11, 30));
      expect(timeFor('10:00:00'), const TimeOfDayValue(10, 0));

      for (final invalid in [
        null,
        '',
        '24:00',
        '12:60',
        '99:99',
        '10',
        '10:5',
        'sabah',
        '10:00 PM',
        '-1:30',
        1030,
        '2026-11-16T10:00:00+03:00',
      ]) {
        expect(timeFor(invalid), isNull, reason: '$invalid');
      }
    });

    test('scope ve category enum dışıysa güvenli varsayılana düşer', () {
      final unknown = parse(const {
        'title': 'x',
        'scope': 'Şirket',
        'category': 'eğlence',
      });
      expect(unknown.scope, 'Kişisel');
      expect(unknown.category, 'kisisel');

      final missing = parse(const {'title': 'x'});
      expect(missing.scope, 'Kişisel');
      expect(missing.category, 'kisisel');
    });

    test('scope ve category Türkçe harf farkına duyarsız eşleşir', () {
      final r = parse(const {
        'title': 'x',
        'scope': 'PUSHOLDER',
        'category': 'FİNANS',
      });
      expect(r.scope, 'Pusholder');
      expect(r.category, 'finans');
      expect(parse(const {'title': 'x', 'scope': 'KİŞİSEL'}).scope, 'Kişisel');
      expect(parse(const {'title': 'x', 'scope': 'kisisel'}).scope, 'Kişisel');
      expect(parse(const {'title': 'x', 'category': 'Operasyon'}).category,
          'operasyon');
    });

    test('toJson: quick_add_entries routines sütunları', () {
      final weekly = parse(const {
        'title': 'Ekip toplantısı',
        'scope': 'Pusholder',
        'category': 'operasyon',
        'frequency': 'weekly',
        'days_of_week': [1],
        'time_of_day': '11:00',
      }).toJson();
      expect(weekly, {
        'title': 'Ekip toplantısı',
        'scope': 'Pusholder',
        'category': 'operasyon',
        'frequency': 'weekly',
        'days_of_week': [1],
        'day_of_month': null,
        'time_of_day': '11:00',
      });

      final monthly = parse(const {
        'title': 'Kira',
        'frequency': 'monthly',
        'day_of_month': 45,
        'time_of_day': 'öğlen',
      }).toJson();
      expect(monthly, {
        'title': 'Kira',
        'scope': 'Kişisel',
        'category': 'kisisel',
        'frequency': 'monthly',
        'days_of_week': [1, 2, 3, 4, 5, 6, 7],
        'day_of_month': 31,
        'time_of_day': null,
      });
      expect(() => jsonEncode(monthly), returnsNormally);
    });

    test('scheduleLabel tekrar özetleri', () {
      String labelFor(Object? days, [String? time]) => parse({
            'title': 'x',
            'days_of_week': days,
            'time_of_day': time,
          }).scheduleLabel;

      expect(labelFor(null), 'Her gün');
      expect(labelFor([1, 2, 3, 4, 5], '09:00'), 'Hafta içi her gün · 09:00');
      expect(labelFor([6, 7]), 'Hafta sonu');
      expect(labelFor([1], '11:00'), 'Her Pzt · 11:00');
      expect(labelFor([7, 3]), 'Her Çar, Paz');
    });
  });

  group('ParsedEntry: rutinler ve diğer alan', () {
    test('routines dizisi okunur, geçersiz kalemler atlanır', () {
      final entry = ParsedEntry.fromJson(const {
        'routines': [
          {'title': 'Maaş', 'frequency': 'monthly', 'day_of_month': 15},
          {'frequency': 'weekly'},
          'metin',
          {'title': 'Günsüz aylık', 'frequency': 'monthly'},
          {'title': 'Toplantı', 'days_of_week': [1]},
        ],
      });
      expect(entry.routines.map((r) => r.title), ['Maaş', 'Toplantı']);
      expect(entry.totalCount, 2);
      expect(entry.isEmpty, isFalse);
    });

    test('routines dizi değilse boş kalır', () {
      expect(ParsedEntry.fromJson(const {'routines': 'yok'}).routines, isEmpty);
      expect(ParsedEntry.fromJson(const {'routines': null}).routines, isEmpty);
    });

    test('other_domain yalnızca açıkça true ise işaretlenir', () {
      bool flagFor(Object? value) =>
          ParsedEntry.fromJson({'other_domain': value}).otherDomain;

      expect(flagFor(true), isTrue);
      expect(flagFor('true'), isTrue);
      expect(flagFor(' TRUE '), isTrue);
      expect(flagFor(false), isFalse);
      expect(flagFor(null), isFalse);
      expect(flagFor('evet'), isFalse);
      expect(flagFor(1), isFalse);
      expect(ParsedEntry.fromJson(const {}).otherDomain, isFalse);
    });

    test('yalnızca other_domain olan girdi boştur (kayıt sayılmaz)', () {
      final entry = ParsedEntry.fromJson(const {
        'other_domain': true,
        'other_domain_summary': '  Öğlen tavuk  ',
      });
      expect(entry.isEmpty, isTrue);
      expect(entry.totalCount, 0);
      expect(entry.otherDomainSummary, 'Öğlen tavuk');
    });

    test('özet boşsa null olur, uzunsa 200 kod noktasına kırpılır', () {
      expect(
        ParsedEntry.fromJson(const {'other_domain_summary': '   '})
            .otherDomainSummary,
        isNull,
      );
      expect(
        ParsedEntry.fromJson(const {'other_domain_summary': 12})
            .otherDomainSummary,
        isNull,
      );
      expect(
        ParsedEntry.fromJson({'other_domain_summary': 'ö' * 500})
            .otherDomainSummary!
            .runes
            .length,
        200,
      );
    });

    test('restrictedTo alanın dışındaki kalemleri atar, bayrağı korur', () {
      final entry = ParsedEntry.fromJson(const {
        'tasks': [
          {'title': 'G'},
        ],
        'notes': [
          {'title': 'N'},
        ],
        'routines': [
          {'title': 'R'},
        ],
        'nutrition': [
          {'food_name': 'B'},
        ],
        'workouts': [
          {'title': 'A'},
        ],
        'weights': [
          {'weight_kg': 84},
        ],
        'other_domain': true,
        'other_domain_summary': 'özet',
      });

      final work = entry.restrictedTo(QuickAddMode.work);
      expect(work.totalCount, 3);
      expect(work.tasks, hasLength(1));
      expect(work.notes, hasLength(1));
      expect(work.routines, hasLength(1));
      expect(work.nutrition, isEmpty);
      expect(work.workouts, isEmpty);
      expect(work.weights, isEmpty);
      expect(work.otherDomain, isTrue);
      expect(work.otherDomainSummary, 'özet');

      final health = entry.restrictedTo(QuickAddMode.health);
      expect(health.totalCount, 3);
      expect(health.tasks, isEmpty);
      expect(health.notes, isEmpty);
      expect(health.routines, isEmpty);
      expect(health.nutrition, hasLength(1));
      expect(health.workouts, hasLength(1));
      expect(health.weights, hasLength(1));
      expect(health.otherDomain, isTrue);
    });
  });

  group('QuickAddMode', () {
    test('other karşı alanı verir', () {
      expect(QuickAddMode.work.other, QuickAddMode.health);
      expect(QuickAddMode.health.other, QuickAddMode.work);
    });

    test('etiketler', () {
      expect(QuickAddMode.work.title, 'İş girişi');
      expect(QuickAddMode.health.title, 'Sağlık & beslenme girişi');
      expect(QuickAddMode.work.switchLabel, 'İş girişine geç');
      expect(QuickAddMode.health.switchLabel, 'Sağlık girişine geç');
      expect(QuickAddMode.work.recordNoun, 'iş kaydı');
      expect(QuickAddMode.health.recordNoun, 'sağlık kaydı');
    });
  });
}
