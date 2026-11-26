import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/notification_service.dart';

void main() {
  test('bildirim yükü ilgili sekmeye eşlenir', () {
    expect(tabForNotificationPayload('task:abc'), 1);
    expect(tabForNotificationPayload('routine:r1:3'), 1);
    expect(tabForNotificationPayload('reminder:x'), 1);
    expect(tabForNotificationPayload('health:meal:2026-11-26'), 2);
    expect(tabForNotificationPayload('bilinmeyen'), isNull);
    expect(tabForNotificationPayload(null), isNull);
  });
}
