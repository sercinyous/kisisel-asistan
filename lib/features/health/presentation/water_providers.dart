import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_utils.dart';
import '../data/water_repository.dart';

export '../data/water_repository.dart';

/// Bugünün su kayıtları ve günlük hedef.
class WaterToday {
  const WaterToday({
    required this.day,
    required this.logs,
    required this.targetMl,
  });

  final DateTime day;
  final List<WaterLog> logs;
  final int targetMl;

  int get totalMl => waterTotalForDay(logs, day);
  double get progress => waterProgress(totalMl, targetMl);
  bool get canUndo => logs.isNotEmpty;

  WaterToday copyWith({List<WaterLog>? logs}) =>
      WaterToday(day: day, logs: logs ?? this.logs, targetMl: targetMl);
}

/// Sağlık kartı ve Kokpit özeti aynı durumu paylaşır.
final waterTodayProvider =
    AsyncNotifierProvider<WaterTodayNotifier, WaterToday>(
  WaterTodayNotifier.new,
);

class WaterTodayNotifier extends AsyncNotifier<WaterToday> {
  @override
  Future<WaterToday> build() async {
    final repo = ref.watch(waterRepositoryProvider);
    final day = AppDates.startOfDay(DateTime.now());
    final results = await Future.wait<Object>([
      repo.fetchDay(day),
      repo.fetchDailyTarget(),
    ]);
    return WaterToday(
      day: day,
      logs: results[0] as List<WaterLog>,
      targetMl: results[1] as int,
    );
  }

  /// [ml] ekler. Gün değiştiyse önce yeniden yüklenir.
  Future<void> add(int ml) => _serial(() => _add(ml));

  /// Su işlemlerini sıraya alır: hızlı art arda dokunuşlar birbirinin
  /// sonucunu ezmez (her işlem öncekinin bitmesini bekler).
  Future<void> _queue = Future.value();
  Future<void> _serial(Future<void> Function() op) {
    final next = _queue.catchError((_) {}).then((_) => op());
    _queue = next;
    return next;
  }

  Future<void> _add(int ml) async {
    var current = await future;
    final today = AppDates.startOfDay(DateTime.now());
    if (current.day != today) {
      ref.invalidateSelf();
      current = await future;
    }
    final log = await ref.read(waterRepositoryProvider).add(current.day, ml);
    final latest = state.valueOrNull ?? current;
    state = AsyncData(latest.copyWith(logs: [...latest.logs, log]));
  }

  /// Günlük hedefi [ml] yapar (Plan > Rehber "Hedefi … yap").
  Future<void> setTarget(int ml) async {
    final current = await future;
    await ref.read(waterRepositoryProvider).setDailyTarget(ml);
    state = AsyncData(
        WaterToday(day: current.day, logs: current.logs, targetMl: ml));
  }

  /// Bugünün son kaydını siler; kayıt yoksa bir şey yapmaz.
  Future<void> undo() => _serial(_undo);

  Future<void> _undo() async {
    final current = await future;
    if (current.logs.isEmpty) return;
    final last = current.logs.last;
    await ref.read(waterRepositoryProvider).delete(last.id);
    final latest = state.valueOrNull ?? current;
    state = AsyncData(latest.copyWith(
        logs: [for (final l in latest.logs) if (l.id != last.id) l]));
  }
}
