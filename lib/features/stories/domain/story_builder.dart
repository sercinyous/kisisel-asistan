import '../../../core/avatar/avatar_spec.dart';
import '../../health/domain/goal_mode.dart';
import 'story_models.dart';

/// Günün özeti için girdiler (hepsi isteğe bağlı: veri yoksa kart çıkmaz).
class DailySummaryInput {
  const DailySummaryInput({
    required this.today,
    this.stepsToday,
    this.stepsYesterday,
    this.stepGoal,
    this.kcalToday,
    this.kcalTarget,
    this.tasksDone = 0,
    this.tasksTotal = 0,
    this.streaks = const {},
  });

  final DateTime today;
  final int? stepsToday;
  final int? stepsYesterday;
  final int? stepGoal;
  final double? kcalToday;
  final int? kcalTarget;
  final int tasksDone;
  final int tasksTotal;

  /// Seri adı → güncel gün sayısı ("Adım" → 7).
  final Map<String, int> streaks;
}

/// Bugünkü bir hatırlatma ya da rutin.
class StoryAgendaItem {
  const StoryAgendaItem({required this.title, this.time});

  final String title;
  final DateTime? time;
}

/// Başarı tespiti için girdiler.
class AchievementInput {
  const AchievementInput({
    required this.today,
    this.streaks = const {},
    this.weeklyGoalHit = false,
    this.workoutToday = false,
    this.weightGoalReached = false,
  });

  final DateTime today;

