import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  group('TimeOfDayValue', () {
    test('"HH:mm" ve Postgres "HH:mm:ss" okunur', () {
      expect(TimeOfDayValue.tryParse('09:00'), const TimeOfDayValue(9, 0));
      expect(TimeOfDayValue.tryParse('07:30:00'), const TimeOfDayValue(7, 30));
      expect(TimeOfDayValue.tryParse('23:59:59.123'), const TimeOfDayValue(23, 59));
      expect(TimeOfDayValue.tryParse('0:5'), const TimeOfDayValue(0, 5));
    });

    test('geçersiz değerler null', () {
      for (final bad in <Object?>[null, 900, '', '9', 'aa:bb', '24:00', '12:60', '-1:00', ':']) {
        expect(TimeOfDayValue.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('format sıfır dolgulu; gidiş-dönüş', () {
      expect(const TimeOfDayValue(7, 5).format(), '07:05');
      expect(const TimeOfDayValue(23, 0).toString(), '23:00');
      expect(
        TimeOfDayValue.tryParse(const TimeOfDayValue(0, 0).format()),
        const TimeOfDayValue(0, 0),
      );
    });

    test('eşitlik, sıralama, gece yarısından dakika', () {
      expect(const TimeOfDayValue(9, 0) == const TimeOfDayValue(9, 0), isTrue);
      expect(
        const TimeOfDayValue(9, 0).hashCode,
        const TimeOfDayValue(9, 0).hashCode,
      );
      expect(const TimeOfDayValue(9, 0) == const TimeOfDayValue(9, 1), isFalse);
      expect(
        const TimeOfDayValue(7, 30).compareTo(const TimeOfDayValue(23, 0)),
        isNegative,
      );
      expect(const TimeOfDayValue(7, 30).minutesSinceMidnight, 450);
    });
  });

  group('UserSettings', () {
    test('varsayılanlar veritabanı varsayılanlarıyla aynı', () {
      const d = UserSettings.defaults();
      expect(d.toMap(), {
        'start_weight_kg': 70.0,
        'target_weight_kg': 70.0,
        'daily_calories': 2000,
        'daily_protein_g': 120,
        'daily_carbs_g': 220,
        'daily_fat_g': 65,
        'daily_steps': 8000,
        'sleep_minutes': 450,
        'notifications_enabled': true,
        'routine_notifications': true,
        'monthly_lead_days': 3,
        'monthly_remind_time': '09:00',
        'event_remind_minutes': 30,
        'quiet_hours_enabled': true,
        'quiet_start': '23:00',
        'quiet_end': '07:30',
        'team_members': <String>[],
        'height_cm': null,
        'birth_year': null,
        'sex': null,
        'display_name': null,
        'work_description': null,
      });
    });

    test('fromMap: PostgREST satırı (numeric double/int, time saniyeli)', () {
      final s = UserSettings.fromMap(const {
        'user_id': 'u1',
        'start_weight_kg': 90,
        'target_weight_kg': 80.5,
        'daily_calories': 2200,
        'daily_protein_g': 180,
        'daily_carbs_g': 200,
        'daily_fat_g': 70,
        'daily_steps': 12000,
        'sleep_minutes': 480,
        'notifications_enabled': false,
        'routine_notifications': false,
        'monthly_lead_days': 5,
        'monthly_remind_time': '08:15:00',
        'event_remind_minutes': 60,
        'quiet_hours_enabled': false,
        'quiet_start': '22:00:00',
        'quiet_end': '06:45:00',
        'team_members': ['Ali', 'Veli'],
        'updated_at': '2026-11-16T10:00:00+00:00',
      });
      expect(s.startWeightKg, 90.0);
      expect(s.targetWeightKg, 80.5);
      expect(s.dailyCalories, 2200);
      expect(s.dailySteps, 12000);
      expect(s.sleepMinutes, 480);
      expect(s.notificationsEnabled, isFalse);
      expect(s.routineNotifications, isFalse);
      expect(s.monthlyLeadDays, 5);
      expect(s.monthlyRemindTime, const TimeOfDayValue(8, 15));
      expect(s.eventRemindMinutes, 60);
      expect(s.quietHoursEnabled, isFalse);
      expect(s.quietStart, const TimeOfDayValue(22, 0));
      expect(s.quietEnd, const TimeOfDayValue(6, 45));
      expect(s.teamMembers, ['Ali', 'Veli']);
    });

    test('fromMap: eksik ve bozuk alanlar varsayılana düşer', () {
      final s = UserSettings.fromMap(const {
        'monthly_remind_time': 'bozuk',
        'team_members': 'liste değil',
        'daily_calories': null,
      });
      expect(s.toMap(), const UserSettings.defaults().toMap());
    });

    test('boş ekip listesi korunur', () {
      expect(UserSettings.fromMap(const {'team_members': <String>[]}).teamMembers,
          isEmpty);
    });

    test('toMap → fromMap gidiş-dönüş; user_id/updated_at yazılmaz', () {
      final original = const UserSettings.defaults().copyWith(
        targetWeightKg: 76.5,
        monthlyLeadDays: 0,
        quietEnd: const TimeOfDayValue(6, 0),
        teamMembers: ['Ayşe'],
      );
      final map = original.toMap();
      expect(map.containsKey('user_id'), isFalse);
      expect(map.containsKey('updated_at'), isFalse);
      expect(UserSettings.fromMap(map).toMap(), map);
    });

    test('copyWith yalnızca verilen alanı değiştirir', () {
      const d = UserSettings.defaults();
      final next = d.copyWith(dailyCalories: 2300, notificationsEnabled: false);
      expect(next.dailyCalories, 2300);
      expect(next.notificationsEnabled, isFalse);
      expect(next.dailyProteinG, d.dailyProteinG);
      expect(next.quietStart, d.quietStart);
      expect(next.teamMembers, d.teamMembers);
      expect(d.dailyCalories, 2000);
    });
  });

  group('UserSettings profili (boy, doğum yılı, cinsiyet)', () {
    test('varsayılanda profil boş ve profileComplete false', () {
      const d = UserSettings.defaults();
      expect(d.heightCm, isNull);
      expect(d.birthYear, isNull);
      expect(d.sex, isNull);
      expect(d.profileComplete, isFalse);
    });

    test('fromMap → toMap gidiş-dönüş; anahtarlar height_cm, birth_year, sex', () {
      final s = UserSettings.fromMap(const {
        'height_cm': 180,
        'birth_year': 1990,
        'sex': 'male',
      });
      expect(s.heightCm, 180);
      expect(s.birthYear, 1990);
      expect(s.sex, 'male');
      final map = s.toMap();
      expect(map['height_cm'], 180);
      expect(map['birth_year'], 1990);
      expect(map['sex'], 'male');
      final back = UserSettings.fromMap(map);
      expect(back.heightCm, 180);
      expect(back.birthYear, 1990);
      expect(back.sex, 'male');
      expect(back.toMap(), map);
    });

    test('toMap boş profili null olarak yazar (kullanıcı alanı temizleyebilsin)', () {
      final map = const UserSettings.defaults().toMap();
      expect(map.containsKey('height_cm'), isTrue);
      expect(map.containsKey('birth_year'), isTrue);
      expect(map.containsKey('sex'), isTrue);
      expect(map['height_cm'], isNull);
      expect(map['birth_year'], isNull);
      expect(map['sex'], isNull);
    });

    test('tanınan cinsiyet değerleri korunur', () {
      for (final v in const ['female', 'male', 'unspecified']) {
        expect(UserSettings.fromMap({'sex': v}).sex, v, reason: v);
      }
    });

    test('tanınmayan cinsiyet null olur', () {
      for (final bad in <Object?>['x', '', 'Male', 'FEMALE', 1, true, null]) {
        expect(UserSettings.fromMap({'sex': bad}).sex, isNull, reason: '$bad');
      }
    });

    test('boy aralığı 100..250; dışı null', () {
      expect(UserSettings.fromMap(const {'height_cm': 99}).heightCm, isNull);
      expect(UserSettings.fromMap(const {'height_cm': 100}).heightCm, 100);
      expect(UserSettings.fromMap(const {'height_cm': 250}).heightCm, 250);
      expect(UserSettings.fromMap(const {'height_cm': 251}).heightCm, isNull);
      expect(UserSettings.fromMap(const {'height_cm': -180}).heightCm, isNull);
      expect(UserSettings.fromMap(const {'height_cm': 180.0}).heightCm, 180);
    });

    test('doğum yılı aralığı 1900..2100; dışı null', () {
      expect(UserSettings.fromMap(const {'birth_year': 1899}).birthYear, isNull);
      expect(UserSettings.fromMap(const {'birth_year': 1900}).birthYear, 1900);
      expect(UserSettings.fromMap(const {'birth_year': 2100}).birthYear, 2100);
      expect(UserSettings.fromMap(const {'birth_year': 2101}).birthYear, isNull);
    });

    test('sayısal olmayan ve kesirli profil değerleri null olur', () {
      for (final bad in <Object?>['180', '', true, 180.5, double.nan, double.infinity]) {
        expect(UserSettings.fromMap({'height_cm': bad}).heightCm, isNull,
            reason: '$bad');
        expect(UserSettings.fromMap({'birth_year': bad}).birthYear, isNull,
            reason: '$bad');
      }
    });

    test('profileComplete yalnızca üçü de doluyken true', () {
      const d = UserSettings.defaults();
      expect(d.profileComplete, isFalse);
      expect(d.copyWith(heightCm: 180).profileComplete, isFalse);
      expect(d.copyWith(heightCm: 180, birthYear: 1990).profileComplete, isFalse);
      expect(d.copyWith(heightCm: 180, sex: 'male').profileComplete, isFalse);
      expect(d.copyWith(birthYear: 1990, sex: 'male').profileComplete, isFalse);
      expect(
        d.copyWith(heightCm: 180, birthYear: 1990, sex: 'male').profileComplete,
        isTrue,
      );
      expect(
        d.copyWith(heightCm: 180, birthYear: 1990, sex: 'unspecified').profileComplete,
        isTrue,
      );
    });

    test('copyWith(sex: male) yalnızca cinsiyeti değiştirir', () {
      final base = const UserSettings.defaults()
          .copyWith(heightCm: 170, birthYear: 1985, dailyCalories: 2300);
      final next = base.copyWith(sex: 'male');
      expect(next.sex, 'male');
      expect(next.heightCm, 170);
      expect(next.birthYear, 1985);
      expect(next.dailyCalories, 2300);
      expect(base.sex, isNull);
    });

    test('copyWith clear bayrakları alanı null yapar', () {
      final full = const UserSettings.defaults()
          .copyWith(heightCm: 180, birthYear: 1990, sex: 'female');
      final cleared = full.copyWith(
        clearHeightCm: true,
        clearBirthYear: true,
        clearSex: true,
      );
      expect(cleared.heightCm, isNull);
      expect(cleared.birthYear, isNull);
      expect(cleared.sex, isNull);
      expect(cleared.profileComplete, isFalse);
      final onlyHeight = full.copyWith(clearHeightCm: true);
      expect(onlyHeight.heightCm, isNull);
      expect(onlyHeight.birthYear, 1990);
      expect(onlyHeight.sex, 'female');
    });

    test('profil olmayan alanlar copyWith ile profili silmez', () {
      final full = const UserSettings.defaults()
          .copyWith(heightCm: 180, birthYear: 1990, sex: 'male');
      final next = full.copyWith(dailySteps: 12000);
      expect(next.heightCm, 180);
      expect(next.birthYear, 1990);
      expect(next.sex, 'male');
    });
  });

  group('UserSettings ilk kurulum alanları (görünen ad, iş tanımı, onboarded_at)', () {
    test('varsayılanda üçü de boş; isOnboarded false', () {
      const d = UserSettings.defaults();
      expect(d.displayName, isNull);
      expect(d.workDescription, isNull);
      expect(d.onboardedAt, isNull);
      expect(d.isOnboarded, isFalse);
    });

    test('fromMap okur: metinler kırpılır, zaman yerel zamana çevrilir', () {
      final s = UserSettings.fromMap(const {
        'display_name': '  Ayşe  ',
        'work_description': 'Mimarım, şantiyede çalışırım.',
        'onboarded_at': '2026-11-17T09:30:00+00:00',
      });
      expect(s.displayName, 'Ayşe');
      expect(s.workDescription, 'Mimarım, şantiyede çalışırım.');
      expect(s.onboardedAt!.toUtc(), DateTime.utc(2026, 11, 17, 9, 30));
      expect(s.onboardedAt!.isUtc, isFalse);
      expect(s.isOnboarded, isTrue);
    });

    test('tanınmayan değerler güvenle null olur', () {
      for (final bad in <Object?>[null, 5, true, '', '   ', <String>[]]) {
        final s = UserSettings.fromMap({
          'display_name': bad,
          'work_description': bad,
        });
        expect(s.displayName, isNull, reason: '$bad');
        expect(s.workDescription, isNull, reason: '$bad');
      }
      for (final bad in <Object?>[null, 0, true, '', 'dün', 'bozuk-tarih']) {
        expect(UserSettings.fromMap({'onboarded_at': bad}).onboardedAt, isNull,
            reason: '$bad');
      }
    });

    test('sınırı aşan metin null olur (60 ve 500 karakter dahil geçerli)', () {
      expect(
        UserSettings.fromMap({'display_name': 'a' * 60}).displayName,
        'a' * 60,
      );
      expect(UserSettings.fromMap({'display_name': 'a' * 61}).displayName, isNull);
      expect(
        UserSettings.fromMap({'work_description': 'b' * 500}).workDescription,
        'b' * 500,
      );
      expect(
        UserSettings.fromMap({'work_description': 'b' * 501}).workDescription,
        isNull,
      );
      // Sınır karakter (kod noktası) sayar: emoji tek karakterdir.
      expect(
        UserSettings.fromMap({'display_name': '😀' * 60}).displayName,
        '😀' * 60,
      );
    });

    test('toMap: metinler yazılır; boş olan null yazılır', () {
      final map = const UserSettings.defaults()
          .copyWith(displayName: 'Ayşe', workDescription: 'Mimar')
          .toMap();
      expect(map['display_name'], 'Ayşe');
      expect(map['work_description'], 'Mimar');
      final empty = const UserSettings.defaults().toMap();
      expect(empty.containsKey('display_name'), isTrue);
      expect(empty['display_name'], isNull);
      expect(empty['work_description'], isNull);
    });

    test('toMap: onboarded_at yalnızca doluysa ve UTC ISO olarak yazılır', () {
      expect(
        const UserSettings.defaults().toMap().containsKey('onboarded_at'),
        isFalse,
      );
      final at = DateTime.utc(2026, 11, 17, 9, 30);
      final map = const UserSettings.defaults().copyWith(onboardedAt: at).toMap();
      expect(map['onboarded_at'], '2026-11-17T09:30:00.000Z');
    });

    test('toMap → fromMap gidiş-dönüş aynı anı ve metinleri korur', () {
      final at = DateTime.utc(2026, 11, 17, 9, 30);
      final original = const UserSettings.defaults().copyWith(
        displayName: 'Ayşe',
        workDescription: 'Mimar',
        onboardedAt: at,
      );
      final back = UserSettings.fromMap(original.toMap());
      expect(back.displayName, 'Ayşe');
      expect(back.workDescription, 'Mimar');
      expect(back.onboardedAt!.toUtc(), at);
      expect(back.toMap(), original.toMap());
    });

    test('copyWith yeni alanları değiştirir; clear bayrakları siler', () {
      final at = DateTime.utc(2026, 11, 17);
      final full = const UserSettings.defaults().copyWith(
        displayName: 'Ayşe',
        workDescription: 'Mimar',
        onboardedAt: at,
      );
      // İlgisiz bir alan yeni alanları silmez.
      final other = full.copyWith(dailySteps: 12000);
      expect(other.displayName, 'Ayşe');
      expect(other.workDescription, 'Mimar');
      expect(other.onboardedAt, at);

      final cleared = full.copyWith(
        clearDisplayName: true,
        clearWorkDescription: true,
      );
      expect(cleared.displayName, isNull);
      expect(cleared.workDescription, isNull);
      // Kurulum anı clear bayrağıyla değil, yalnızca yeni değerle değişir.
      expect(cleared.onboardedAt, at);
    });
  });
}
