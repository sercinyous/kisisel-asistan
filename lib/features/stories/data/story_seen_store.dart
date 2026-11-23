import 'package:shared_preferences/shared_preferences.dart';

/// Görülen story kartları cihazda saklanır (sunucuya gitmez).
class StorySeenStore {
  StorySeenStore({Future<SharedPreferences> Function()? openPrefs})
      : _openPrefs = openPrefs ?? SharedPreferences.getInstance;

  static const String prefsKey = 'stories.seen.v1';

  /// Saklanan en çok anahtar; eskiler baştan atılır.
  static const int maxKeys = 400;

  final Future<SharedPreferences> Function() _openPrefs;

  Future<Set<String>> load() async {
    try {
      final prefs = await _openPrefs();
      return (prefs.getStringList(prefsKey) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// [keys]'i görüldü olarak ekler; güncel kümeyi döndürür.
  Future<Set<String>> markSeen(
      Set<String> current, Iterable<String> keys) async {
    final list = [...current];
    for (final k in keys) {
      if (!current.contains(k)) list.add(k);
    }
    final trimmed =
        list.length > maxKeys ? list.sublist(list.length - maxKeys) : list;
    try {
      final prefs = await _openPrefs();
      await prefs.setStringList(prefsKey, trimmed);
    } catch (_) {
      // Saklanamazsa yalnızca bu oturumda görülmüş sayılır.
    }
    return trimmed.toSet();
  }
}
