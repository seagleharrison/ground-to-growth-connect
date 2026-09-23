import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'secure_storage_service.dart';

/// Direct equivalent of the native app's APIClient.swift: same endpoints,
/// same bearer-token header, same error mapping. Talks to the same
/// unmodified Go backend.
class ApiClient {
  ApiClient._();
  static final ApiClient shared = ApiClient._();

  Future<String> get _baseUrl => SecureStorageService.loadApiBaseUrl();

  Future<RegisterResponse> register(RegisterRequest payload) async {
    final json = await _request(
      path: '/api/users',
      method: 'POST',
      body: payload.toJson(),
      authenticated: false,
    );
    return RegisterResponse.fromJson(json);
  }

  /// Signs back into an existing account with only the recovery code shown
  /// once at sign-up — for a lost or replaced phone, or a changed number.
  Future<RecoverResponse> recover(String code) async {
    final json = await _request(
      path: '/api/recover',
      method: 'POST',
      body: {'code': code},
      authenticated: false,
    );
    return RecoverResponse.fromJson(json);
  }

  /// Replaces the account's recovery code (e.g. the old one was lost) and
  /// returns the new one. The old code stops working immediately.
  Future<String> regenerateRecoveryCode() async {
    final json = await _request(path: '/api/me/recovery-code', method: 'POST');
    return json['recoveryCode'] as String;
  }

