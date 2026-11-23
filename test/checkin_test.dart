import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/features/health/domain/checkin.dart';
import 'package:kisisel_asistan/features/settings/domain/user_settings.dart';

void main() {
  const weekly = UserSettings.defaults();
  final monthly = const UserSettings.defaults()
      .copyWith(checkinCadence: CheckinCadence.monthly, checkinMonthday: 15);

  test('haftalık varsayılan Pazartesi', () {
    expect(isCheckinDay(weekly, DateTime(2026, 11, 23)), isTrue); // Pzt
    expect(isCheckinDay(weekly, DateTime(2026, 11, 24)), isFalse);
    final friday = weekly.copyWith(checkinWeekday: 5);
    expect(isCheckinDay(friday, DateTime(2026, 11, 27)), isTrue);
  });

  test('aylık ayın günü', () {
    expect(isCheckinDay(monthly, DateTime(2026, 12, 15)), isTrue);
    expect(isCheckinDay(monthly, DateTime(2026, 12, 16)), isFalse);
  });

  test('sonraki gün ve kalan', () {
    expect(nextCheckinDay(weekly, DateTime(2026, 11, 26)),
        DateTime(2026, 11, 30));
    expect(daysUntilCheckin(weekly, DateTime(2026, 11, 27)), 3);
    expect(daysUntilCheckin(weekly, DateTime(2026, 11, 23)), 0);
    expect(nextCheckinDay(monthly, DateTime(2026, 11, 20)),
        DateTime(2026, 12, 15));
  });

  test('satır metni', () {
    expect(checkinScheduleLine(weekly, DateTime(2026, 11, 27)),
        'Sonraki ölçü günü: Pazartesi · 3 gün kaldı');
    expect(checkinScheduleLine(weekly, DateTime(2026, 11, 29)),
        'Sonraki ölçü günü: Pazartesi · yarın');
    expect(checkinScheduleLine(weekly, DateTime(2026, 11, 23)),
        'Bugün ölçü ve fotoğraf günü');
  });

  test('ölçü ya da fotoğraf varsa yapıldı', () {
    expect(isCheckinDone(hasMeasurement: false, hasPhoto: false), isFalse);
    expect(isCheckinDone(hasMeasurement: true, hasPhoto: false), isTrue);
    expect(isCheckinDone(hasMeasurement: false, hasPhoto: true), isTrue);
  });
}
