import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_sync.dart';
import '../../kokpit/presentation/kokpit_providers.dart';
import '../../routines/presentation/routines_providers.dart';
import '../../settings/presentation/settings_providers.dart';
import '../data/gemini_parser_service.dart';
import '../data/quick_add_repository.dart';
import '../domain/parsed_entry.dart';
import '../domain/quick_add_mode.dart';

enum QuickAddStatus { idle, parsing, preview, saving, saved }

class QuickAddState {
  const QuickAddState({
    this.status = QuickAddStatus.idle,
    this.entry,
    this.errorMessage,
    this.savedCount = 0,
    this.otherDomain = false,
    this.otherDomainSummary,
  });

  final QuickAddStatus status;
  final ParsedEntry? entry;
  final String? errorMessage;
  final int savedCount;

  /// Son ayrıştırılan metnin tamamı ya da bir kısmı diğer giriş alanına ait.
  final bool otherDomain;
  final String? otherDomainSummary;

  bool get isBusy =>
      status == QuickAddStatus.parsing || status == QuickAddStatus.saving;

  QuickAddState copyWith({
    QuickAddStatus? status,
    ParsedEntry? entry,
    String? errorMessage,
    int? savedCount,
    bool clearEntry = false,
    bool clearOtherDomain = false,
  }) =>
      QuickAddState(
        status: status ?? this.status,
        entry: clearEntry ? null : (entry ?? this.entry),
        // Hata mesajı her geçişte sıfırlanır; yalnızca açıkça verilirse kalır.
        errorMessage: errorMessage,
        savedCount: savedCount ?? this.savedCount,
        otherDomain: !clearOtherDomain && otherDomain,
        otherDomainSummary: clearOtherDomain ? null : otherDomainSummary,
      );
}

/// Her giriş alanının kendi akışı vardır; anahtar alanın kendisidir.
final quickAddControllerProvider = NotifierProvider.autoDispose
    .family<QuickAddController, QuickAddState, QuickAddMode>(
  QuickAddController.new,
);

class QuickAddController
    extends AutoDisposeFamilyNotifier<QuickAddState, QuickAddMode> {
  @override
  QuickAddState build(QuickAddMode arg) {
    // Kayıt anında bildirim tercihi okunur; ayarlar o ana kadar yüklenmiş
    // olsun diye sayfa açılırken dinlenmeye başlanır.
    ref.listen(userSettingsProvider, (_, __) {});
    return const QuickAddState();
  }

  /// 1. adım: metni Gemini ile ayrıştır ve önizlemeye geç.
  Future<void> parse(String text) async {
    if (state.isBusy) return;
    state = state.copyWith(
      status: QuickAddStatus.parsing,
      clearEntry: true,
      clearOtherDomain: true,
    );
    try {
      final entry =
          await ref.read(geminiParserServiceProvider(arg)).parse(text);
      if (entry.isEmpty) {
        // Metin tümüyle diğer alana aitse hata değil, yönlendirme gösterilir.
        state = entry.otherDomain
            ? QuickAddState(
                otherDomain: true,
                otherDomainSummary: entry.otherDomainSummary,
              )
            : state.copyWith(
                status: QuickAddStatus.idle,
                errorMessage: 'Metinden kaydedilecek bir şey çıkaramadım. '
                    'Biraz daha açık yazar mısın?',
              );
        return;
      }
      state = QuickAddState(
        status: QuickAddStatus.preview,
        entry: entry,
        otherDomain: entry.otherDomain,
        otherDomainSummary: entry.otherDomainSummary,
      );
    } on AiParseException catch (e) {
      state = state.copyWith(
        status: QuickAddStatus.idle,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: QuickAddStatus.idle,
        errorMessage: 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Önizlemeden tek bir kalemi çıkar. Diğer alan uyarısı kalır: metnin o
  /// kısmı hâlâ kaydedilmemiştir.
  void remove(ParsedKind kind, int index) {
    final entry = state.entry;
    if (entry == null || state.isBusy) return;
    final next = entry.without(kind, index);
    state = next.isEmpty
        ? state.copyWith(status: QuickAddStatus.idle, clearEntry: true)
        : state.copyWith(entry: next);
  }

  /// Önizlemeyi kapatıp metin düzenlemeye dön.
  void backToEdit() {
    if (state.isBusy) return;
    state = state.copyWith(
      status: QuickAddStatus.idle,
      clearEntry: true,
      clearOtherDomain: true,
    );
  }

  /// 2. adım: onaylanan kalemleri tek transaction'da kaydet,
  /// saatli görevler için yerel bildirim planla, etkilenen ekranları tazele.
  Future<bool> save() async {
    final entry = state.entry;
    if (entry == null || entry.isEmpty || state.isBusy) return false;

    state = state.copyWith(status: QuickAddStatus.saving);
    try {
      final result = await ref.read(quickAddRepositoryProvider).saveAll(entry);

      // Tam eşitleme aşağıda tetiklenir ama yalnızca dinleyeni varsa çalışır;
      // saatli görev o beklenmeden hemen planlanır. Bildirimler kapalıysa
      // hiçbir şey planlanmaz.
      if (ref.read(settingsOrDefaultProvider).notificationsEnabled) {
        final notifications = ref.read(notificationServiceProvider);
        for (final task in result.tasks) {
          final when = task.remindAt;
          if (when == null) continue;
          try {
            await notifications.scheduleReminder(
              ReminderSchedule(taskId: task.id, title: task.title, when: when),
            );
          } catch (_) {
            // Bildirim planlanamasa da kayıt geçerlidir.
          }
        }
      }

      _refreshAfterSave(result);

      state = state.copyWith(
        status: QuickAddStatus.saved,
        savedCount: result.totalCount,
      );
      return true;
    } on PostgrestException catch (e) {
      state = state.copyWith(
        status: QuickAddStatus.preview,
        errorMessage: 'Kaydedilemedi: ${e.message}',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: QuickAddStatus.preview,
        errorMessage:
            'Kaydedilemedi. Bağlantını kontrol edip tekrar dene; hiçbir kayıt yazılmadı.',
      );
      return false;
    }
  }

  /// Yalnızca gerçekten yazılan türlerin beslediği sağlayıcılar tazelenir.
  void _refreshAfterSave(QuickAddResult result) {
    final wroteRoutines = result.routineCount > 0;
    final wroteTasks = result.tasks.isNotEmpty;
    final wroteHealth =
        result.nutritionCount + result.workoutCount + result.weightCount > 0;

    if (wroteRoutines) {
      ref.invalidate(activeRoutinesProvider);
      ref.invalidate(todayOccurrencesProvider);
    }
    if (wroteTasks) ref.invalidate(upcomingRemindersProvider);
    if (result.nutritionCount > 0) ref.invalidate(todayNutritionProvider);
    // Ay görünümü aylık işleri, randevuları ve sağlık ortalamalarını içerir.
    if (wroteRoutines || wroteTasks || wroteHealth) {
      ref.invalidate(monthOverviewProvider);
    }
    if (wroteRoutines || wroteTasks) ref.invalidate(notificationSyncProvider);
  }
}
