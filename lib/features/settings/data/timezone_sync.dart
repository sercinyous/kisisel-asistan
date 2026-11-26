import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../reports/presentation/reports_providers.dart';
import 'settings_repository.dart';

/// IANA saat dilimi adı (ör. `Europe/Istanbul`, `America/New_York`).
final RegExp _ianaName = RegExp(r'^[A-Za-z]+(?:/[A-Za-z0-9_+\-]+){0,2}$');

/// Cihazın saat dilimini okur ve sunucudakinden farklıysa günceller; değiştiyse
/// raporlar tazelenir. Açılışta ve uygulama öne geldiğinde çağrılır. Eklenti
/// yoksa (test, web) ya da ağ hatasında sessizce hiçbir şey yapmaz.
Future<void> syncDeviceTimezone(
  ProviderContainer container, {
  Future<String> Function()? readDeviceTimezone,
}) async {
  try {
    final name =
        (await (readDeviceTimezone ?? FlutterTimezone.getLocalTimezone)())
            .trim();
    if (!_ianaName.hasMatch(name)) return;
    final changed =
        await container.read(settingsRepositoryProvider).syncTimezone(name);
    if (!changed) return;
    container
      ..invalidate(weeklyReportProvider)
      ..invalidate(weeklyReportListProvider)
      ..invalidate(dailyReportProvider)
      ..invalidate(dailyReportListProvider);
  } catch (_) {
    // Bir sonraki açılışta yeniden denenir.
  }
}
