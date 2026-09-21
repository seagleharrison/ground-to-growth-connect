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
  final List<Map<String, dynamic>> patchBodies = [];
  final List<Map<String, dynamic>> uploadBodies = [];

  /// When set, POST /api/documents fails with this error message.
  String? failUploadsWith;

  /// When set, PATCH /api/me fails with this error message.
  String? failProfileUpdateWith;

  String? pictureBase64;
  String? pictureMime;

  late final MockClient client = MockClient(_handle);

  /// Only for taking design screenshots: lets real map tiles download instead
  /// of answering "not found". Off in the automated tests.
  static bool passThroughMapTiles = false;
  static final IOClient _realNetwork = IOClient(HttpClient());

  Future<http.Response> _handle(http.Request request) async {
    if (passThroughMapTiles && request.url.host.endsWith('openstreetmap.org')) {
      final forwarded = http.Request(request.method, request.url)..headers.addAll(request.headers);
      return http.Response.fromStream(await _realNetwork.send(forwarded));
    }
    final route = '${request.method} ${request.url.path}';

    // GET /api/documents/{id}: hand back the stored file (a real 1x1 PNG).
    final docMatch = RegExp(r'^/api/documents/(d\d+)$').firstMatch(request.url.path);
    if (request.method == 'GET' && docMatch != null) {
      final doc = documents.where((d) => d['id'] == docMatch.group(1)).firstOrNull;
      if (doc == null) return _json({'error': 'Not found'}, status: 404);
      return _json({'document': doc, 'fileBase64': tinyPngBase64});
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

  http.Response _json(Object body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
