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

  Future<User> fetchMe() async {
    final json = await _request(path: '/api/me');
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// Edits the signed-in user's own details. Only the fields passed are sent;
  /// an empty string clears an optional field (email, phone, gender), and a
  /// null field is left unchanged on the server.
  Future<User> updateProfile({String? name, String? email, String? phone, String? gender}) async {
    final json = await _request(
      path: '/api/me',
      method: 'PATCH',
      body: {
        'name': ?name,
        'email': ?email,
        'phone': ?phone,
        'gender': ?gender,
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
      throw GgcException('Network error: $error');
    }

    if (response.statusCode == 401) {
      throw GgcException('Session expired. Please sign in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        throw GgcException(decoded['error'] as String? ?? 'Request failed (${response.statusCode}).');
      } on GgcException {
        rethrow;
      } catch (_) {
        throw GgcException('Request failed (${response.statusCode}).');
      }
    }

    if (response.body.isEmpty) return {};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw GgcException('Unexpected response from server.');
    }
  }
}
