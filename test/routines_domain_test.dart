import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/routines/domain/routine.dart';

Routine weekly(
  String id, {
  List<int> days = Routine.everyDay,
  int? hour,
  int? minute,
  int sortOrder = 0,
  bool isActive = true,
  DateTime? createdAt,
}) =>
    Routine(
      id: id,
      title: 'Haftalık $id',
      daysOfWeek: days,
      hour: hour,
      minute: minute,
      sortOrder: sortOrder,
      isActive: isActive,
      createdAt: createdAt,
    );

Routine monthly(
  String id,
  int day, {
  bool isActive = true,
  int sortOrder = 0,
  DateTime? createdAt,
}) =>
    Routine(
      id: id,
      title: 'Aylık $id',
      scope: Routine.scopeWork,
      category: 'finans',
      frequency: RoutineFrequency.monthly,
      dayOfMonth: day,
      isActive: isActive,
      sortOrder: sortOrder,
      createdAt: createdAt,
    );

RoutineCompletionKey done(String id, DateTime period, {DateTime? at}) =>
    RoutineCompletionKey(id, period, completedAt: at);

void main() {
  group('Routine.fromMap', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
          'id': 'r1',
          'title': 'Sabah kontrolü',
          ...extra,
        };

    test("Postgres time '09:00:00' saat ve dakikaya ayrılır", () {
      final r = Routine.fromMap(row({'time_of_day': '09:00:00'}));
      expect(r.hour, 9);
      expect(r.minute, 0);
      expect(r.hasTime, isTrue);
      expect(r.timeLabel, '09:00');
    });

    test("'21:30' (saniyesiz) de okunur", () {
      expect(Routine.fromMap(row({'time_of_day': '21:30'})).timeLabel, '21:30');
    });

    test('time_of_day null ise saat yok', () {
      final r = Routine.fromMap(row({'time_of_day': null}));
      expect(r.hour, isNull);
      expect(r.minute, isNull);
      expect(r.hasTime, isFalse);
      expect(r.timeLabel, isNull);
    });

    test('bozuk saat metni saat üretmez ve hata fırlatmaz', () {
      for (final garbage in ['abc', '', 'aa:bb', '9', ':', 'on:otuz:00', '9:xx']) {
        final r = Routine.fromMap(row({'time_of_day': garbage}));
        expect(r.hasTime, isFalse, reason: garbage);
        expect(r.hour, isNull, reason: garbage);
        expect(r.minute, isNull, reason: garbage);
        expect(r.timeLabel, isNull, reason: garbage);
      }
      expect(Routine.fromMap(row({'time_of_day': 900})).hasTime, isFalse);
    });

    test('varsayılanlar (sürüm 1 satırı: yeni sütunlar yok)', () {
      final r = Routine.fromMap(row());
      expect(r.scope, 'Kişisel');
      expect(r.category, 'kisisel');
      expect(r.frequency, RoutineFrequency.weekly);
      expect(r.daysOfWeek, [1, 2, 3, 4, 5, 6, 7]);
      expect(r.dayOfMonth, isNull);
      expect(r.notify, isTrue);
      expect(r.isActive, isTrue);
      expect(r.sortOrder, 0);
      expect(r.createdAt, isNull);
      expect(r.isDaily, isTrue);
      expect(r.isMonthly, isFalse);
    });

    test('days_of_week sayı listesi (int/double) int listesine çevrilir', () {
      final r = Routine.fromMap(row({
        'days_of_week': [1, 2.0, 'x', null, 5],
        'notify': false,
        'category': 'spor',
      }));
      expect(r.daysOfWeek, [1, 2, 5]);
      expect(r.isDaily, isFalse);
      expect(r.notify, isFalse);
      expect(r.category, 'spor');
    });

    test('aylık satır', () {
      final r = Routine.fromMap(row({
        'scope': 'İş',
        'category': 'finans',
        'frequency': 'monthly',
        'day_of_month': 15,
        'time_of_day': '10:00:00',
        'is_active': false,
        'sort_order': 120,
        'created_at': '2026-11-01T09:00:00+00:00',
      }));
      expect(r.scope, 'İş');
      expect(r.frequency, RoutineFrequency.monthly);
      expect(r.isMonthly, isTrue);
      expect(r.isDaily, isFalse, reason: 'aylık iş günlük sayılmaz');
      expect(r.dayOfMonth, 15);
      expect(r.isActive, isFalse);
      expect(r.sortOrder, 120);
      expect(r.createdAt!.toUtc(), DateTime.utc(2026, 11, 1, 9));
    });

    test('bilinmeyen frequency haftalığa düşer', () {
      expect(
        Routine.fromMap(row({'frequency': 'yearly'})).frequency,
        RoutineFrequency.weekly,
      );
    });
  });

  group('Routine.toInsertMap', () {
    test('haftalık: günler sıralı ve tekil, day_of_month null', () {
      const r = Routine(
        id: 'x',
        title: '  Ekip toplantısı ',
        scope: Routine.scopeWork,
        category: 'operasyon',
        daysOfWeek: [5, 1, 1],
        dayOfMonth: 12,
        hour: 11,
        minute: 0,
        sortOrder: 50,
      );
      expect(r.toInsertMap(), {
        'title': 'Ekip toplantısı',
        'scope': 'İş',
        'category': 'operasyon',
        'frequency': 'weekly',
        'days_of_week': [1, 5],
        'day_of_month': null,
        'time_of_day': '11:00',
        'notify': true,
        'is_active': true,
        'sort_order': 50,
      });
    });

    test('aylık: day_of_month yazılır, günler tablo kısıtına uyar', () {
      final map = monthly('m', 31).copyWith(daysOfWeek: []).toInsertMap();
      expect(map['frequency'], 'monthly');
      expect(map['day_of_month'], 31);
      expect(map['days_of_week'], [1, 2, 3, 4, 5, 6, 7]);
      expect(map['time_of_day'], isNull);
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('user_id'), isFalse);
    });

    test('boş gün listesi tüm haftaya çevrilir', () {
      expect(weekly('w', days: []).toInsertMap()['days_of_week'],
          [1, 2, 3, 4, 5, 6, 7]);
    });

    test('fromMap ile gidiş-dönüş', () {
      final original = monthly('m', 15).copyWith(hour: 10, minute: 0);
      final back = Routine.fromMap({'id': 'm', ...original.toInsertMap()});
      expect(back.toInsertMap(), original.toInsertMap());
    });
  });

  group('Routine.copyWith', () {
    test('verilmeyen alanlar korunur; clearTime saati siler', () {
      final created = DateTime(2026, 10, 1);
      final r = weekly('w', hour: 8, minute: 15, createdAt: created);
      final next = r.copyWith(title: 'Yeni', notify: false);
      expect(next.id, 'w');
      expect(next.title, 'Yeni');
      expect(next.notify, isFalse);
      expect(next.timeLabel, '08:15');
      expect(next.createdAt, created);
      expect(r.copyWith(clearTime: true).hasTime, isFalse);
      expect(r.copyWith(id: 'z').id, 'z');
    });
  });

  group('RoutineCompletionKey', () {
    test('eşitlik (rutin, dönem) üzerinden; saat ve completedAt yok sayılır', () {
      final a = RoutineCompletionKey('r', DateTime(2026, 11, 16, 14, 30));
      final b = RoutineCompletionKey(
        'r',
        DateTime(2026, 11, 16),
        completedAt: DateTime(2026, 11, 16, 9),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a}.contains(b), isTrue);
      expect(a.periodKey, DateTime(2026, 11, 16));
      expect(a == RoutineCompletionKey('r', DateTime(2026, 11, 17)), isFalse);
      expect(a == RoutineCompletionKey('q', DateTime(2026, 11, 16)), isFalse);
    });

    test('fromMap: date sütunu yerel güne, completed_at yerel saate çevrilir', () {
      final key = RoutineCompletionKey.fromMap(const {
        'routine_id': 'r',
        'completed_on': '2026-11-01',
        'completed_at': '2026-11-14T08:00:00+00:00',
      });
      expect(key.periodKey, DateTime(2026, 11));
      expect(key.completedAt!.toUtc(), DateTime.utc(2026, 11, 14, 8));
      expect(
        RoutineCompletionKey.fromMap(const {
          'routine_id': 'r',
          'completed_on': '2026-11-01',
        }).completedAt,
        isNull,
      );
    });
  });

  group('monthlyDueDate', () {
    test('ayın günü varsa aynen', () {
      expect(monthlyDueDate(monthly('m', 15), 2026, 11), DateTime(2026, 11, 15));
      expect(monthlyDueDate(monthly('m', 1), 2026, 12), DateTime(2026, 12, 1));
      expect(monthlyDueDate(monthly('m', 31), 2026, 12), DateTime(2026, 12, 31));
    });

    test('31 → 30 günlük aylarda 30', () {
      for (final month in [4, 6, 9, 11]) {
        expect(
          monthlyDueDate(monthly('m', 31), 2026, month),
          DateTime(2026, month, 30),
          reason: 'ay $month',
        );
      }
    });

    test('29/30/31 → Şubat: artık olmayan yılda 28, artık yılda 29', () {
      for (final day in [29, 30, 31]) {
        expect(monthlyDueDate(monthly('m', day), 2026, 2), DateTime(2026, 2, 28));
        expect(monthlyDueDate(monthly('m', day), 2027, 2), DateTime(2027, 2, 28));
        expect(monthlyDueDate(monthly('m', day), 2028, 2), DateTime(2028, 2, 29));
      }
      // Yüzyıl kuralı: 2100 artık yıl değildir, 2000 artık yıldı.
      expect(monthlyDueDate(monthly('m', 31), 2100, 2), DateTime(2100, 2, 28));
      expect(monthlyDueDate(monthly('m', 31), 2000, 2), DateTime(2000, 2, 29));
      expect(monthlyDueDate(monthly('m', 28), 2028, 2), DateTime(2028, 2, 28));
    });

    test('hafta sonuna denk gelse de tarih kaymaz', () {
      // 15 Kasım 2026 Pazar.
      final due = monthlyDueDate(monthly('m', 15), 2026, 11);
      expect(due.weekday, DateTime.sunday);
      expect(due.day, 15);
    });

    test('ay taşması yıla yansır (13. ay = gelecek Ocak)', () {
      expect(monthlyDueDate(monthly('m', 31), 2026, 13), DateTime(2027, 1, 31));
      expect(monthlyDueDate(monthly('m', 5), 2027, 0), DateTime(2026, 12, 5));
    });
  });

  group('periodKeyFor', () {
    test('haftalık: günün kendisi (saat atılır)', () {
      expect(
        periodKeyFor(weekly('w'), DateTime(2026, 11, 16, 23, 59)),
        DateTime(2026, 11, 16),
      );
    });

    test('aylık: ayın 1\'i', () {
      final m = monthly('m', 15);
      expect(periodKeyFor(m, DateTime(2026, 11, 1)), DateTime(2026, 11));
      expect(periodKeyFor(m, DateTime(2026, 11, 30, 22)), DateTime(2026, 11));
      expect(periodKeyFor(m, DateTime(2026, 12, 31)), DateTime(2026, 12));
      expect(periodKeyFor(m, DateTime(2028, 2, 29)), DateTime(2028, 2));
    });
  });

  group('occurrencesForDay (günlük/haftalık)', () {
    // 16 Kasım 2026 Pazartesi.
    final monday = DateTime(2026, 11, 16);

    test('yalnızca o hafta gününe düşen rutinler', () {
      final routines = [
        weekly('her-gun'),
        weekly('pzt', days: [1]),
        weekly('sal-per', days: [2, 4]),
        weekly('hafta-sonu', days: [6, 7]),
      ];
      List<String> ids(DateTime day) => [
            for (final o in occurrencesForDay(routines, {}, day)) o.routine.id,
          ];
      expect(ids(monday), unorderedEquals(['her-gun', 'pzt']));
      expect(ids(DateTime(2026, 11, 17)), unorderedEquals(['her-gun', 'sal-per']));
      expect(ids(DateTime(2026, 11, 18)), ['her-gun']);
      expect(ids(DateTime(2026, 11, 19)), unorderedEquals(['her-gun', 'sal-per']));
      expect(ids(DateTime(2026, 11, 21)), unorderedEquals(['her-gun', 'hafta-sonu']));
      expect(ids(DateTime(2026, 11, 22)), unorderedEquals(['her-gun', 'hafta-sonu']));
    });

    test('pasif ve aylık rutinler hariç', () {
      final list = occurrencesForDay(
        [
          weekly('aktif'),
          weekly('pasif', isActive: false),
          monthly('aylik', 16),
        ],
        {},
        monday,
      );
      expect(list.map((o) => o.routine.id), ['aktif']);
    });

    test('tamamlanma yalnızca o günün anahtarıyla eşleşir', () {
      final routines = [weekly('a'), weekly('b')];
      final completions = {
        done('a', monday),
        done('b', DateTime(2026, 11, 15)), // dün
      };
      final list = occurrencesForDay(routines, completions, monday);
      final a = list.firstWhere((o) => o.routine.id == 'a');
      final b = list.firstWhere((o) => o.routine.id == 'b');
      expect(a.completed, isTrue);
      expect(a.status, OccurrenceStatus.done);
      expect(b.completed, isFalse);
      expect(b.status, OccurrenceStatus.dueToday);
    });

    test('dönem anahtarı ve gün = verilen gün; gün içi saat atılır', () {
      final o = occurrencesForDay(
        [weekly('a')],
        {done('a', monday)},
        DateTime(2026, 11, 16, 21, 45),
      ).single;
      expect(o.periodKey, monday);
      expect(o.dueDate, monday);
      expect(o.completed, isTrue);
      expect(o.completionKey, RoutineCompletionKey('a', monday));
      expect(o.daysUntilDue(DateTime(2026, 11, 16, 8)), 0);
    });

    test('sıra: saat, sonra sıra numarası; saatsizler sonda', () {
      final list = occurrencesForDay(
        [
          weekly('saatsiz-2', sortOrder: 20),
          weekly('aksam', hour: 19, minute: 0, sortOrder: 1),
          weekly('saatsiz-1', sortOrder: 10),
          weekly('sabah-b', hour: 9, minute: 0, sortOrder: 20),
          weekly('sabah-a', hour: 9, minute: 0, sortOrder: 10),
          weekly('erken', hour: 8, minute: 30, sortOrder: 99),
        ],
        {},
        monday,
      );
      expect(list.map((o) => o.routine.id), [
        'erken',
        'sabah-a',
        'sabah-b',
        'aksam',
        'saatsiz-1',
        'saatsiz-2',
      ]);
    });
  });

  group('monthlyForDay (Gün ekranı)', () {
    List<RoutineOccurrence> on(
      DateTime today, {
      required List<Routine> routines,
      Set<RoutineCompletionKey>? completions,
      int lead = 3,
    }) =>
        monthlyForDay(routines, completions ?? {}, today, lead);

    final salary = monthly('maas', 15);

    test('pencere açılmadan görünmez; lead gün kala girer', () {
      expect(on(DateTime(2026, 11, 11), routines: [salary]), isEmpty);
      final o = on(DateTime(2026, 11, 12), routines: [salary]).single;
      expect(o.status, OccurrenceStatus.upcoming);
      expect(o.dueDate, DateTime(2026, 11, 15));
      expect(o.periodKey, DateTime(2026, 11));
      expect(o.completed, isFalse);
      expect(o.daysUntilDue(DateTime(2026, 11, 12)), 3);
    });

    test('gün gün durum: yaklaşıyor → bugün → gecikti → ay bitince düşer', () {
      OccurrenceStatus? status(DateTime day) {
        final list = on(day, routines: [salary]);
        return list.isEmpty ? null : list.single.status;
      }

      expect(status(DateTime(2026, 11, 13)), OccurrenceStatus.upcoming);
      expect(status(DateTime(2026, 11, 14)), OccurrenceStatus.upcoming);
      expect(status(DateTime(2026, 11, 15)), OccurrenceStatus.dueToday);
      expect(status(DateTime(2026, 11, 16)), OccurrenceStatus.overdue);
      expect(status(DateTime(2026, 11, 30)), OccurrenceStatus.overdue,
          reason: 'ayın son günü hâlâ gecikmiş olarak durur');
      expect(status(DateTime(2026, 12, 1)), isNull,
          reason: 'eski ayın kaydı birikmez');
      expect(status(DateTime(2026, 12, 11)), isNull);
      expect(status(DateTime(2026, 12, 12)), OccurrenceStatus.upcoming);
    });

    test('gecikme gün sayısı eksi döner', () {
      final today = DateTime(2026, 11, 17, 13);
      final o = on(today, routines: [salary]).single;
      expect(o.status, OccurrenceStatus.overdue);
      expect(o.daysUntilDue(today), -2);
    });

    test('gün içi saat sonucu değiştirmez', () {
      final late = on(DateTime(2026, 11, 15, 23, 59), routines: [salary]).single;
      expect(late.status, OccurrenceStatus.dueToday);
      expect(late.daysUntilDue(DateTime(2026, 11, 15, 23, 59)), 0);
      expect(on(DateTime(2026, 11, 11, 23, 59), routines: [salary]), isEmpty);
    });

    test('lead 0: yalnızca gününde girer, sonra gecikir', () {
      expect(on(DateTime(2026, 11, 14), routines: [salary], lead: 0), isEmpty);
      expect(
        on(DateTime(2026, 11, 15), routines: [salary], lead: 0).single.status,
        OccurrenceStatus.dueToday,
      );
      expect(
        on(DateTime(2026, 11, 16), routines: [salary], lead: 0).single.status,
        OccurrenceStatus.overdue,
      );
    });

    test('lead 14: iki hafta önceden girer', () {
      // Ekim dönemi yapılmış olmalı; yoksa 31 Ekim'de gecikmiş olarak görünür.
      expect(
        on(
          DateTime(2026, 10, 31),
          routines: [salary],
          completions: {done('maas', DateTime(2026, 10))},
          lead: 14,
        ),
        isEmpty,
      );
      expect(
        on(DateTime(2026, 11, 1), routines: [salary], lead: 14)
            .single
            .daysUntilDue(DateTime(2026, 11, 1)),
        14,
      );
    });

    group('ay sınırını aşan pencere', () {
      final report = monthly('rapor', 1);

      test("ayın 1'indeki iş önceki ayın 29'unda GELECEK ayın dönemiyle görünür",
          () {
        final list = on(
          DateTime(2026, 11, 29),
          routines: [report],
          // Kasım dönemi yapılmış: yalnızca Aralık'ınki listelenmeli.
          completions: {done('rapor', DateTime(2026, 11))},
        );
        final o = list.single;
        expect(o.periodKey, DateTime(2026, 12));
        expect(o.dueDate, DateTime(2026, 12, 1));
        expect(o.status, OccurrenceStatus.upcoming);
        expect(o.completed, isFalse);
        expect(o.daysUntilDue(DateTime(2026, 11, 29)), 2);
      });

      test("28'inde henüz yok (3 günden uzak), 30'unda 1 gün kala", () {
        final doneNov = {done('rapor', DateTime(2026, 11))};
        expect(
          on(DateTime(2026, 11, 27), routines: [report], completions: doneNov),
          isEmpty,
        );
        expect(
          on(DateTime(2026, 11, 28), routines: [report], completions: doneNov)
              .single
              .daysUntilDue(DateTime(2026, 11, 28)),
          3,
        );
        expect(
          on(DateTime(2026, 11, 30), routines: [report], completions: doneNov)
              .single
              .daysUntilDue(DateTime(2026, 11, 30)),
          1,
        );
      });

      test('bu ayınki yapılmadıysa gecikmiş olarak yanında durur', () {
        final list = on(DateTime(2026, 11, 29), routines: [report]);
        expect(list, hasLength(2));
        expect(list[0].periodKey, DateTime(2026, 11));
        expect(list[0].status, OccurrenceStatus.overdue);
        expect(list[0].daysUntilDue(DateTime(2026, 11, 29)), -28);
        expect(list[1].periodKey, DateTime(2026, 12));
        expect(list[1].status, OccurrenceStatus.upcoming);
      });

      test('ay dönünce yeni dönem "bugün" olur, eski ayınki düşer', () {
        final o = on(DateTime(2026, 12, 1), routines: [report]).single;
        expect(o.periodKey, DateTime(2026, 12));
        expect(o.status, OccurrenceStatus.dueToday);
      });

      test('gelecek ayın dönemi önceden işaretlenebilir ve yapıldı görünür', () {
        final o = on(
          DateTime(2026, 11, 30),
          routines: [report],
          completions: {
            done('rapor', DateTime(2026, 11)),
            done('rapor', DateTime(2026, 12), at: DateTime(2026, 11, 29, 18)),
          },
        ).single;
        expect(o.periodKey, DateTime(2026, 12));
        expect(o.completed, isTrue);
        expect(o.status, OccurrenceStatus.done);
      });

      test('yıl sınırı: 2 Ocak işi 30 Aralık\'ta gelecek yılın dönemiyle', () {
        final o = on(DateTime(2026, 12, 30), routines: [monthly('y', 2)],
            completions: {done('y', DateTime(2026, 12))}).single;
        expect(o.periodKey, DateTime(2027, 1));
        expect(o.dueDate, DateTime(2027, 1, 2));
        expect(o.daysUntilDue(DateTime(2026, 12, 30)), 3);
      });

      test('Şubat sonu → Mart başı (artık ve artık olmayan yıl)', () {
        final r = monthly('m', 2);
        final feb26 = {done('m', DateTime(2026, 2))};
        // 2026: Şubat 28 gün → 27 Şubat'tan 2 Mart'a 3 gün.
        expect(on(DateTime(2026, 2, 26), routines: [r], completions: feb26),
            isEmpty);
        expect(
          on(DateTime(2026, 2, 27), routines: [r], completions: feb26)
              .single
              .periodKey,
          DateTime(2026, 3),
        );
        // 2028: Şubat 29 gün → 27 Şubat'tan 2 Mart'a 4 gün.
        final feb28 = {done('m', DateTime(2028, 2))};
        expect(on(DateTime(2028, 2, 27), routines: [r], completions: feb28),
            isEmpty);
        expect(
          on(DateTime(2028, 2, 28), routines: [r], completions: feb28)
              .single
              .daysUntilDue(DateTime(2028, 2, 28)),
          3,
        );
      });
    });

    group('ayın 31\'i', () {
      final endOfMonth = monthly('son', 31);

      test('30 günlük ayda 30\'unda "bugün"', () {
        final o = on(DateTime(2026, 11, 30), routines: [endOfMonth]).single;
        expect(o.dueDate, DateTime(2026, 11, 30));
        expect(o.status, OccurrenceStatus.dueToday);
        expect(
          on(DateTime(2026, 11, 27), routines: [endOfMonth]).single.status,
          OccurrenceStatus.upcoming,
        );
        expect(on(DateTime(2026, 11, 26), routines: [endOfMonth]), isEmpty);
      });

      test('Şubat: 28 (2026) ve 29 (2028)', () {
        expect(
          on(DateTime(2026, 2, 28), routines: [endOfMonth]).single.status,
          OccurrenceStatus.dueToday,
        );
        final leap = on(DateTime(2028, 2, 28), routines: [endOfMonth]).single;
        expect(leap.status, OccurrenceStatus.upcoming);
        expect(leap.dueDate, DateTime(2028, 2, 29));
        expect(
          on(DateTime(2028, 2, 29), routines: [endOfMonth]).single.status,
          OccurrenceStatus.dueToday,
        );
      });

      test('ay sonu işinin gecikme günü olmaz: ertesi gün yeni ay', () {
        // 1 Aralık: Kasım dönemi kapandı, Aralık'ınki (31'i) henüz uzak.
        expect(on(DateTime(2026, 12, 1), routines: [endOfMonth]), isEmpty);
      });
    });

    group('tamamlanan iş', () {
      test('penceresi içindeyken (günü gelene kadar) yapıldı olarak kalır', () {
        final completions = {
          done('maas', DateTime(2026, 11), at: DateTime(2026, 11, 12, 10)),
        };
        for (final day in [12, 13, 14, 15]) {
          final o = on(
            DateTime(2026, 11, day),
            routines: [salary],
            completions: completions,
          ).single;
          expect(o.completed, isTrue, reason: 'gün $day');
          expect(o.status, OccurrenceStatus.done, reason: 'gün $day');
        }
      });

      test('günü geçince listeden düşer', () {
        final completions = {
          done('maas', DateTime(2026, 11), at: DateTime(2026, 11, 12, 10)),
        };
        expect(
          on(DateTime(2026, 11, 16), routines: [salary], completions: completions),
          isEmpty,
        );
      });

      test('gecikmişken işaretlenirse o gün boyunca görünür, ertesi gün düşer',
          () {
        final completions = {
          done('maas', DateTime(2026, 11), at: DateTime(2026, 11, 20, 9, 30)),
        };
        final same = on(
          DateTime(2026, 11, 20, 22),
          routines: [salary],
          completions: completions,
        ).single;
        expect(same.status, OccurrenceStatus.done);
        expect(same.completed, isTrue);
        expect(
          on(DateTime(2026, 11, 21), routines: [salary], completions: completions),
          isEmpty,
        );
      });

      test('completedAt bilinmiyorsa gecikmiş-tamamlanmış iş görünmez', () {
        expect(
          on(
            DateTime(2026, 11, 20),
            routines: [salary],
            completions: {done('maas', DateTime(2026, 11))},
          ),
          isEmpty,
        );
      });

      test('pencereden önce (Ay ekranından) işaretlenen iş pencere açılana '
          'kadar Gün ekranına girmez', () {
        final completions = {
          done('maas', DateTime(2026, 11), at: DateTime(2026, 11, 5, 9)),
        };
        expect(
          on(DateTime(2026, 11, 5), routines: [salary], completions: completions),
          isEmpty,
        );
        expect(
          on(DateTime(2026, 11, 13), routines: [salary], completions: completions)
              .single
              .status,
          OccurrenceStatus.done,
        );
      });

      test('başka ayın ya da başka rutinin kaydı sayılmaz', () {
        final o = on(
          DateTime(2026, 11, 15),
          routines: [salary],
          completions: {
            done('maas', DateTime(2026, 10)),
            done('baska', DateTime(2026, 11)),
            // Günlük anahtar aylık dönemle eşleşmez.
            done('maas', DateTime(2026, 11, 15)),
          },
        ).single;
        expect(o.completed, isFalse);
        expect(o.status, OccurrenceStatus.dueToday);
      });
    });

    test('pasif ve haftalık rutinler hariç', () {
      final list = on(
        DateTime(2026, 11, 15),
        routines: [
          salary,
          monthly('pasif', 15, isActive: false),
          weekly('gunluk'),
        ],
      );
      expect(list.map((o) => o.routine.id), ['maas']);
    });

    test('sıra: güne göre, gecikenler önce', () {
      final list = on(
        DateTime(2026, 11, 14),
        routines: [
          monthly('16', 16),
          monthly('10', 10),
          monthly('14', 14),
          monthly('15b', 15, sortOrder: 2),
          monthly('15a', 15, sortOrder: 1),
        ],
      );
      expect(list.map((o) => o.routine.id), ['10', '14', '15a', '15b', '16']);
      expect(list.map((o) => o.status), [
        OccurrenceStatus.overdue,
        OccurrenceStatus.dueToday,
        OccurrenceStatus.upcoming,
        OccurrenceStatus.upcoming,
        OccurrenceStatus.upcoming,
      ]);
    });
  });

  group('monthlyForMonth (Ay ekranı)', () {
    final routines = [monthly('rapor', 1), monthly('maas', 15), monthly('son', 31)];
    final today = DateTime(2026, 11, 15, 10);

    Map<String, OccurrenceStatus> statuses(
      int year,
      int month, {
      Set<RoutineCompletionKey>? completions,
      DateTime? at,
    }) =>
        {
          for (final o in monthlyForMonth(
            routines,
            completions ?? {},
            year,
            month,
            at ?? today,
          ))
            o.routine.id: o.status,
        };

    test('içinde bulunulan ay: gecikti / bugün / bekliyor', () {
      expect(statuses(2026, 11), {
        'rapor': OccurrenceStatus.overdue,
        'maas': OccurrenceStatus.dueToday,
        'son': OccurrenceStatus.upcoming,
      });
    });

    test('tamamlanan her durumda yapıldı', () {
      expect(
        statuses(2026, 11, completions: {done('rapor', DateTime(2026, 11))}),
        containsPair('rapor', OccurrenceStatus.done),
      );
      expect(
        statuses(2026, 10, completions: {done('maas', DateTime(2026, 10))}),
        {
          'rapor': OccurrenceStatus.missed,
          'maas': OccurrenceStatus.done,
          'son': OccurrenceStatus.missed,
        },
      );
    });

    test('geçmiş ay: işaretlenmeyenler yapılmadı olarak kapanır', () {
      expect(statuses(2026, 10).values.toSet(), {OccurrenceStatus.missed});
      expect(statuses(2025, 12).values.toSet(), {OccurrenceStatus.missed});
    });

    test('ay biter bitmez (ayın 1\'i) önceki ay yapılmadı olur', () {
      expect(
        statuses(2026, 11, at: DateTime(2026, 11, 30, 23, 59))['son'],
        OccurrenceStatus.dueToday,
      );
      expect(
        statuses(2026, 11, at: DateTime(2026, 12, 1))['son'],
        OccurrenceStatus.missed,
      );
    });

    test('gelecek ay: hepsi bekliyor', () {
      expect(statuses(2026, 12).values.toSet(), {OccurrenceStatus.upcoming});
      expect(statuses(2027, 1).values.toSet(), {OccurrenceStatus.upcoming});
    });

    test('dönem anahtarı ve günler (31 → Kasım\'da 30, Şubat\'ta 28/29)', () {
      final nov = monthlyForMonth(routines, {}, 2026, 11, today);
      expect(nov.map((o) => o.periodKey).toSet(), {DateTime(2026, 11)});
      expect(nov.map((o) => o.dueDate),
          [DateTime(2026, 11, 1), DateTime(2026, 11, 15), DateTime(2026, 11, 30)]);
      expect(
        monthlyForMonth(routines, {}, 2026, 2, today).last.dueDate,
        DateTime(2026, 2, 28),
      );
      expect(
        monthlyForMonth(routines, {}, 2028, 2, today).last.dueDate,
        DateTime(2028, 2, 29),
      );
    });

    test('pasif ve haftalık rutinler hariç', () {
      final list = monthlyForMonth(
        [monthly('a', 5), monthly('p', 5, isActive: false), weekly('w')],
        {},
        2026,
        11,
        today,
      );
      expect(list.map((o) => o.routine.id), ['a']);
    });

    test('rutinin oluşturulduğu aydan önceki aylar listelenmez', () {
      final fresh = monthly('yeni', 5, createdAt: DateTime(2026, 11, 10));
      expect(monthlyForMonth([fresh], {}, 2026, 10, today), isEmpty);
      expect(monthlyForMonth([fresh], {}, 2025, 11, today), isEmpty);
      expect(
        monthlyForMonth([fresh], {}, 2026, 11, today).single.status,
        OccurrenceStatus.overdue,
      );
      expect(
        monthlyForMonth([fresh], {}, 2026, 12, today).single.status,
        OccurrenceStatus.upcoming,
      );
    });
  });

  group('weeklyStatsForRange', () {
    test('Kasım 2026: her gün 30, pazartesiler 5, hafta sonları 9', () {
      final stats = weeklyStatsForRange(
        [
          weekly('her-gun'),
          weekly('pzt', days: [1]),
          weekly('hs', days: [6, 7]),
          weekly('pasif', isActive: false),
          monthly('aylik', 15),
        ],
        {
          done('her-gun', DateTime(2026, 11, 1)),
          done('her-gun', DateTime(2026, 11, 30)),
          done('pzt', DateTime(2026, 11, 16)),
          // Aralık dışı ve gününe denk gelmeyen kayıtlar sayılmaz.
          done('her-gun', DateTime(2026, 12, 1)),
          done('pzt', DateTime(2026, 11, 17)),
          done('aylik', DateTime(2026, 11)),
        },
        DateTime(2026, 11),
        DateTime(2026, 11, 30),
      );
      expect(stats.planned, 30 + 5 + 9);
      expect(stats.done, 3);
    });

    test('tek gün ve ters aralık', () {
      final day = DateTime(2026, 11, 16);
      expect(
        weeklyStatsForRange([weekly('a')], {done('a', day)}, day, day),
        (planned: 1, done: 1),
      );
      expect(
        weeklyStatsForRange([weekly('a')], {}, day, DateTime(2026, 11, 15)),
        (planned: 0, done: 0),
      );
    });

    test('oluşturulmadan önceki günler planlanmış sayılmaz', () {
      final stats = weeklyStatsForRange(
        [weekly('yeni', createdAt: DateTime(2026, 11, 20, 15))],
        {},
        DateTime(2026, 11),
        DateTime(2026, 11, 30),
      );
      expect(stats.planned, 11); // 20..30
    });

    test('yaz saati geçişi olan ayda gün atlanmaz (Mart: 31 gün)', () {
      final stats = weeklyStatsForRange(
        [weekly('a')],
        {},
        DateTime(2026, 3),
        DateTime(2026, 3, 31),
      );
      expect(stats.planned, 31);
    });
  });

  group('daysUntilDue', () {
    test('ay ve yıl sınırlarında takvim günü sayar', () {
      RoutineOccurrence at(DateTime due) => RoutineOccurrence(
            routine: monthly('m', due.day),
            periodKey: DateTime(due.year, due.month),
            dueDate: due,
            completed: false,
            status: OccurrenceStatus.upcoming,
          );
      expect(at(DateTime(2026, 12, 1)).daysUntilDue(DateTime(2026, 11, 29)), 2);
      expect(at(DateTime(2027, 1, 1)).daysUntilDue(DateTime(2026, 12, 31, 23)), 1);
      expect(at(DateTime(2028, 3, 1)).daysUntilDue(DateTime(2028, 2, 28)), 2);
      expect(at(DateTime(2026, 3, 1)).daysUntilDue(DateTime(2026, 2, 28)), 1);
      expect(at(DateTime(2026, 11, 1)).daysUntilDue(DateTime(2026, 11, 30)), -29);
    });
  });
}
