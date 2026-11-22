/// Arkadaşlık sözleşmesi modelleri (Faz 4B). Arkadaş verisi yalnızca
/// `friend_goal_summary` RPC'sinden gelir: tarih ya da ham değer yoktur.
library;

import '../../../core/avatar/avatar_spec.dart';

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
    this.avatar = const AvatarChoice(),
  });

  factory Friend.fromMap(Map<String, dynamic> m) => Friend(
        avatar: AvatarChoice.fromMap(m),
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

  /// Arkadaşın avatar seçimi (`my_friends` RPC'si).
  final AvatarChoice avatar;
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
/// `share*` hedef paylaşımıdır: arkadaşlar yalnızca hedefi tutturulan gün
/// sayısını görür. [shareDetails] ayrı, açık onaydır: hedef paylaşımı açık
/// metriklerin ham değerlerini ([detailValueLabels]) açar. Sunucu onaysız
/// ham değeri arkadaşa null döndürür (`friend_leaderboard`).
class FriendSharing {
  const FriendSharing({
    this.shareSteps = false,
    this.shareSleep = false,
    this.shareCalories = false,
    this.shareDetails = false,
  });

  factory FriendSharing.fromMap(Map<String, dynamic>? m) => m == null
      ? const FriendSharing()
      : FriendSharing(
          shareSteps: (m['share_steps'] as bool?) ?? false,
          shareSleep: (m['share_sleep'] as bool?) ?? false,
          shareCalories: (m['share_calories'] as bool?) ?? false,
          shareDetails: (m['share_details'] as bool?) ?? false,
        );

  final bool shareSteps;
  final bool shareSleep;
  final bool shareCalories;
  final bool shareDetails;

  bool get sharesAnyGoal => shareSteps || shareSleep || shareCalories;

  /// Ayrıntı onayıyla arkadaşlara açılacak ham değerler (hedef paylaşımı
  /// açık metrikler için).
  List<String> get detailValueLabels => [
        if (shareSteps) 'Bugünkü ve bu haftaki toplam adım sayın',
        if (shareSleep) 'Bugünkü uyku süren ve bu haftaki ortalaman',
        if (shareCalories) 'Bugün ve bu hafta yediğin toplam kalori (kcal)',
      ];

  FriendSharing copyWith({
    bool? steps,
    bool? sleep,
    bool? calories,
    bool? details,
  }) =>
      FriendSharing(
        shareSteps: steps ?? shareSteps,
        shareSleep: sleep ?? shareSleep,
        shareCalories: calories ?? shareCalories,
        shareDetails: details ?? shareDetails,
      );

  Map<String, dynamic> toMap(String userId) => {
        'user_id': userId,
        'share_steps': shareSteps,
        'share_sleep': shareSleep,
        'share_calories': shareCalories,
        'share_details': shareDetails,
      };
}

class FriendWithSummary {
  const FriendWithSummary({required this.friend, required this.summaries});

  final Friend friend;
  final List<GoalSummary> summaries;
}

/// Sıralama dönemi.
enum RankPeriod {
  today('Bugün'),
  week('Bu hafta');

  const RankPeriod(this.label);
  final String label;
}

/// `friend_leaderboard` satırı: kabul edilmiş arkadaş ya da kişinin kendisi.
/// Değerler yalnızca toplanmış sayılardır; paylaşılmayan metrik null gelir.
/// Arkadaşın ham değeri yalnızca hedef paylaşımı VE ayrıntı onayı açıkken
/// doludur; yalnızca hedef paylaşımı açıksa null gelir ve arayüz hedef gün
/// sayısını ([GoalSummary]) gösterir.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.isSelf,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    this.stepsToday,
    this.stepsWeek,
    this.sleepToday,
    this.sleepWeekAvg,
    this.kcalToday,
    this.kcalWeek,
    this.avatar = const AvatarChoice(),
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> m) {
    final email = (m['email'] as String?) ?? '';
    final name = ((m['display_name'] as String?) ?? '').trim();
    final avatar = ((m['avatar_url'] as String?) ?? '').trim();
    return LeaderboardEntry(
      userId: m['user_id'] as String,
      isSelf: (m['is_self'] as bool?) ?? false,
      displayName: name.isEmpty ? email : name,
      email: email,
      avatarUrl: avatar.isEmpty ? null : avatar,
      stepsToday: _num(m['steps_today']),
      stepsWeek: _num(m['steps_week']),
      sleepToday: _num(m['sleep_today']),
      sleepWeekAvg: _num(m['sleep_week_avg']),
      kcalToday: _num(m['kcal_today']),
      kcalWeek: _num(m['kcal_week']),
      avatar: AvatarChoice.fromMap(m),
    );
  }

  static num? _num(Object? v) => switch (v) {
        num n => n,
        String s => num.tryParse(s),
        _ => null,
      };

  final String userId;
  final bool isSelf;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final num? stepsToday;
  final num? stepsWeek;
  final num? sleepToday;
  final num? sleepWeekAvg;
  final num? kcalToday;
  final num? kcalWeek;

  /// Avatar seçimi (`friend_leaderboard` RPC'si); [avatarUrl] yalnızca baş
  /// harf türünde Google profil resmi olarak kullanılır.
  final AvatarChoice avatar;

  /// Seçilen metrik ve dönemin değeri; paylaşılmıyorsa null.
  num? value(GoalMetric metric, RankPeriod period) =>
      switch ((metric, period)) {
        (GoalMetric.steps, RankPeriod.today) => stepsToday,
        (GoalMetric.steps, RankPeriod.week) => stepsWeek,
        (GoalMetric.sleep, RankPeriod.today) => sleepToday,
        (GoalMetric.sleep, RankPeriod.week) => sleepWeekAvg,
        (GoalMetric.calories, RankPeriod.today) => kcalToday,
        (GoalMetric.calories, RankPeriod.week) => kcalWeek,
      };

  /// Ad soyadın baş harfleri (fotoğraf yoksa).
  String get initials => initialsFor(displayName);
}

/// En iyi değer önce; paylaşılmayanlar sona, eşitlikte ada göre.
List<LeaderboardEntry> rankEntries(
  List<LeaderboardEntry> entries,
  GoalMetric metric,
  RankPeriod period,
) {
  final list = [...entries];
  list.sort((a, b) {
    final va = a.value(metric, period);
    final vb = b.value(metric, period);
    if (va == null && vb != null) return 1;
    if (vb == null && va != null) return -1;
    if (va != null && vb != null && va != vb) return vb.compareTo(va);
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return list;
}

/// Metrik değerinin Türkçe gösterimi.
/// Ham değeri paylaşılmayan arkadaş için hedef gün sayısı metni ("3/5 gün
/// hedef"); hedef de paylaşılmıyorsa null.
String? formatGoalDays(GoalSummary? s) {
  if (s == null || !s.shared) return null;
  return '${s.goalDays}/${s.dataDays} gün hedef';
}

String formatMetricValue(GoalMetric metric, RankPeriod period, num? v) {
  if (v == null) return 'paylaşmıyor';
  String grouped(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return n < 0 ? '-$b' : b.toString();
  }

  switch (metric) {
    case GoalMetric.steps:
      return '${grouped(v.round())} adım';
    case GoalMetric.calories:
      return '${grouped(v.round())} kcal';
    case GoalMetric.sleep:
      final m = v.round();
      final text = '${m ~/ 60} sa ${(m % 60).toString().padLeft(2, '0')} dk';
      return period == RankPeriod.week ? 'ort. $text' : text;
  }
}
