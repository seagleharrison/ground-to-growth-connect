import 'dart:convert';

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

/// An in-memory stand-in for the Go backend, covering just the endpoints the
/// profile and document screens use. It lets widget tests drive the real
/// screens and the real ApiClient/AppState code without a network.
///
/// The real server is covered by the Go test suite; this checks that the app
/// sends the right requests and reacts correctly to the responses.
/// A real 1x1 PNG, so widgets that display a picture can decode it.
const tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class FakeApi {
  Map<String, dynamic> user = {
    'id': 'u1',
    'personType': 'homeless',
    'name': 'Jane Doe',
    'email': 'jane@example.org',
    'phone': '912-555-0100',
    'gender': 'female',
    'isStaff': false,
    'hasProfilePicture': false,
  };
  final List<Map<String, dynamic>> documents = [];

  /// What GET /api/locations/latest returns to a staff viewer.
  List<Map<String, dynamic>> staffLocations = [];

  /// What GET /api/documents/on-file returns to a staff viewer: [{userId, documentTypes}].
  List<Map<String, dynamic>> documentsOnFile = [];
  int analyticsRequests = 0;

  /// Every non-tile request the app made, as "METHOD /path", in order.
  final List<String> routes = [];

  /// What GET /api/resources returns; null answers 404 (as if the server had no content).
  String? resourcesBody;
  String resourcesEtag = '"v1"';
  int resourcesRequests = 0;
  String? lastIfNoneMatch;
  bool failResources = false;

  /// What GET /api/events returns; null answers 404, same shape as resources above.
  String? eventsBody;
  // Derived from the actual content, not a fixed string: the secure-storage
  // mock persists across tests in the same file, so a constant etag here
  // would 304 a later test into showing an earlier test's cached content.
  String get eventsEtag => '"${eventsBody.hashCode}"';
  int eventsRequests = 0;
  String? lastEventsIfNoneMatch;

  /// This person's own appointments (private — see /api/appointments*).
  final List<Map<String, dynamic>> appointments = [];
  int _nextAppointmentId = 1;

  /// What GET /api/analytics/sources returns for an admin.
  List<Map<String, dynamic>> flaggedSources = [];
  List<Map<String, dynamic>> blockedSources = [];
  int totalSources = 12;

  /// When true, GET /api/analytics fails as if the server were unreachable.
  bool failAnalytics = false;
  final List<Map<String, dynamic>> patchBodies = [];
  final List<Map<String, dynamic>> uploadBodies = [];

  /// When set, POST /api/documents fails with this error message.
  String? failUploadsWith;

  /// The staff invite code this fake accepts when switching to a staff role.
  static const staffCode = 'g2g-test';

  /// When set, PATCH /api/me fails with this error message.
  String? failProfileUpdateWith;

  /// Whether this account currently has location sharing on, and its history
  /// of turning it on/off. Backs GET/POST /api/consent*.
  bool locationConsentGranted = false;
  final List<Map<String, dynamic>> locationConsentRecords = [];

  String? pictureBase64;
  String? pictureMime;

  /// The current recovery code for this account. Tests can set it before
  /// registering/recovering; POST /api/me/recovery-code replaces it.
  String recoveryCode = 'G7K4-9XPQ-3RTM';
  int recoveryCodeRegenerations = 0;

  /// When set, POST /api/users fails with this error message and status.
  String? failRegisterWith;
  int failRegisterStatus = 400;

  late final MockClient client = MockClient(_handle);

  /// Only for taking design screenshots: lets real map tiles download instead
  /// of answering "not found". Off in the automated tests.
  static bool passThroughMapTiles = false;
  static final IOClient _realNetwork = IOClient(HttpClient());

  Future<http.Response> _handle(http.Request request) async {
    if (passThroughMapTiles && request.url.host.endsWith('openstreetmap.org')) {
      final forwarded = http.Request(request.method, request.url)
        ..headers['user-agent'] = request.headers['user-agent'] ?? 'GroundToGrowthConnect-test';
      return http.Response.fromStream(await _realNetwork.send(forwarded));
    }
    final route = '${request.method} ${request.url.path}';
    routes.add(route);

    if (route == 'POST /api/users') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (failRegisterWith != null) return _json({'error': failRegisterWith}, status: failRegisterStatus);
      final name = (body['name'] as String? ?? '').trim();
      if (name.isEmpty) return _json({'error': 'name is required'}, status: 400);
      final phone = (body['phone'] as String? ?? '').trim();
      if (phone.isEmpty) return _json({'error': 'phone is required'}, status: 400);
      final personType = (body['personType'] as String?) ?? 'homeless';
      if (personType != 'homeless' && body['staffCode'] != staffCode) {
        return _json({'error': 'A valid staff invite code is required for staff accounts.'}, status: 403);
      }
      user = {
        'id': 'u1',
        'personType': personType,
        'name': name,
        'email': (body['email'] as String?)?.isEmpty == true ? null : body['email'],
        'phone': phone,
        'gender': body['gender'],
        'isStaff': personType != 'homeless',
        'hasProfilePicture': false,
      };
      return _json({'user': user, 'token': 'tok-${user['id']}', 'recoveryCode': recoveryCode}, status: 201);
    }

    if (route == 'POST /api/recover') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final entered = _normalizeCode(body['code'] as String? ?? '');
      if (entered.isEmpty) return _json({'error': 'code is required'}, status: 400);
      if (entered != _normalizeCode(recoveryCode)) {
        return _json({'error': "That recovery code doesn't match any account."}, status: 404);
      }
      return _json({'user': user, 'token': 'tok-recovered'});
    }

    if (route == 'POST /api/me/recovery-code') {
      recoveryCodeRegenerations++;
      recoveryCode = 'NEW$recoveryCodeRegenerations-CODE-CODE';
      return _json({'recoveryCode': recoveryCode});
    }

    // GET /api/documents/{id}: hand back the stored file (a real 1x1 PNG).
    final docMatch = RegExp(r'^/api/documents/(d\d+)$').firstMatch(request.url.path);
    if (request.method == 'GET' && docMatch != null) {
      final doc = documents.where((d) => d['id'] == docMatch.group(1)).firstOrNull;
      if (doc == null) return _json({'error': 'Not found'}, status: 404);
      return _json({'document': doc, 'fileBase64': tinyPngBase64});
    }

    // PATCH/DELETE /api/appointments/{id}
    final apptMatch = RegExp(r'^/api/appointments/(a\d+)$').firstMatch(request.url.path);
    if (apptMatch != null) {
      final id = apptMatch.group(1);
      final existing = appointments.where((a) => a['id'] == id).firstOrNull;
      if (existing == null) return _json({'error': 'Not found'}, status: 404);
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        for (final key in ['title', 'notes', 'location', 'startsAt']) {
          if (body.containsKey(key)) existing[key] = body[key];
        }
        return _json({'appointment': existing});
      }
      if (request.method == 'DELETE') {
        appointments.removeWhere((a) => a['id'] == id);
        return _json({'deleted': true});
      }
    }

    switch (route) {
      case 'GET /api/me':
        return _json({'user': user});
      case 'PATCH /api/me':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        patchBodies.add(body);
        if (failProfileUpdateWith != null) {
          return _json({'error': failProfileUpdateWith}, status: 400);
        }
        final requestedType = body['personType'] as String?;
        if (requestedType != null && requestedType != user['personType']) {
          if (requestedType != 'homeless' && body['staffCode'] != staffCode) {
            return _json({'error': 'A valid staff invite code is required for staff accounts.'}, status: 403);
          }
          user['personType'] = requestedType;
          user['isStaff'] = requestedType != 'homeless';
        }
        for (final field in ['name', 'email', 'phone', 'gender']) {
          if (!body.containsKey(field)) continue;
          final value = (body[field] as String).trim();
          user[field] = value.isEmpty ? null : value;
        }
        return _json({'user': user});
      case 'PUT /api/me/picture':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        pictureBase64 = body['fileBase64'] as String;
        pictureMime = body['mimeType'] as String;
        user['hasProfilePicture'] = true;
        return _json({'user': user});
      case 'GET /api/me/picture':
        if (pictureBase64 == null) return _json({'error': 'No profile picture'}, status: 404);
        return _json({'mimeType': pictureMime, 'fileBase64': pictureBase64});
      case 'DELETE /api/me/picture':
        pictureBase64 = null;
        pictureMime = null;
        user['hasProfilePicture'] = false;
        return _json({'user': user});
      case 'GET /api/analytics':
        analyticsRequests++;
        if (failAnalytics) return _json({'error': 'Internal server error'}, status: 500);
        if (user['personType'] != 'admin') return _json({'error': 'Admin access required'}, status: 403);
        return _json({
          'generatedAt': '2026-09-21T12:00:00.000Z',
          'people': {'participants': 40, 'volunteers': 5, 'admins': 2},
          'sharing': {'participantsSharing': 30, 'activeLast24Hours': 18, 'activeLast7Days': 27},
          'documents': {'participantsUsingStorage': 22, 'participantsWithAllThree': 9, 'documentsStored': 61},
          'daily': [
            for (var i = 0; i < 14; i++)
              {'date': '2026-09-${(8 + i).toString().padLeft(2, '0')}', 'signups': i == 13 ? 2 : 0, 'checkIns': i * 3},
          ],
        });
      case 'GET /api/resources':
        resourcesRequests++;
        lastIfNoneMatch = request.headers['if-none-match'];
        if (failResources) return http.Response('boom', 500);
        if (resourcesBody == null) return http.Response('{"error":"Not found"}', 404);
        if (lastIfNoneMatch == resourcesEtag) return http.Response('', 304, headers: {'etag': resourcesEtag});
        return http.Response(resourcesBody!, 200, headers: {'content-type': 'application/json', 'etag': resourcesEtag});
      case 'GET /api/events':
        eventsRequests++;
        lastEventsIfNoneMatch = request.headers['if-none-match'];
        if (eventsBody == null) return http.Response('{"error":"Not found"}', 404);
        if (lastEventsIfNoneMatch == eventsEtag) return http.Response('', 304, headers: {'etag': eventsEtag});
        return http.Response(eventsBody!, 200, headers: {'content-type': 'application/json', 'etag': eventsEtag});
      case 'GET /api/appointments':
        return _json({'appointments': appointments});
      case 'POST /api/appointments':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final appt = {
          'id': 'a${_nextAppointmentId++}',
          'title': body['title'],
          'notes': (body['notes'] as String?)?.isEmpty == true ? null : body['notes'],
          'location': (body['location'] as String?)?.isEmpty == true ? null : body['location'],
          'startsAt': body['startsAt'],
          'createdAt': '2026-09-26T12:00:00.000Z',
        };
        appointments.add(appt);
        return _json({'appointment': appt}, status: 201);
      case 'GET /api/analytics/sources':
        if (user['personType'] != 'admin') return _json({'error': 'Admin access required'}, status: 403);
        return _json({'total': totalSources, 'lastCheckedAt': '2026-09-21T00:00:00.000Z', 'needsAttention': flaggedSources, 'cannotCheck': blockedSources});
      case 'POST /api/analytics/sources/reviewed':
        final url = (jsonDecode(request.body) as Map<String, dynamic>)['url'];
        flaggedSources.removeWhere((s) => s['url'] == url);
        return _json({'total': totalSources, 'lastCheckedAt': '2026-09-21T00:00:00.000Z', 'needsAttention': flaggedSources, 'cannotCheck': blockedSources});
      case 'GET /api/consent/status':
        return _json({'granted': locationConsentGranted});
      case 'GET /api/consent/history':
        return _json({'records': locationConsentRecords.reversed.toList()});
      case 'POST /api/consent':
        final granted = (jsonDecode(request.body) as Map<String, dynamic>)['granted'] as bool;
        locationConsentGranted = granted;
        final record = {
          'id': 'c${locationConsentRecords.length + 1}',
          'consent_version': '1.0',
          'granted': granted,
          'granted_at': granted ? '2026-09-21T12:00:00.000Z' : null,
          'revoked_at': granted ? null : '2026-09-21T12:00:00.000Z',
          'created_at': '2026-09-21T12:00:00.000Z',
        };
        locationConsentRecords.add(record);
        return _json({'record': record});
      case 'GET /api/locations/latest':
        return _json({'locations': staffLocations});
      case 'GET /api/documents/on-file':
        return _json({'participants': documentsOnFile});
      case 'GET /api/consent/disclosure':
        return _json({'version': '1.0', 'text': 'Location sharing disclosure text.'});
      case 'GET /api/consent/documents/disclosure':
        return _json({'version': '1.0', 'text': 'Document storage disclosure text.'});
      case 'GET /api/consent/documents/status':
        return _json({'granted': true, 'consent_version': '1.0'});
      case 'GET /api/documents':
        return _json({'documents': documents.reversed.toList()});
      case 'POST /api/documents':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        uploadBodies.add(body);
        if (failUploadsWith != null) {
          return _json({'error': failUploadsWith}, status: 400);
        }
        final doc = {
          'id': 'd${documents.length + 1}',
          'documentType': body['documentType'],
          'label': body['label'],
          'mimeType': body['mimeType'],
          'fileSizeBytes': base64Decode(body['fileBase64'] as String).length,
          'createdAt': '2026-09-21T12:00:00.000Z',
        };
        documents.add(doc);
        return _json({'document': doc}, status: 201);
    }
    return _json({'error': 'No fake for $route'}, status: 404);
  }

  String _normalizeCode(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
