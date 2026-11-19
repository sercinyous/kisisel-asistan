import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/widgets/ritim_top/ritim_top.dart';
import 'package:kisisel_asistan/core/widgets/ritim_top/ritim_top_geometry.dart';

Widget _host(Widget child, {bool reduced = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('RitimTopGeometry', () {
    test('üç şekil 100x100 uzayının içinde kalır', () {
      for (final path in [
        RitimTopGeometry.ring,
        RitimTopGeometry.handle,
        RitimTopGeometry.cone,
      ]) {
        final bounds = path.getBounds();
        expect(bounds.isEmpty, isFalse);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(RitimTopGeometry.viewBox));
        expect(bounds.bottom, lessThanOrEqualTo(RitimTopGeometry.viewBox));
      }
      expect(RitimTopGeometry.cone.contains(const Offset(45, 70)), isTrue);
      expect(RitimTopGeometry.handle.contains(const Offset(54, 30)), isTrue);
      expect(RitimTopGeometry.ring.contains(const Offset(50, 52)), isTrue);
      // Halkanın ortası boştur.
      expect(RitimTopGeometry.ring.contains(const Offset(45, 43)), isFalse);
    });

    test('desteklenmeyen komut hata verir', () {
      expect(() => RitimTopGeometry.parse('M 0 0 Q 1 1 2 2'),
          throwsFormatException);
    });
  });

  group('RitimTopPose', () {
    test('yerine oturma simge duruşunda biter', () {
      final end = RitimTopPose.at(RitimTopMode.settle, 1);
      expect(end.tilt, closeTo(0, 1e-9));
      expect(end.scale, closeTo(1, 1e-9));
      expect(end.stretch, closeTo(0, 1e-9));
      expect(end.opacity, 1);
      expect(end.highlight, 0);
      expect(end.shadow, 0);
    });

    test('dönme döngüsü baştan sona süreklidir', () {
      final a = RitimTopPose.at(RitimTopMode.spin, 0);
      final b = RitimTopPose.at(RitimTopMode.spin, 1);
      expect(b.tilt, closeTo(a.tilt, 1e-9));
      expect(b.stretch, closeTo(a.stretch, 1e-9));
      expect(b.shadowScale, closeTo(a.shadowScale, 1e-9));
      // Yalpalama birkaç dereceyi geçmez.
      for (var i = 0; i <= 20; i++) {
        expect(RitimTopPose.at(RitimTopMode.spin, i / 20).tilt.abs(),
            lessThan(0.08));
      }
    });
  });

  group('RitimTop', () {
    testWidgets('spin sürekli döner ve "Yükleniyor" der', (tester) async {
      await tester.pumpWidget(_host(const RitimTop(size: 72)));
      expect(tester.getSize(find.byType(RitimTop)), const Size.square(72));
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('settle bir kez oynar ve onDone çağırır', (tester) async {
      var done = 0;
      await tester.pumpWidget(_host(
        RitimTop(mode: RitimTopMode.settle, size: 96, onDone: () => done++),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, 0);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(done, 1);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('idle durağandır', (tester) async {
      await tester.pumpWidget(_host(
        const RitimTop(mode: RitimTopMode.idle, semanticsLabel: 'Ritim'),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('Ritim'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hareket azaltmada spin durağan kalır', (tester) async {
      await tester.pumpWidget(_host(const RitimTop(), reduced: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('Yükleniyor'), findsOneWidget);
    });

    testWidgets('hareket azaltmada settle oynamadan onDone çağırır',
        (tester) async {
      var done = 0;
      await tester.pumpWidget(_host(
        RitimTop(mode: RitimTopMode.settle, onDone: () => done++),
        reduced: true,
      ));
      await tester.pump();
      expect(done, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('kip değişince yeniden başlar ve temiz sökülür',
        (tester) async {
      var done = 0;
      await tester.pumpWidget(_host(const RitimTop()));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(_host(
        RitimTop(mode: RitimTopMode.settle, onDone: () => done++),
      ));
      await tester.pumpAndSettle();
      expect(done, 1);
      await tester.pumpWidget(_host(const SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });
}
