import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/error_reporter.dart';
import '../../../core/services/supabase_providers.dart';

/// Hesap silme ya da geri bildirim başarısız oldu; [message] kullanıcıya gösterilir.
class AccountActionException implements Exception {
  const AccountActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// "Sorun bildir" kategorileri (sunucudaki check ile aynı).
enum FeedbackCategory {
  bug('hata', 'Hata'),
  idea('öneri', 'Öneri'),
  other('diğer', 'Diğer');

  const FeedbackCategory(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// Hesap silme, cihaz temizliği ve geri bildirim.
class AccountRepository {
  AccountRepository(
    this._client, {
    Future<SharedPreferences> Function()? openPrefs,
  }) : _openPrefs = openPrefs ?? SharedPreferences.getInstance;

  static const String confirmWord = 'SİL';
  static const int maxFeedback = 2000;

  /// Kullanıcıya bağlı olmayan ama kişisel sayılan cihaz anahtarları.
  static const List<String> sharedPersonalKeys = [
    'recent_food_ids',
    'stories.seen.v1',
    'checkin_dismissed_on',
    'health_nudges_disabled',
  ];

  final SupabaseClient _client;
  final Future<SharedPreferences> Function() _openPrefs;

  /// delete-account gövdesi. Apple kullanıcısında silmeden hemen önce
  /// alınan taze yetki kodu eklenir; sunucu onu Apple'da iptal eder.
  static Map<String, String> deletionBody({String? appleAuthorizationCode}) => {
        'confirm': confirmWord,
        if (appleAuthorizationCode != null && appleAuthorizationCode.isNotEmpty)
          'apple_authorization_code': appleAuthorizationCode,
      };

  /// Sunucuda hesabı ve tüm verisini siler (delete-account Edge Function).
  Future<void> deleteAccount({String? appleAuthorizationCode}) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'delete-account',
        body: deletionBody(appleAuthorizationCode: appleAuthorizationCode),
      );
    } on FunctionException catch (e) {
      throw AccountActionException(_serverMessage(e.details) ??
          'Hesap silinemedi. Bağlantını kontrol edip tekrar dene.');
    } catch (_) {
      throw const AccountActionException(
        'Hesap silinemedi. Bağlantını kontrol edip tekrar dene.',
      );
    }
    final data = response.data;
    if (data is Map && data['ok'] != true) {
      throw AccountActionException(
        _serverMessage(data) ?? 'Hesap silinemedi. Biraz sonra tekrar dene.',
      );
    }
  }

  /// Cihazda [userId] için saklanan tercihleri (`<anahtar>:<uid>`) siler.
  Future<void> clearLocalData(String userId) async {
    try {
      final prefs = await _openPrefs().timeout(const Duration(seconds: 2));
      final keys = prefs
          .getKeys()
          .where(
              (k) => k.endsWith(':$userId') || sharedPersonalKeys.contains(k))
          .toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  /// Oturum bitince (hangi yoldan olursa olsun) kullanıcı soneki olmayan
  /// kişisel tercihleri siler; aynı telefonda sonraki hesap devralmaz.
  Future<void> clearSharedPersonalKeys() async {
    try {
      final prefs = await _openPrefs().timeout(const Duration(seconds: 2));
      for (final key in sharedPersonalKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  /// "Sorun bildir": yalnızca ekleme; kullanıcı gönderdiğini sonradan okuyamaz.
  Future<void> sendFeedback({
    required String message,
    required FeedbackCategory category,
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      throw const AccountActionException('Bir şeyler yaz.');
    }
    try {
      await _client.from('feedback').insert({
        'message':
            text.length > maxFeedback ? text.substring(0, maxFeedback) : text,
        'category': category.apiValue,
        'app_version': appVersion,
      });
    } catch (_) {
      throw const AccountActionException(
        'Gönderilemedi. Bağlantını kontrol edip tekrar dene.',
      );
    }
  }

  static String? _serverMessage(Object? details) {
    if (details is Map && details['error'] is String) {
      final text = (details['error'] as String).trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(supabaseClientProvider)),
);