  Future<User> fetchMe() async {
    final json = await _request(path: '/api/me');
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// Edits the signed-in user's own details. Only the fields passed are sent;
  /// an empty string clears an optional field (email, phone, gender), and a
  /// null field is left unchanged on the server. Passing a [personType] changes
  /// the account type; moving to a staff role also needs the [staffCode].
  Future<User> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? gender,
    String? personType,
    String? staffCode,
  }) async {
    final json = await _request(
      path: '/api/me',
      method: 'PATCH',
      body: {
        'name': ?name,
        'email': ?email,
        'phone': ?phone,
        'gender': ?gender,
        'personType': ?personType,
        'staffCode': ?staffCode,
      },
    );
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<User> putProfilePicture({required String mimeType, required String fileBase64}) async {
    final json = await _request(
      path: '/api/me/picture',
      method: 'PUT',
      body: {'mimeType': mimeType, 'fileBase64': fileBase64},
      timeout: const Duration(seconds: 60),
    );
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// The picture as base64. Only call this when the user has one.
  Future<String> fetchProfilePictureBase64() async {
    final json = await _request(path: '/api/me/picture', timeout: const Duration(seconds: 60));
    return json['fileBase64'] as String;
  }

  Future<User> deleteProfilePicture() async {
    final json = await _request(path: '/api/me/picture', method: 'DELETE');
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> deleteAccount() async {
    await _request(path: '/api/account', method: 'DELETE');
  }

  Future<DisclosureResponse> fetchDisclosure() async {
    final json = await _request(path: '/api/consent/disclosure', authenticated: false);
    return DisclosureResponse.fromJson(json);
  }

  Future<ConsentStatus> fetchConsentStatus() async {
    final json = await _request(path: '/api/consent/status');
    return ConsentStatus.fromJson(json);
  }

  Future<List<ConsentRecord>> fetchConsentHistory() async {
    final json = await _request(path: '/api/consent/history');
    return (json['records'] as List)
        .map((r) => ConsentRecord.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ConsentRecord> setConsent({required bool granted}) async {
    final json = await _request(
      path: '/api/consent',
      method: 'POST',
      body: {'granted': granted},
    );
    return ConsentRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  Future<LocationReportMeta> postLocation(LocationReportPayload payload) async {
    final json = await _request(path: '/api/locations', method: 'POST', body: payload.toJson());
    return LocationReportMeta.fromJson(json['report'] as Map<String, dynamic>);
  }

  Future<List<UserLocation>> fetchLatestLocations() async {
    final json = await _request(path: '/api/locations/latest');
    return (json['locations'] as List)
        .map((l) => UserLocation.fromJson(l as Map<String, dynamic>))
        .toList();
  }

  Future<List<MyLocationReport>> fetchMyLocations() async {
    final json = await _request(path: '/api/locations/mine');
    return (json['reports'] as List)
        .map((r) => MyLocationReport.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // MARK: - Document storage consent

  Future<DisclosureResponse> fetchDocumentDisclosure() async {
    final json = await _request(
      path: '/api/consent/documents/disclosure',
      authenticated: false,
    );
    return DisclosureResponse.fromJson(json);
  }

  Future<ConsentStatus> fetchDocumentConsentStatus() async {
    final json = await _request(path: '/api/consent/documents/status');
    return ConsentStatus.fromJson(json);
  }

  Future<List<ConsentRecord>> fetchDocumentConsentHistory() async {
    final json = await _request(path: '/api/consent/documents/history');
    return (json['records'] as List)
        .map((r) => ConsentRecord.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<ConsentRecord> setDocumentConsent({required bool granted}) async {
    final json = await _request(
      path: '/api/consent/documents',
      method: 'POST',
      body: {'granted': granted},
    );
    return ConsentRecord.fromJson(json['record'] as Map<String, dynamic>);
  }

  // MARK: - Documents

  Future<DocumentMeta> uploadDocument({
    required String documentType,
    String? label,
    required String mimeType,
    required String fileBase64,
  }) async {
    final json = await _request(
      path: '/api/documents',
      method: 'POST',
      body: {
        'documentType': documentType,
        'label': label,
        'mimeType': mimeType,
        'fileBase64': fileBase64,
      },
      timeout: const Duration(seconds: 60),
    );
    return DocumentMeta.fromJson(json['document'] as Map<String, dynamic>);
  }

  Future<List<DocumentMeta>> fetchDocuments() async {
    final json = await _request(path: '/api/documents');
    return (json['documents'] as List)
        .map((d) => DocumentMeta.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  /// Staff only. Participants with nothing on file are simply absent.
  Future<Map<String, Set<DocumentType>>> fetchDocumentsOnFile() async {
    final json = await _request(path: '/api/documents/on-file');
    return {
      for (final p in (json['participants'] as List))
        DocumentsOnFile.fromJson(p as Map<String, dynamic>).userId: DocumentsOnFile.fromJson(p).types,
    };
  }

  /// Admin only. Organization-wide totals.
  Future<Analytics> fetchAnalytics() async {
    final json = await _request(path: '/api/analytics');
    return Analytics.fromJson(json);
  }

  /// The Resources content. Public (no sign-in). Pass the [etag] of the copy you
  /// already have and an unchanged server answers "not modified" with no body.
  Future<({int status, String? body, String? etag})> fetchResources({String? etag}) async {
    final base = (await _baseUrl).replaceAll(RegExp(r'/+$'), '');
    final response = await http
        .get(Uri.parse('$base/api/resources'), headers: {
          'User-Agent': 'GroundToGrowthConnect-Flutter/0.1',
          'If-None-Match': ?etag,
        })
        .timeout(const Duration(seconds: 15));
    return (
      status: response.statusCode,
      body: response.statusCode == 200 ? response.body : null,
      etag: response.headers['etag'],
    );
  }

  /// Admin only. Official pages the Resources content points to that vanished or changed.
  Future<SourceReport> fetchSourceReport() async {
    final json = await _request(path: '/api/analytics/sources');
    return SourceReport.fromJson(json);
  }

  /// Admin only. "I checked it; the guide is still right."
  Future<SourceReport> markSourceReviewed(String url) async {
    final json = await _request(path: '/api/analytics/sources/reviewed', method: 'POST', body: {'url': url});
    return SourceReport.fromJson(json);
  }

  Future<GetDocumentResponse> fetchDocument(String id) async {
    final json = await _request(path: '/api/documents/$id', timeout: const Duration(seconds: 60));
    return GetDocumentResponse.fromJson(json);
  }

  Future<void> deleteDocument(String id) async {
    await _request(path: '/api/documents/$id', method: 'DELETE');
  }

  // MARK: - Private

  Future<Map<String, dynamic>> _request({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final base = (await _baseUrl).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'GroundToGrowthConnect-Flutter/0.1',
    };

    if (authenticated) {
      final token = await SecureStorageService.loadToken();
      if (token == null) {
        throw GgcException('Session expired. Please sign in again.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamed = await request.send().timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } catch (error) {
      throw GgcException(_couldntReachServer);
    }

    if (response.statusCode == 401) {
      throw GgcException('Session expired. Please sign in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        throw GgcException(_friendlyServerMessage(decoded['error'] as String?, response.statusCode));
      } on GgcException {
        rethrow;
      } catch (_) {
        throw GgcException(_friendlyServerMessage(null, response.statusCode));
      }
    }

    if (response.body.isEmpty) return {};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw GgcException(_somethingWentWrong);
    }
  }
}

const _couldntReachServer =
    "We can't reach Ground to Growth right now. Check your signal or Wi-Fi and try again in a moment.";
const _somethingWentWrong = 'Something went wrong on our end. Please try again in a moment.';

/// Turns the server's terse messages into something a person would want to read.
String _friendlyServerMessage(String? raw, int status) {
  final message = raw?.trim() ?? '';
  if (message.startsWith('A valid staff invite code')) {
    return "That staff code doesn't look right. Please double-check it with Ground to Growth and try again.";
  }
  if (message == 'Internal server error' || status >= 500) return _somethingWentWrong;
  if (message.contains('file too large')) {
    return 'That file is too big. Try taking the photo again a little closer, or in better light.';
  }
  if (message == 'Staff access required') return 'That part of the app is only for Ground to Growth staff.';
  if (message.isEmpty || RegExp(r'^[a-zA-Z]+ (is|are|must|cannot)\b').hasMatch(message)) {
    // Technical validation text ("mimeType must be one of...") isn't helpful to read.
    return message.startsWith('name') ? 'Please enter your name.' : _somethingWentWrong;
  }
  return message;
}
