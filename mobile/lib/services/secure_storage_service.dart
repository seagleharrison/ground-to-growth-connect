import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// Direct equivalent of the native app's KeychainService: Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android, via flutter_secure_storage.
class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _apiUrlKey = 'api_base_url';

  /// Builds shipped to phones (TestFlight/App Store) talk to the real server;
  /// on a phone "127.0.0.1" is the phone itself, so it can never work there.
  /// Debug builds keep pointing at the backend running on this Mac.
  static const defaultApiBaseUrl =
      kReleaseMode ? 'https://api.groundtogrowth.org' : 'http://127.0.0.1:3001';

  static Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  static Future<String?> loadToken() => _storage.read(key: _tokenKey);

  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  static Future<void> saveUser(User user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  static Future<User?> loadUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteUser() => _storage.delete(key: _userKey);

  static Future<void> saveApiBaseUrl(String url) => _storage.write(key: _apiUrlKey, value: url);

  static Future<String> loadApiBaseUrl() async =>
      await _storage.read(key: _apiUrlKey) ?? defaultApiBaseUrl;

  /// Documents this person marked "I don't have this", remembered on this phone
  /// only. It's just a display preference, so it isn't sent to the server.
  static String _hiddenKey(String userId) => 'hidden_documents_$userId';

  static Future<void> saveHiddenDocuments(String userId, Set<DocumentType> hidden) =>
      _storage.write(key: _hiddenKey(userId), value: [for (final t in hidden) t.wireValue].join(','));

  static Future<Set<DocumentType>> loadHiddenDocuments(String userId) async {
    final raw = await _storage.read(key: _hiddenKey(userId));
    if (raw == null || raw.isEmpty) return {};
    return {for (final w in raw.split(',')) DocumentType.fromWire(w)}..remove(DocumentType.other);
  }

  static Future<void> deleteHiddenDocuments(String userId) => _storage.delete(key: _hiddenKey(userId));

  /// The last Resources content fetched from the server, so it still shows
  /// (and is the newest we have) when there's no signal.
  static Future<void> saveResourcesCache({required String json, String? etag}) async {
    await _storage.write(key: 'resources_json', value: json);
    if (etag != null) await _storage.write(key: 'resources_etag', value: etag);
  }

  static Future<({String json, String? etag})?> loadResourcesCache() async {
    final json = await _storage.read(key: 'resources_json');
    if (json == null) return null;
    return (json: json, etag: await _storage.read(key: 'resources_etag'));
  }

  static Future<void> clearSession() async {
    await deleteToken();
    await deleteUser();
  }
}
