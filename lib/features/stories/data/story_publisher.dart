import '../../settings/domain/user_settings.dart';
import '../domain/story_models.dart';
import 'stories_repository.dart';

/// Başarıları arkadaşlara yazar. Gizlilik: "Başarılarımı story olarak
/// paylaş" kapalıysa (varsayılan) ya da sütun şemada yoksa HİÇBİR şey
/// yazılmaz. Aynı tür + gün bu oturumda bir kez denenir (sunucu da tekil).
class StoryPublisher {
  StoryPublisher(this._repository);

  final StoriesRepository _repository;
  final Set<String> _sent = {};

  /// Yazılan (denenen) başarı sayısı.
  Future<int> publish(
    UserSettings settings,
    List<PendingAchievement> candidates,
  ) async {
    if (!settings.shareStories || !settings.shareStoriesColumn) {
      // Kapatınca sunucu story'leri siler; yeniden açınca bugünküler tekrar
      // yazılabilsin diye oturum hafızası da temizlenir.
      _sent.clear();
      return 0;
    }
    var written = 0;
    for (final c in candidates) {
      if (!_sent.add(c.dedupeKey)) continue;
      try {
        await _repository.publish(c);
        written++;
      } catch (_) {
        // Ağ hatasında bir sonraki açılışta yeniden denensin.
        _sent.remove(c.dedupeKey);
      }
    }
    return written;
  }
}
