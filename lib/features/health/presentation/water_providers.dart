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
  Future<void> add(int ml) async {
    var current = await future;
    final today = AppDates.startOfDay(DateTime.now());
    if (current.day != today) {
      ref.invalidateSelf();
      current = await future;
    }
    final log = await ref.read(waterRepositoryProvider).add(current.day, ml);
    state = AsyncData(current.copyWith(logs: [...current.logs, log]));
  }

  /// Bugünün son kaydını siler; kayıt yoksa bir şey yapmaz.
  Future<void> undo() async {
    final current = await future;
    if (current.logs.isEmpty) return;
    final last = current.logs.last;
    await ref.read(waterRepositoryProvider).delete(last.id);
    state = AsyncData(
      current.copyWith(logs: current.logs.sublist(0, current.logs.length - 1)),
    );
  }
}
