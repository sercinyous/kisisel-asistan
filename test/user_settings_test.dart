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
        'start_weight_kg': 84.5,
        'target_weight_kg': 78.0,
        'daily_calories': 2000,
        'daily_protein_g': 170,
        'daily_carbs_g': 180,
        'daily_fat_g': 65,
        'daily_steps': 10000,
        'sleep_minutes': 450,
        'notifications_enabled': true,
        'routine_notifications': true,
        'monthly_lead_days': 3,
        'monthly_remind_time': '09:00',
        'event_remind_minutes': 30,
        'quiet_hours_enabled': true,
        'quiet_start': '23:00',
        'quiet_end': '07:30',
        'team_members': ['Duhan', 'İlhan', 'Mehmet', 'Sedat'],
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
}
