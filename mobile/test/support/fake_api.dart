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

  /// Help requests in the volunteer-facing shape (with userId/name); the
  /// person's own list is these filtered to their id. Ids must look like h1.
  final List<Map<String, dynamic>> helpRequests = [];
  int _nextHelpId = 1;

  /// Contacts for GET /api/conversations, and each person's thread.
  final List<Map<String, dynamic>> conversations = [];
  final Map<String, List<Map<String, dynamic>>> threads = {};
  int _nextMessageId = 1;

  /// False answers the help board and claims the way the server does for a
  /// volunteer an admin hasn't approved yet.
  bool volunteerApproved = true;

  /// Whether each person's thread is still open for sending (default open).
  final Map<String, bool> threadCanSend = {};

  /// Safety: who this person blocked, reports, and what admins can review.
  final List<Map<String, dynamic>> blocked = [];
  final List<Map<String, dynamic>> reports = [];
  final List<Map<String, dynamic>> adminConversations = [];
  final Map<String, List<Map<String, dynamic>>> adminThreads = {};
  final List<Map<String, dynamic>> accessLog = [];
  final List<Map<String, dynamic>> volunteers = [];
  bool reportAlsoBlocks = true;

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
  /// Phones registered for push alerts, via PUT/DELETE /api/push-token.
  final List<String> pushTokens = [];

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
        for (final key in ['title', 'notes', 'location', 'startsAt', 'allDay']) {
          if (body.containsKey(key)) existing[key] = body[key];
        }
        // Like the server: an empty end clears it.
        if (body.containsKey('endsAt')) existing['endsAt'] = (body['endsAt'] as String?)?.isEmpty == true ? null : body['endsAt'];
        return _json({'appointment': existing});
      }
      if (request.method == 'DELETE') {
        appointments.removeWhere((a) => a['id'] == id);
        return _json({'deleted': true});
      }
    }

    // Help requests: /api/help-requests[/{id}[/claim|release|complete]]
    final helpMatch = RegExp(r'^/api/help-requests/(h\d+)(?:/(claim|release|complete))?$').firstMatch(request.url.path);
    if (helpMatch != null) {
      final hr = helpRequests.where((h) => h['id'] == helpMatch.group(1)).firstOrNull;
      if (hr == null) return _json({'error': 'Not found'}, status: 404);
      final action = helpMatch.group(2);
      if (request.method == 'DELETE') {
        helpRequests.remove(hr);
        return _json({'deleted': true});
      }
      if (action == 'claim') {
        if (hr['status'] == 'claimed' && hr['claimedByMe'] != true) {
          return _json({'error': 'Someone else is already helping with this.'}, status: 409);
        }
        hr['status'] = 'claimed';
        hr['claimedByMe'] = true;
        hr['helperName'] = (user['name'] as String).split(' ').first;
      } else if (action == 'release') {
        hr['status'] = 'open';
        hr['claimedByMe'] = false;
        hr['helperName'] = null;
      } else if (action == 'complete') {
        hr['status'] = 'done';
      }
      return _json({'request': hr});
    }
    final msgMatch = RegExp(r'^/api/messages/([\w-]+)$').firstMatch(request.url.path);
    if (msgMatch != null) {
      final other = msgMatch.group(1)!;
      final thread = threads.putIfAbsent(other, () => []);
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final m = {
          'id': 'm${_nextMessageId++}',
          'fromMe': true,
          'body': body['body'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        thread.add(m);
        for (final c in conversations) {
          if (c['userId'] == other) {
            c['lastMessage'] = body['body'];
            c['lastAt'] = m['createdAt'];
          }
        }
        return _json({'message': m}, status: 201);
      }
      for (final c in conversations) {
        if (c['userId'] == other) c['unread'] = 0;
      }
      return _json({'messages': thread, 'canSend': threadCanSend[other] ?? true});
    }

    // Safety routes
    final unblockMatch = RegExp(r'^/api/blocks/([\w-]+)$').firstMatch(request.url.path);
    if (unblockMatch != null && request.method == 'DELETE') {
      blocked.removeWhere((b) => b['userId'] == unblockMatch.group(1));
      return _json({'unblocked': true});
    }
    final resolveMatch = RegExp(r'^/api/reports/([\w-]+)/resolve$').firstMatch(request.url.path);
    if (resolveMatch != null && request.method == 'POST') {
      for (final r in reports) {
        if (r['id'] == resolveMatch.group(1)) r['status'] = 'resolved';
      }
      return _json({'resolved': true});
    }
    final adminRead = RegExp(r'^/api/admin/conversations/([\w-]+)/([\w-]+)$').firstMatch(request.url.path);
    if (adminRead != null) {
      final a = adminRead.group(1)!, b = adminRead.group(2)!;
      // The real server logs ids and reports names; this fake knows a few.
      const names = {'p1': 'Pat Morgan', 'v1': 'Sam Helper'};
      accessLog.insert(0, {'admin': user['name'], 'a': names[a] ?? a, 'b': names[b] ?? b, 'createdAt': DateTime.now().toUtc().toIso8601String()});
      return _json({'messages': adminThreads['$a/$b'] ?? adminThreads['$b/$a'] ?? []});
    }
    final volAction = RegExp(r'^/api/admin/volunteers/([\w-]+)/(approve|revoke|pause|unpause)$').firstMatch(request.url.path);
    if (volAction != null && request.method == 'POST') {
      for (final v in volunteers) {
        if (v['userId'] != volAction.group(1)) continue;
        switch (volAction.group(2)) {
          case 'approve':
            v['approved'] = true;
          case 'revoke':
            v['approved'] = false;
          case 'pause':
            v['paused'] = true;
          case 'unpause':
            v['paused'] = false;
        }
      }
      return _json({'ok': true});
    }

    switch (route) {
      case 'PUT /api/push-token':
        pushTokens.add((jsonDecode(request.body) as Map<String, dynamic>)['token'] as String);
        return _json({'ok': true});
      case 'DELETE /api/push-token':
        pushTokens.remove((jsonDecode(request.body) as Map<String, dynamic>)['token']);
        return _json({'ok': true});
      case 'POST /api/blocks':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        blocked.add({'userId': body['userId'], 'name': 'Sam', 'role': 'volunteer'});
        conversations.removeWhere((c) => c['userId'] == body['userId']);
        return _json({'blocked': true});
      case 'GET /api/blocks':
        return _json({'blocked': blocked});
      case 'POST /api/reports':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        reports.add({
          'id': 'r${reports.length + 1}',
          'status': 'open',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'reason': body['reason'],
          'reporter': {'userId': user['id'], 'name': user['name'], 'role': 'participant'},
          'subject': {'userId': body['userId'], 'name': 'Sam', 'role': 'volunteer'},
        });
        return _json({'reported': true, 'blocked': reportAlsoBlocks}, status: 201);
      case 'GET /api/reports':
        if (user['personType'] != 'admin') return _json({'error': 'Admin access required'}, status: 403);
        return _json({'reports': reports});
      case 'GET /api/admin/conversations':
        return _json({'conversations': adminConversations});
      case 'GET /api/admin/access-log':
        return _json({'log': accessLog});
      case 'GET /api/admin/volunteers':
        return _json({'volunteers': volunteers});
      case 'GET /api/conversations':
        return _json({'conversations': conversations});
      case 'GET /api/help-requests/mine':
        return _json({
          'requests': [for (final h in helpRequests) if (h['userId'] == user['id']) h].reversed.toList(),
        });
      case 'GET /api/help-requests':
        if (user['personType'] == 'homeless') return _json({'error': 'Staff access required'}, status: 403);
        if (user['personType'] == 'volunteer' && !volunteerApproved) {
          return _json({'error': 'An admin needs to approve your volunteer account before you can do this.'}, status: 403);
        }
        return _json({'requests': [for (final h in helpRequests) if (h['status'] != 'done') h]});
      case 'POST /api/help-requests':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final appt = appointments.where((a) => a['id'] == body['appointmentId']).firstOrNull;
        final hr = {
          'id': 'h${_nextHelpId++}',
          'category': body['category'],
          'note': body['note'],
          'status': 'open',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'claimedAt': null,
          'helperName': null,
          'appointment': appt == null
              ? null
              : {'id': appt['id'], 'title': appt['title'], 'location': appt['location'], 'startsAt': appt['startsAt']},
          'userId': user['id'],
          'name': user['name'],
          'claimedByMe': false,
        };
        helpRequests.add(hr);
        return _json({'request': hr}, status: 201);
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
          'endsAt': body['endsAt'],
          'allDay': body['allDay'] == true,
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
