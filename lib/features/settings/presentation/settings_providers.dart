import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/avatar/avatar_spec.dart';
import '../../operations/domain/task_category.dart';
import '../data/settings_repository.dart';
import '../domain/user_settings.dart';

/// AI (Gemini) kullanımına açık onay. Okunamazsa onay yok sayılır.
final aiConsentProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(settingsRepositoryProvider).fetchAiConsent();
  } catch (_) {
    return false;
  }
});

final userSettingsProvider =
    AsyncNotifierProvider<UserSettingsNotifier, UserSettings>(
  UserSettingsNotifier.new,
);

class UserSettingsNotifier extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() => ref.watch(settingsRepositoryProvider).fetch();

  /// Veritabanına yazar ve sunucunun döndürdüğü satırı yayınlar.
  /// Hata çağırana iletilir; mevcut değer korunur.
  Future<UserSettings> save(UserSettings settings) async {
    final saved = await ref.read(settingsRepositoryProvider).save(settings);
    state = AsyncData(saved);
    return saved;
  }

  /// Yalnızca avatar seçimini yazar ve dönen satırı yayınlar.
  Future<UserSettings> saveAvatar(AvatarChoice avatar) async {
    final saved = await ref.read(settingsRepositoryProvider).saveAvatar(avatar);
    state = AsyncData(saved);
    return saved;
  }

  /// Başka bir sunucu çağrısının (ör. `complete_onboarding`) döndürdüğü
  /// satırı yeniden okumadan yayınlar.
  void adopt(UserSettings saved) => state = AsyncData(saved);

  /// Yalnızca görev kategorilerini yazar; diğer alanlar sunucudaki son
  /// değerden alınır.
  Future<UserSettings> saveTaskCategories(List<TaskCategory> categories) async {
    final current =
        state.valueOrNull ?? await ref.read(settingsRepositoryProvider).fetch();
    return save(current.copyWith(taskCategories: categories));
  }
}

/// Hedef ve tercihleri eşzamanlı okumak için: ayarlar yüklenene kadar (ya da
/// yüklenemezse) varsayılanları verir, böylece ekranlar beklemeden çizilir.
final settingsOrDefaultProvider = Provider<UserSettings>(
  (ref) =>
      ref.watch(userSettingsProvider).valueOrNull ??
      const UserSettings.defaults(),
);

/// Görev kategorileri tanımı (kapalılar dahil); ayarlar yüklenene kadar
/// yerleşik liste.
final taskCategoriesProvider = Provider<List<TaskCategory>>(
  (ref) => ref.watch(settingsOrDefaultProvider).taskCategories,
);

/// Seçici, filtre ve AI önerisinde gösterilen açık kategori adları.
final activeTaskCategoryNamesProvider = Provider<List<String>>(
  (ref) => TaskCategory.activeNames(ref.watch(taskCategoriesProvider)),
);