  /// Seri adı → güncel gün sayısı.
  final Map<String, int> streaks;
  final bool weeklyGoalHit;
  final bool workoutToday;
  final bool weightGoalReached;
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Binlik ayraçlı Türkçe sayı: 8240 → "8.240".
String storyNumber(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

abstract final class StoryBuilder {
  /// Günün özeti: veri olan her başlık için bir kart; hiç veri yoksa
  /// karşılama kartı (halka hiçbir zaman boş açılmaz).
  static StoryGroup dailySummary(DailySummaryInput input) {
    final slides = <StorySlide>[];
    final goal = input.stepGoal;
    if (input.stepsYesterday != null && input.stepsYesterday! > 0) {
      final y = input.stepsYesterday!;
      slides.add(StorySlide(
        id: 'steps-yesterday',
        eyebrow: 'DÜN',
        title: goal != null && y >= goal ? 'Adım hedefini tutturdun' : 'Dünkü adımların',
        value: '${storyNumber(y)} adım',
        progress: goal == null || goal <= 0 ? null : (y / goal).clamp(0, 1).toDouble(),
        tone: StoryTone.sky,
      ));
    }
    if (input.stepsToday != null && input.stepsToday! > 0) {
      final t = input.stepsToday!;
      final left = goal == null ? null : goal - t;
      slides.add(StorySlide(
        id: 'steps-today',
        eyebrow: 'BUGÜN',
        title: 'Bugünkü adımların',
        value: '${storyNumber(t)} adım',
        body: left == null
            ? null
            : left <= 0
                ? 'Hedef tamam.'
                : 'Hedefe ${storyNumber(left)} adım kaldı.',
        progress: goal == null || goal <= 0 ? null : (t / goal).clamp(0, 1).toDouble(),
        tone: StoryTone.mint,
      ));
    }
    final kcal = input.kcalToday;
    final target = input.kcalTarget;
    if (kcal != null && kcal > 0 && target != null && target > 0) {
      final left = target - kcal.round();
      slides.add(StorySlide(
        id: 'kcal',
        eyebrow: 'KALORİ',
        title: 'Bugün aldığın',
        value: '${storyNumber(kcal)} / ${storyNumber(target)} kcal',
        body: left >= 0
            ? 'Hedefin ${storyNumber(left)} kcal altındasın.'
            : 'Hedefin ${storyNumber(-left)} kcal üstündesin.',
        progress: (kcal / target).clamp(0, 1).toDouble(),
        tone: StoryTone.peach,
      ));
    }
    if (input.tasksTotal > 0) {
      final done = input.tasksDone.clamp(0, input.tasksTotal);
      slides.add(StorySlide(
        id: 'tasks',
        eyebrow: 'İŞLER',
        title: done == input.tasksTotal ? 'Bugünün işleri bitti' : 'Bugünün işleri',
        value: '$done / ${input.tasksTotal}',
        body: done == input.tasksTotal
            ? 'Hepsi tamam.'
            : '${input.tasksTotal - done} iş kaldı.',
        progress: done / input.tasksTotal,
        tone: StoryTone.lav,
      ));
    }
    final streaks = input.streaks.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (streaks.isNotEmpty) {
      slides.add(StorySlide(
        id: 'streaks',
        eyebrow: 'SERİLER',
        title: '${streaks.first.key} serin ${streaks.first.value} gün',
        value: '${streaks.first.value} gün',
        body: streaks.length > 1
            ? streaks.skip(1).map((e) => '${e.key} ${e.value} gün').join(' · ')
            : 'Zinciri bugün de sürdür.',
        tone: StoryTone.butter,
      ));
    }
    if (slides.isEmpty) {
      slides.add(const StorySlide(
        id: 'empty',
        eyebrow: 'GÜNÜN ÖZETİ',
        title: 'Bugün yeni bir sayfa',
        body: 'Bir öğün, bir yürüyüş ya da bir iş ekle; özetin burada belirsin.',
        tone: StoryTone.rose,
      ));
    }
    return StoryGroup(
      id: 'daily-${_dayKey(input.today)}',
      kind: StoryKind.daily,
      label: 'Günün özeti',
      slides: slides,
    );
  }

  /// Hedefe göre günün ipuçları ([count] adet) ve bugünün hatırlatmaları.
  static StoryGroup tips({
    required DateTime today,
    required GoalMode goal,
    List<StoryAgendaItem> agenda = const [],
    int count = 2,
  }) {
    final slides = <StorySlide>[
      for (final (i, tip) in dailyTips(goal, today, count: count).indexed)
        StorySlide(
          id: 'tip-$i',
          eyebrow: 'İPUCU · ${goal.label.toUpperCase()}',
          title: tip,
          tone: i.isEven ? StoryTone.mint : StoryTone.sky,
        ),
    ];
    final upcoming = agenda.take(4).toList();
    if (upcoming.isNotEmpty) {
      slides.add(StorySlide(
        id: 'agenda',
        eyebrow: 'BUGÜN SIRADA',
        title: upcoming.length == 1
            ? '1 hatırlatma'
            : '${upcoming.length} hatırlatma',
        body: upcoming
            .map((a) => a.time == null ? a.title : '${_hhmm(a.time!)}  ${a.title}')
            .join('\n'),
        tone: StoryTone.lav,
      ));
    }
    return StoryGroup(
      id: 'tips-${_dayKey(today)}',
      kind: StoryKind.tips,
      label: 'İpuçları',
      slides: slides,
    );
  }

  /// Günün ipuçları: hedef listesi + genel liste, yılın gününe göre döner
  /// (aynı gün hep aynı ipuçları, ertesi gün farklı).
  static List<String> dailyTips(GoalMode goal, DateTime day, {int count = 2}) {
    final pool = [...goalTips[goal]!, ...generalTips];
    final dayIndex = DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(day.year))
            .inDays +
        day.year;
    final n = count.clamp(1, pool.length);
    return [for (var i = 0; i < n; i++) pool[(dayIndex * n + i) % pool.length]];
  }

  /// Bugün yazılması gereken başarılar (seri eşiği tam bugün aşıldıysa).
  static List<PendingAchievement> detectAchievements(AchievementInput input) {
    final day = DateTime(input.today.year, input.today.month, input.today.day);
    final out = <PendingAchievement>[];
    // Birden çok seri aynı eşiğe denk gelirse türü bir kez yazılır.
    final hit = <AchievementKind, String>{};
    for (final e in input.streaks.entries) {
      final kind = AchievementKind.streakMilestones[e.value];
      if (kind != null) hit.putIfAbsent(kind, () => e.key);
    }
    for (final e in hit.entries) {
      out.add(PendingAchievement(e.key, day, {'streak': e.value}));
    }
    if (input.weeklyGoalHit) {
      // Haftada bir kez: gün olarak haftanın pazartesisi yazılır.
      out.add(PendingAchievement(
        AchievementKind.weeklyGoal,
        DateTime(day.year, day.month, day.day - (day.weekday - 1)),
      ));
    }
    if (input.workoutToday) {
      out.add(PendingAchievement(AchievementKind.workout, day));
    }
    if (input.weightGoalReached) {
      out.add(PendingAchievement(AchievementKind.weightGoal, day));
    }
    return out;
  }

  /// Bir başarının arkadaşa görünen metni.
  static StorySlide achievementSlide(FriendStory story) {
    final streak = story.payload['streak'];
    final streakName = streak is String && streak.length <= 20 ? streak : null;
    String serie(int days) =>
        streakName == null ? '$days günlük seri' : '$days günlük $streakName serisi';
    return switch (story.kind) {
      AchievementKind.streak7 => StorySlide(
          id: story.id, eyebrow: 'SERİ', title: serie(7), value: '7 gün', tone: StoryTone.butter),
      AchievementKind.streak14 => StorySlide(
          id: story.id, eyebrow: 'SERİ', title: serie(14), value: '14 gün', tone: StoryTone.peach),
      AchievementKind.streak30 => StorySlide(
          id: story.id, eyebrow: 'SERİ', title: serie(30), value: '30 gün', tone: StoryTone.rose),
      AchievementKind.weeklyGoal => StorySlide(
          id: story.id,
          eyebrow: 'HAFTA',
          title: 'Haftalık hedefini tutturdu',
          tone: StoryTone.mint),
      AchievementKind.workout => StorySlide(
          id: story.id, eyebrow: 'ANTRENMAN', title: 'Bugün antrenman yaptı', tone: StoryTone.sky),
      AchievementKind.weightGoal => StorySlide(
          id: story.id, eyebrow: 'HEDEF', title: 'Kilo hedefine ulaştı', tone: StoryTone.lav),
    };
  }

  /// Arkadaş story'lerini kişi başına bir halkada toplar (en yeni story'si
  /// olan önce). Süresi dolmuş ve arkadaş listesinde olmayanlar atlanır.
  static List<StoryGroup> friendGroups({
    required List<FriendStory> stories,
    required Map<String, ({String name, AvatarChoice avatar})> friends,
    required DateTime now,
  }) {
    final byOwner = <String, List<FriendStory>>{};
    for (final s in stories) {
      if (!s.isVisibleAt(now) || !friends.containsKey(s.ownerId)) continue;
      byOwner.putIfAbsent(s.ownerId, () => []).add(s);
    }
    final groups = [
      for (final e in byOwner.entries)
        () {
          final list = [...e.value]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final f = friends[e.key]!;
          return StoryGroup(
            id: 'friend-${e.key}',
            kind: StoryKind.friend,
            label: f.name,
            friendId: e.key,
            avatar: f.avatar,
            stories: list,
            slides: [for (final s in list) achievementSlide(s)],
          );
        }(),
    ];
    groups.sort((a, b) => b.stories.last.createdAt.compareTo(a.stories.last.createdAt));
    return groups;
  }

  /// Hedef türüne göre kısa, güvenli ipuçları (tıbbi iddia yok).
  static const Map<GoalMode, List<String>> goalTips = {
    GoalMode.fatLoss: [
      'Öğünlerine bir avuç sebze eklemek tabağı doyurucu yapar.',
      'Akşam yürüyüşü günün adımlarını kolayca artırır.',
      'Atıştırmalığı tabağa koyup yemek, ne kadar yediğini görmeni sağlar.',
      'Haftalık ortalamaya bak; tek günlük tartı her şeyi anlatmaz.',
      'Öğünü yavaş yemek, doyduğunu fark etmeye zaman tanır.',
    ],
    GoalMode.recomp: [
      'Her öğüne bir protein kaynağı eklemeyi dene.',
      'Antrenman günlerini takvime önceden yazmak devamlılığı kolaylaştırır.',
      'Ölçü ve fotoğraf, tartıdan fazlasını gösterebilir.',
      'Uyku düzeni, ertesi günün antrenman isteğini etkiler.',
      'Ağırlıkları kademeli artırmak ilerlemeyi takip etmeyi kolaylaştırır.',
    ],
    GoalMode.leanGain: [
      'Öğün sayısını düzenli tutmak hedef kaloriye ulaşmayı kolaylaştırır.',
      'Antrenman sonrası bir öğünü planlamak işini kolaylaştırır.',
      'Kaldırdığın ağırlıkları not almak gelişimi görünür yapar.',
      'Doyurucu ama hafif atıştırmalıklar gün içinde yardımcı olur.',
      'Dinlenme günleri de programın bir parçası.',
    ],
    GoalMode.maintain: [
      'Haftada birkaç kez tartılmak dengeyi izlemeyi kolaylaştırır.',
      'Sevdiğin bir hareketi rutine katmak sürdürmeyi kolaylaştırır.',
      'Öğün saatlerini benzer tutmak günü düzenler.',
      'Hafta sonu da küçük bir yürüyüş planla.',
      'Tabağının yarısını sebzeyle doldurmayı dene.',
    ],
  };

  static const List<String> generalTips = [
    'Gün içinde bir şişe suyu yanında tutmak içmeyi hatırlatır.',
    'Uzun oturduysan birkaç dakika kalkıp esne.',
    'Yarının en önemli işini bu akşam not al.',
    'Telefonu yatmadan biraz önce bırakmak akşamı sakinleştirir.',
    'Küçük bir hedef koy ve tamamlayınca işaretle.',
  ];
}
