import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_sync.dart';
import 'package:kisisel_asistan/features/ai_quick_add/data/gemini_parser_service.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/parsed_entry.dart';
import 'package:kisisel_asistan/features/ai_quick_add/domain/quick_add_mode.dart';
import 'package:kisisel_asistan/features/ai_quick_add/presentation/ai_quick_add_controller.dart';
import 'package:kisisel_asistan/features/health/domain/health_models.dart';
import 'package:kisisel_asistan/features/health/presentation/energy_providers.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_providers.dart';
import 'package:kisisel_asistan/features/routines/presentation/routines_providers.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/quick_add_fakes.dart';

const Map<String, dynamic> _task = {
  'title': 'Ayşe ile vardiya planı',
  'category': 'Ekip',
  'priority': 'medium',
  'due_at': '2099-01-05T15:00:00+03:00',
};
const Map<String, dynamic> _undatedTask = {'title': 'Tarihsiz iş'};
const Map<String, dynamic> _routine = {
  'title': 'Maaş ödemeleri',
  'scope': 'İş',
  'category': 'finans',
  'frequency': 'monthly',
  'day_of_month': 15,
  'time_of_day': '10:00',
};
const Map<String, dynamic> _note = {'title': 'Fikir', 'content': 'içerik'};
const Map<String, dynamic> _meal = {
  'meal_type': 'lunch',
  'food_name': 'Tavuk göğsü',
  'calories': 330,
  'protein_g': 62,
  'carbs_g': 0,
  'fat_g': 7,
};
const Map<String, dynamic> _workout = {'workout_type': 'weights', 'title': 'Ağırlık'};
const Map<String, dynamic> _weight = {'weight_kg': 83.9};

/// Bir sağlayıcının kaç kez taze veri ürettiğini sayar (ilk yükleme = 1).
class _RefreshCounter {
  int _count = 0;

  void track<T>(ProviderContainer container, ProviderListenable<AsyncValue<T>> provider) {
    container.listen<AsyncValue<T>>(
      provider,
      (_, next) {
        if (next.hasValue && !next.isLoading) _count++;
      },
      fireImmediately: true,
    );
  }

  int get count => _count;
}

