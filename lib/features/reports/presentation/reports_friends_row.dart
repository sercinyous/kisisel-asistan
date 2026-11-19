import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../friends/domain/friends_models.dart';
import '../../friends/presentation/friends_providers.dart';
import '../../friends/presentation/friends_screen.dart';
import 'reports_widgets.dart';

/// Arkadaşlar arasında bu haftaki sıra (haftalık adım); 1'den başlar.
/// Arkadaş yoksa ya da kişinin kendi satırı yoksa `null`.
int? weeklyFriendRank(List<LeaderboardEntry> entries) {
  if (!entries.any((e) => !e.isSelf)) return null;
  final ranked = rankEntries(entries, GoalMetric.steps, RankPeriod.week);
  final index = ranked.indexWhere((e) => e.isSelf);
  return index < 0 ? null : index + 1;
}

/// Tek satır: "Arkadaşlar · bu hafta N. sıradasın ›". Arkadaş yoksa, veri
/// yüklenirken ya da hata varsa hiç yer kaplamaz.
class ReportsFriendsRow extends ConsumerWidget {
  const ReportsFriendsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(friendsLeaderboardProvider).valueOrNull;
    final rank = entries == null ? null : weeklyFriendRank(entries);
    if (rank == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ReportLinkRow(
        key: const ValueKey('reports-friends'),
        icon: Icons.people_alt_rounded,
        label: 'Arkadaşlar · bu hafta $rank. sıradasın',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FriendsScreen()),
        ),
      ),
    );
  }
}
