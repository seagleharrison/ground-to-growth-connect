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

  static Future<void> clearSession() async {
    await deleteToken();
    await deleteUser();
  }
}
