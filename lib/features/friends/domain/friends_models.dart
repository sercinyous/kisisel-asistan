/// Arkadaşlık sözleşmesi modelleri (Faz 4B). Arkadaş verisi yalnızca
/// `friend_goal_summary` RPC'sinden gelir: tarih ya da ham değer yoktur.
library;

/// Haftanın Pazartesi'si (yalnızca tarih, saat 00:00).
DateTime weekStartOf(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

/// RPC `week_start` parametresi biçimi: yyyy-MM-dd.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class IncomingRequest {
  const IncomingRequest({
    required this.id,
    required this.fromName,
    required this.createdAt,
  });

  factory IncomingRequest.fromMap(Map<String, dynamic> m) => IncomingRequest(
        id: m['id'] as String,
        fromName: (m['from_name'] as String?) ?? '',
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  final String id;
  final String fromName;
  final DateTime createdAt;
}

class OutgoingRequest {
  const OutgoingRequest({
    required this.id,
    required this.targetEmail,
    required this.createdAt,
  });

  factory OutgoingRequest.fromMap(Map<String, dynamic> m) => OutgoingRequest(
        id: m['id'] as String,
        targetEmail: (m['target_email'] as String?) ?? '',
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  final String id;
  final String targetEmail;
  final DateTime createdAt;
}

class Friend {
  const Friend({
    required this.friendId,
    required this.displayName,
    required this.shareSteps,
    required this.shareSleep,
    required this.shareCalories,
  });

  factory Friend.fromMap(Map<String, dynamic> m) => Friend(
        friendId: m['friend_id'] as String,
        displayName: (m['display_name'] as String?) ?? '',
        shareSteps: (m['share_steps'] as bool?) ?? false,
        shareSleep: (m['share_sleep'] as bool?) ?? false,
        shareCalories: (m['share_calories'] as bool?) ?? false,
      );

  final String friendId;
  final String displayName;
  final bool shareSteps;
  final bool shareSleep;
  final bool shareCalories;
}

enum GoalMetric {
  steps('steps', 'Adım'),
  sleep('sleep', 'Uyku'),
  calories('calories', 'Kalori');

  const GoalMetric(this.key, this.label);
  final String key;
  final String label;

  static GoalMetric? fromKey(String? key) {
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

class GoalSummary {
  const GoalSummary({
    required this.metric,
    required this.shared,
    required this.goalDays,
    required this.dataDays,
  });

  factory GoalSummary.fromMap(Map<String, dynamic> m) => GoalSummary(
        metric: GoalMetric.fromKey(m['metric'] as String?),
        shared: (m['shared'] as bool?) ?? false,
        goalDays: (m['goal_days'] as num?)?.toInt() ?? 0,
        dataDays: (m['data_days'] as num?)?.toInt() ?? 0,
      );

  /// Bilinmeyen metrik null olur ve arayüzde atlanır.
  final GoalMetric? metric;
  final bool shared;
  final int goalDays;
  final int dataDays;
}

/// Kişinin kendi paylaşım anahtarları (`friend_sharing`); varsayılan kapalı.
class FriendSharing {
  const FriendSharing({
    this.shareSteps = false,
    this.shareSleep = false,
    this.shareCalories = false,
  });

  factory FriendSharing.fromMap(Map<String, dynamic>? m) => m == null
      ? const FriendSharing()
      : FriendSharing(
          shareSteps: (m['share_steps'] as bool?) ?? false,
          shareSleep: (m['share_sleep'] as bool?) ?? false,
          shareCalories: (m['share_calories'] as bool?) ?? false,
        );

  final bool shareSteps;
  final bool shareSleep;
  final bool shareCalories;

  FriendSharing copyWith({bool? steps, bool? sleep, bool? calories}) =>
      FriendSharing(
        shareSteps: steps ?? shareSteps,
        shareSleep: sleep ?? shareSleep,
        shareCalories: calories ?? shareCalories,
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'share_steps': shareSteps,
        'share_sleep': shareSleep,
        'share_calories': shareCalories,
      };
}

class FriendWithSummary {
  const FriendWithSummary({required this.friend, required this.summaries});

  final Friend friend;
  final List<GoalSummary> summaries;
}
