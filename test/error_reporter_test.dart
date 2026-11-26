import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/services/error_reporter.dart';

void main() {
  late DateTime now;
  late List<List<ErrorReport>> batches;

  ErrorReporter make({int maxPerDay = 3, Future<void> Function()? fail}) =>
      ErrorReporter(
        now: () => now,
        maxPerDay: maxPerDay,
        dedupWindow: const Duration(minutes: 10),
        platform: 'ios',
        version: '9.9.9',
        send: (reports) async {
          if (fail != null) await fail();
          batches.add(reports);
        },
      );

  setUp(() {
    now = DateTime(2026, 11, 18, 12);
    batches = [];
  });

  test('aynı hata pencere içinde bir kez gönderilir, sonra yeniden', () async {
    final r = make();
    final stack = StackTrace.fromString('#0 main (a.dart:1)\n#1 x');
    expect(r.report(StateError('a'), stack), isTrue);
    expect(r.report(StateError('a'), stack), isFalse);
    now = now.add(const Duration(minutes: 11));
    expect(r.report(StateError('a'), stack), isTrue);
    await r.flush();
    expect(batches.single, hasLength(2));
    expect(batches.single.first.platform, 'ios');
    expect(batches.single.first.appVersion, '9.9.9');
  });

  test('günlük sınır aşılınca kabul edilmez, 24 saat sonra açılır', () async {
    final r = make(maxPerDay: 2);
    expect(r.report('1', null), isTrue);
    expect(r.report('2', null), isTrue);
    expect(r.report('3', null), isFalse);
    now = now.add(const Duration(hours: 24));
    expect(r.report('4', null), isTrue);
  });

  test('uzun mesaj ve iz kırpılır', () async {
    final r = make();
    r.report('x' * 5000, StackTrace.fromString('y' * 9000));
    await r.flush();
    final report = batches.single.single;
    expect(report.message.length, ErrorReport.maxMessage);
    expect(report.stack!.length, ErrorReport.maxStack);
  });

  test('gönderim hatası yutulur', () async {
    final r = make(fail: () async => throw Exception('ağ yok'));
    expect(r.report('a', null), isTrue);
    await expectLater(r.flush(), completes);
    expect(r.pendingCount, 0);
  });

  test('toString fırlatan hata raporlayıcıyı bozmaz', () {
    final r = make();
    expect(r.report(_Bad(), null), isFalse);
  });
  test('hata metnindeki tırnaklı kullanıcı değerleri silinir', () {
    expect(
      ErrorReporter.scrubMessage(
          const FormatException('Bozuk "gizli not"\nayrıntı')),
      'FormatException: FormatException: Bozuk "…"',
    );
    expect(ErrorReporter.scrubMessage(StateError("x 'ali@ex.com'")),
        "Bad state: x '…'");
  });
}

class _Bad {
  @override
  String toString() => throw Exception('bozuk');
}
