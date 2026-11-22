import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:kisisel_asistan/features/settings/data/settings_repository.dart';

void main() {
  group('SettingsRepository.withNetworkRetry', () {
    test('ağ hatasında bir kez yineler', () async {
      for (final error in <Object>[
        const SocketException('yok'),
        ClientException('kapandı'),
        TimeoutException('geç'),
      ]) {
        var calls = 0;
        final result = await SettingsRepository.withNetworkRetry(() async {
          calls++;
          if (calls == 1) throw error;
          return 'ok';
        }, delay: Duration.zero);
        expect(result, 'ok', reason: '$error');
        expect(calls, 2);
      }
    });

    test('ikinci ağ hatası iletilir (en çok iki deneme)', () async {
      var calls = 0;
      await expectLater(
        SettingsRepository.withNetworkRetry<String>(() async {
          calls++;
          throw const SocketException('yok');
        }, delay: Duration.zero),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 2);
    });

    test('ağ dışı hata yinelenmez', () async {
      var calls = 0;
      await expectLater(
        SettingsRepository.withNetworkRetry<String>(() async {
          calls++;
          throw StateError('şema');
        }, delay: Duration.zero),
        throwsStateError,
      );
      expect(calls, 1);
    });
  });
}