void main() {
  late QuickAddHarness harness;
  late ProviderContainer container;

  setUp(() {
    harness = QuickAddHarness();
    container = ProviderContainer(overrides: harness.overrides);
    addTearDown(container.dispose);
  });

  /// autoDispose denetleyiciyi test boyunca canlı tutar.
  QuickAddController controllerFor(QuickAddMode mode) {
    container.listen(quickAddControllerProvider(mode), (_, __) {});
    return container.read(quickAddControllerProvider(mode).notifier);
  }

  QuickAddState stateOf(QuickAddMode mode) =>
      container.read(quickAddControllerProvider(mode));

  void respond(QuickAddMode mode, Map<String, dynamic> json) {
    harness.parserFor(mode).handler =
        (_) async => ParsedEntry.fromJson(json).restrictedTo(mode);
  }

  group('parse', () {
    test('metin kendi alanının ayrıştırıcısına gider', () async {
      respond(QuickAddMode.work, {
        'tasks': [_task],
      });
      respond(QuickAddMode.health, {
        'nutrition': [_meal],
      });

      await controllerFor(QuickAddMode.work).parse('iş metni');
      await controllerFor(QuickAddMode.health).parse('sağlık metni');

      expect(harness.work.inputs, ['iş metni']);
      expect(harness.health.inputs, ['sağlık metni']);
      expect(stateOf(QuickAddMode.work).entry!.tasks, hasLength(1));
      expect(stateOf(QuickAddMode.health).entry!.nutrition, hasLength(1));
    });

    test('iki alanın durumu birbirinden bağımsızdır', () async {
      respond(QuickAddMode.work, {
        'tasks': [_task],
      });
      controllerFor(QuickAddMode.health);
      await controllerFor(QuickAddMode.work).parse('metin');

      expect(stateOf(QuickAddMode.work).status, QuickAddStatus.preview);
      expect(stateOf(QuickAddMode.health).status, QuickAddStatus.idle);
      expect(stateOf(QuickAddMode.health).entry, isNull);
    });

    test('tümüyle diğer alana ait metin: önizleme yok, hata yok, uyarı var',
        () async {
      respond(QuickAddMode.health, {
        'other_domain': true,
        'other_domain_summary': 'Yarın toplantı',
      });
      await controllerFor(QuickAddMode.health).parse('Yarın toplantı var');

      final state = stateOf(QuickAddMode.health);
      expect(state.status, QuickAddStatus.idle);
      expect(state.entry, isNull);
      expect(state.errorMessage, isNull);
      expect(state.otherDomain, isTrue);
      expect(state.otherDomainSummary, 'Yarın toplantı');
    });

    test('karışık metin: bu alanın kalemleri önizlenir, uyarı da taşınır',
        () async {
      respond(QuickAddMode.work, {
        'tasks': [_task],
        'routines': [_routine],
        'other_domain': true,
        'other_domain_summary': 'Öğlen tavuk',
      });
      await controllerFor(QuickAddMode.work).parse('metin');

      final state = stateOf(QuickAddMode.work);
      expect(state.status, QuickAddStatus.preview);
      expect(state.entry!.totalCount, 2);
      expect(state.otherDomain, isTrue);
      expect(state.otherDomainSummary, 'Öğlen tavuk');
    });

    test('hiçbir şey çıkmadıysa ve diğer alan da değilse hata mesajı',
        () async {
      await controllerFor(QuickAddMode.work).parse('selam');

      final state = stateOf(QuickAddMode.work);
      expect(state.status, QuickAddStatus.idle);
      expect(state.otherDomain, isFalse);
      expect(state.errorMessage, contains('Metinden kaydedilecek bir şey'));
    });

    test('yeni ayrıştırma önceki uyarıyı siler', () async {
      final controller = controllerFor(QuickAddMode.health);
      respond(QuickAddMode.health, {'other_domain': true});
      await controller.parse('toplantı');
      expect(stateOf(QuickAddMode.health).otherDomain, isTrue);

      respond(QuickAddMode.health, {
        'nutrition': [_meal],
      });
      await controller.parse('tavuk yedim');

      final state = stateOf(QuickAddMode.health);
      expect(state.otherDomain, isFalse);
      expect(state.otherDomainSummary, isNull);
      expect(state.status, QuickAddStatus.preview);
    });

    test('ayrıştırma hatası uyarıyı geri getirmez', () async {
      final controller = controllerFor(QuickAddMode.health);
      respond(QuickAddMode.health, {'other_domain': true});
      await controller.parse('toplantı');

      harness.health.handler =
          (_) async => throw const AiParseException('kota', statusCode: 429);
      await controller.parse('tekrar');

      final state = stateOf(QuickAddMode.health);
      expect(state.errorMessage, 'kota');
      expect(state.otherDomain, isFalse);
    });

    test('backToEdit uyarıyı siler; son kalemi çıkarmak silmez', () async {
      final controller = controllerFor(QuickAddMode.health);
      respond(QuickAddMode.health, {
        'nutrition': [_meal],
        'other_domain': true,
        'other_domain_summary': 'toplantı',
      });

      await controller.parse('metin');
      controller.remove(ParsedKind.nutrition, 0);
      var state = stateOf(QuickAddMode.health);
      expect(state.status, QuickAddStatus.idle);
      expect(state.entry, isNull);
      expect(state.otherDomain, isTrue, reason: 'iş kısmı hâlâ kaydedilmedi');
      expect(state.otherDomainSummary, 'toplantı');

      await controller.parse('metin');
      controller.backToEdit();
      state = stateOf(QuickAddMode.health);
      expect(state.status, QuickAddStatus.idle);
      expect(state.otherDomain, isFalse);
    });

    test('rutin kalemi önizlemeden çıkarılabilir', () async {
      final controller = controllerFor(QuickAddMode.work);
      respond(QuickAddMode.work, {
        'tasks': [_task],
        'routines': [_routine],
      });
      await controller.parse('metin');
      controller.remove(ParsedKind.routine, 0);

      final entry = stateOf(QuickAddMode.work).entry!;
      expect(entry.routines, isEmpty);
      expect(entry.tasks, hasLength(1));
    });
  });

  group('save', () {
    late _RefreshCounter routines;
    late _RefreshCounter today;
    late _RefreshCounter reminders;
    late _RefreshCounter nutrition;
    late _RefreshCounter month;
    late _RefreshCounter sync;
    late _RefreshCounter energy;

    // Enerji dengesi profil ister; profil dolu olsun ki sağlayıcı gerçek
    // bir EnergyDay üretsin (bayat önbellek görünür olsun).
    setUp(() {
      harness.settings.settings = const UserSettings.defaults().copyWith(
        heightCm: 180,
        birthYear: 1996,
        sex: 'male',
      );
    });

    /// Tazelenen sağlayıcıların adları (ilk yüklemeye göre).
    Future<Set<String>> refreshedAfter(Future<void> Function() action) async {
      final now = DateTime.now();
      routines = _RefreshCounter()..track(container, activeRoutinesProvider);
      today = _RefreshCounter()..track(container, todayOccurrencesProvider);
      reminders = _RefreshCounter()
        ..track(container, upcomingRemindersProvider);
      nutrition = _RefreshCounter()..track(container, todayNutritionProvider);
      month = _RefreshCounter()
        ..track(
          container,
          monthOverviewProvider(DateTime(now.year, now.month)),
        );
      sync = _RefreshCounter()..track(container, notificationSyncProvider);
      energy = _RefreshCounter()
        ..track(
          container,
          energyDayProvider(DateTime(now.year, now.month, now.day)),
        );
      await pumpEventQueue();

      final counters = {
        'activeRoutines': routines,
        'todayOccurrences': today,
        'upcomingReminders': reminders,
        'todayNutrition': nutrition,
        'monthOverview': month,
        'notificationSync': sync,
        'energyDay': energy,
      };
      for (final MapEntry(:key, :value) in counters.entries) {
        expect(value.count, 1, reason: '$key ilk yükleme');
      }

      await action();
      await pumpEventQueue();

      return {
        for (final MapEntry(:key, :value) in counters.entries)
          if (value.count > 1) key,
      };
    }

    Future<bool> parseAndSave(QuickAddMode mode, Map<String, dynamic> json) async {
      respond(mode, json);
      final controller = controllerFor(mode);
      await controller.parse('metin');
      return controller.save();
    }

    test('iş kaydı (görev + rutin): rutinler, hatırlatmalar, ay ve bildirimler tazelenir',
        () async {
      late bool ok;
      final refreshed = await refreshedAfter(() async {
        ok = await parseAndSave(QuickAddMode.work, {
          'tasks': [_task],
          'routines': [_routine],
        });
      });

      expect(ok, isTrue);
      expect(refreshed, {
        'activeRoutines',
        'todayOccurrences',
        'upcomingReminders',
        'monthOverview',
        'notificationSync',
      });
      final state = stateOf(QuickAddMode.work);
      expect(state.status, QuickAddStatus.saved);
      expect(state.savedCount, 2, reason: 'rutin de sayılır');
    });

    test('yalnızca rutin: hatırlatma listesi tazelenmez', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.work, {
          'routines': [_routine],
        }),
      );
      expect(refreshed, {
        'activeRoutines',
        'todayOccurrences',
        'monthOverview',
        'notificationSync',
      });
    });

    test('yalnızca görev: rutin sağlayıcıları tazelenmez', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.work, {
          'tasks': [_task],
        }),
      );
      expect(refreshed, {'upcomingReminders', 'monthOverview', 'notificationSync'});
    });

    test('yalnızca not: hiçbir Kokpit sağlayıcısı tazelenmez', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.work, {
          'notes': [_note],
        }),
      );
      expect(refreshed, isEmpty, reason: 'energyDay de tazelenmez');
      expect(stateOf(QuickAddMode.work).savedCount, 1);
    });

    test('öğün: beslenme özeti ve ay tazelenir, iş tarafı tazelenmez', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.health, {
          'nutrition': [_meal],
        }),
      );
      expect(refreshed, {'todayNutrition', 'monthOverview', 'energyDay'});
    });

    test('antrenman ve kilo: ay özeti ve enerji dengesi tazelenir', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.health, {
          'workouts': [_workout],
          'weights': [_weight],
        }),
      );
      expect(refreshed, {'monthOverview', 'energyDay'});
      expect(stateOf(QuickAddMode.health).savedCount, 2);
    });

    test('yalnızca antrenman: enerji dengesi (aktif kalori) tazelenir',
        () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.health, {
          'workouts': [_workout],
        }),
      );
      expect(refreshed, contains('energyDay'));
    });

    test('yalnızca kilo: enerji dengesi (bazal) tazelenir', () async {
      final refreshed = await refreshedAfter(
        () => parseAndSave(QuickAddMode.health, {
          'weights': [_weight],
        }),
      );
      expect(refreshed, contains('energyDay'));
    });

    test('AI ile öğün kaydedilince Enerji kartı "öğün yok"tan çıkar', () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      container.listen(energyDayProvider(day), (_, __) {});
      expect(
        (await container.read(energyDayProvider(day).future))!.verdict,
        EnergyVerdict.noMeals,
      );

      respond(QuickAddMode.health, {
        'nutrition': [_meal],
      });
      final controller = controllerFor(QuickAddMode.health);
      await controller.parse('metin');
      // Gerçek RPC satırı yazar; sahte depoda aynı etkiyi doğrudan veririz.
      await harness.healthData.createNutritionLog(
        NutritionLog(
          id: '',
          foodName: 'Tavuk göğsü',
          eatenAt: now,
          mealType: 'lunch',
          calories: 2500,
          proteinG: 62,
        ),
      );
      expect(await controller.save(), isTrue);
      await pumpEventQueue();

      expect(
        (await container.read(energyDayProvider(day).future))!.verdict,
        isNot(EnergyVerdict.noMeals),
      );
    });

    test('kayıt hatasında hiçbir şey tazelenmez, önizleme kalır', () async {
      harness.repository.error = Exception('ağ yok');
      late bool ok;
      final refreshed = await refreshedAfter(() async {
        ok = await parseAndSave(QuickAddMode.work, {
          'tasks': [_task],
          'routines': [_routine],
        });
      });

      expect(ok, isFalse);
      expect(refreshed, isEmpty);
      final state = stateOf(QuickAddMode.work);
      expect(state.status, QuickAddStatus.preview);
      expect(state.entry!.totalCount, 2);
      expect(state.errorMessage, contains('hiçbir kayıt yazılmadı'));
      expect(harness.notifications.scheduled, isEmpty);
    });

    test('PostgrestException mesajı kullanıcıya iletilir', () async {
      harness.repository.error =
          const PostgrestException(message: 'routines_monthly_day ihlali');
      final ok = await parseAndSave(QuickAddMode.work, {
        'routines': [_routine],
      });

      expect(ok, isFalse);
      expect(
        stateOf(QuickAddMode.work).errorMessage,
        'Kaydedilemedi: routines_monthly_day ihlali',
      );
    });

    test('RPC yükü: altı dizi, diğer alan bilgisi yok', () async {
      await parseAndSave(QuickAddMode.work, {
        'tasks': [_undatedTask],
        'routines': [_routine],
        'other_domain': true,
        'other_domain_summary': 'Öğlen tavuk',
      });

      final payload = harness.repository.saved.single.toJson();
      expect(payload.keys.toSet(),
          {'tasks', 'nutrition', 'workouts', 'weights', 'notes', 'routines'});
      expect(payload['nutrition'], isEmpty);
      expect(payload['routines'], [
        {
          'title': 'Maaş ödemeleri',
          'scope': 'İş',
          'category': 'finans',
          'frequency': 'monthly',
          'days_of_week': [1, 2, 3, 4, 5, 6, 7],
          'day_of_month': 15,
          'time_of_day': '10:00',
        },
      ]);
    });

    test('yalnızca saati olan görevler için bildirim planlanır', () async {
      await parseAndSave(QuickAddMode.work, {
        'tasks': [_task, _undatedTask],
        'routines': [_routine],
      });

      final reminder = harness.notifications.scheduled.single;
      expect(reminder.title, 'Ayşe ile vardiya planı');
      // 15:00 (+03:00) randevu, varsayılan 30 dk önce.
      expect(reminder.when.toUtc(), DateTime.utc(2099, 1, 5, 11, 30));
    });

    group('randevu bildirimi "randevu kaç dk önce" ayarına uyar', () {
      Future<DateTime> reminderFor(
        Map<String, dynamic> task, {
        required int minutes,
      }) async {
        harness.settings.settings = const UserSettings.defaults()
            .copyWith(eventRemindMinutes: minutes);
        respond(QuickAddMode.work, {
          'tasks': [task],
        });
        final controller = controllerFor(QuickAddMode.work);
        // Ayarlar yüklensin.
        await pumpEventQueue();
        await controller.parse('metin');
        expect(await controller.save(), isTrue);
        return harness.notifications.scheduled.single.when.toUtc();
      }

      test('hatırlatma zamanı söylenmemişse termin − ayar', () async {
        expect(
          await reminderFor(_task, minutes: 45),
          DateTime.utc(2099, 1, 5, 11, 15),
        );
        // Veritabanına hatırlatma saati yazılmaz; plan da aynı kuralı uygular.
        final saved = harness.repository.saved.single.tasks.single;
        expect(saved.remindAt, isNull);
        expect(saved.toJson()['remind_at'], isNull);
      });

      test('model termini remind_at olarak yinelese de ayar uygulanır',
          () async {
        expect(
          await reminderFor(
            {..._task, 'remind_at': '2099-01-05T15:00:00+03:00'},
            minutes: 45,
          ),
          DateTime.utc(2099, 1, 5, 11, 15),
        );
      });

      test('ayar 0 ise bildirim randevu anındadır', () async {
        expect(
          await reminderFor(_task, minutes: 0),
          DateTime.utc(2099, 1, 5, 12),
        );
      });

      test('kullanıcının söylediği hatırlatma zamanı ayarın önüne geçer',
          () async {
        expect(
          await reminderFor(
            {..._task, 'remind_at': '2099-01-05T13:00:00+03:00'},
            minutes: 45,
          ),
          DateTime.utc(2099, 1, 5, 10),
        );
      });
    });

    test('bildirimler kapalıysa görev bildirimi planlanmaz', () async {
      harness.settings.settings =
          const UserSettings.defaults().copyWith(notificationsEnabled: false);
      respond(QuickAddMode.work, {
        'tasks': [_task],
      });
      final controller = controllerFor(QuickAddMode.work);
      await pumpEventQueue();
      await controller.parse('metin');

      expect(await controller.save(), isTrue);
      expect(harness.notifications.scheduled, isEmpty);
    });

    test('ayarlar okunamazsa varsayılan geçerlidir: bildirim planlanır',
        () async {
      harness.settings.fetchError = Exception('ağ yok');
      respond(QuickAddMode.work, {
        'tasks': [_task],
      });
      final controller = controllerFor(QuickAddMode.work);
      await pumpEventQueue();
      await controller.parse('metin');

      expect(await controller.save(), isTrue);
      expect(harness.notifications.scheduled, hasLength(1));
    });

    test('önizleme yokken ya da boşken kaydetmez', () async {
      final controller = controllerFor(QuickAddMode.work);
      expect(await controller.save(), isFalse);

      respond(QuickAddMode.work, {'other_domain': true});
      await controller.parse('öğlen tavuk');
      expect(await controller.save(), isFalse);
      expect(harness.repository.saved, isEmpty);
    });
  });
}
