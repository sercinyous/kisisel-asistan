import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/theme/app_theme.dart';
import 'package:kisisel_asistan/features/kokpit/presentation/kokpit_motion.dart';

Widget _host(Widget child, {bool reduce = false}) => MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

Widget _counter(int value) => KokpitCountUp(
      value: value,
      builder: (_, v) => Text('$v', textDirection: TextDirection.ltr),
    );

void main() {
  group('KokpitCountUp', () {
    testWidgets('ilk görünüşte 0dan sayar ve 400 ms içinde biter',
        (tester) async {
      await tester.pumpWidget(_host(_counter(120)));
      expect(find.text('0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('120'), findsNothing);
      await tester.pump(KokpitMotion.fill);
      expect(find.text('120'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('hareket azaltılınca doğrudan son değer', (tester) async {
      await tester.pumpWidget(_host(_counter(120), reduce: true));
      expect(find.text('120'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('KokpitEntrance', () {
    testWidgets('soluk başlar, 400 ms içinde tam görünür', (tester) async {
      await tester.pumpWidget(
        _host(const KokpitEntrance(index: 3, child: Text('Kart'))),
      );
      expect(find.byType(Opacity), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Opacity), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('hareket azaltılınca animasyonsuz', (tester) async {
      await tester.pumpWidget(
        _host(
          const KokpitEntrance(index: 3, child: Text('Kart')),
          reduce: true,
        ),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('KokpitCelebrate', () {
    Widget celebrate(bool active, {bool reduce = false}) => _host(
          KokpitCelebrate(
            key: const ValueKey('c'),
            active: active,
            color: AppColors.accent,
            child: const SizedBox.square(dimension: 20),
          ),
          reduce: reduce,
        );

    KokpitCelebrateState state(WidgetTester tester) =>
        tester.state(find.byKey(const ValueKey('c')));

    testWidgets('false → true geçişinde kutlar, sonra durur', (tester) async {
      await tester.pumpWidget(celebrate(false));
      expect(state(tester).celebrations, 0);
      await tester.pumpWidget(celebrate(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(state(tester).celebrations, 1);
      expect(state(tester).playing, isTrue);
      await tester.pumpAndSettle();
      expect(state(tester).playing, isFalse);
    });

    testWidgets('ilk çizimde zaten tamamsa kutlamaz', (tester) async {
      await tester.pumpWidget(celebrate(true));
      await tester.pump();
      expect(state(tester).celebrations, 0);
      expect(state(tester).playing, isFalse);
    });

    testWidgets('hareket azaltılınca sayılır ama oynatılmaz', (tester) async {
      await tester.pumpWidget(celebrate(false, reduce: true));
      await tester.pumpWidget(celebrate(true, reduce: true));
      expect(state(tester).celebrations, 1);
      expect(state(tester).playing, isFalse);
    });
  });

  test('günün bölümü saate göre seçilir', () {
    expect(KokpitDayPhase.of(DateTime(2026, 1, 1, 7)), KokpitDayPhase.sabah);
    expect(KokpitDayPhase.of(DateTime(2026, 1, 1, 13)), KokpitDayPhase.ogle);
    expect(KokpitDayPhase.of(DateTime(2026, 1, 1, 19)), KokpitDayPhase.aksam);
    expect(KokpitDayPhase.of(DateTime(2026, 1, 1, 23)), KokpitDayPhase.gece);
    expect(KokpitDayPhase.of(DateTime(2026, 1, 1, 3)), KokpitDayPhase.gece);
  });
}
