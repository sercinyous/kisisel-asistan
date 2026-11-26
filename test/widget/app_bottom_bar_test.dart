import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kisisel_asistan/core/widgets/app_bottom_bar.dart';

void main() {
  testWidgets('her slotun dokunma alanı en az 44x44; aralarda ölü bölge yok',
      (tester) async {
    final taps = <int>[];
    var created = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomBar(
            currentIndex: 0,
            onSelect: taps.add,
            onCreate: () => created++,
          ),
        ),
      ),
    );

    expect(AppBottomBar.slotWidth, greaterThanOrEqualTo(44));
    expect(AppBottomBar.slotHeight, greaterThanOrEqualTo(44));

    final kokpit = tester.getRect(find.bySemanticsLabel('Kokpit'));
    expect(kokpit.width, greaterThanOrEqualTo(44));
    expect(kokpit.height, greaterThanOrEqualTo(44));

    // Kapsülün üst kenarına yakın ve iki slotun sınırına dokunma da sayılır.
    await tester.tapAt(kokpit.topCenter + const Offset(0, 2));
    await tester.tapAt(kokpit.centerRight + const Offset(1, 0));
    final plus = tester.getRect(find.bySemanticsLabel('Yeni giriş'));
    await tester.tapAt(plus.bottomCenter - const Offset(0, 2));
    expect(taps, [0, 1]);
    expect(created, 1);
  });
}
