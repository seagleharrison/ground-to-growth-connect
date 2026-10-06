import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Admin-only: who needs approving, what's been reported, and the review of
/// conversations (every open is logged by the server).
class SafetyController extends ChangeNotifier {
  List<SafetyReport> reports = [];
  List<AdminConversation> conversations = [];
  List<VolunteerInfo> volunteers = [];
  List<AccessLogEntry> accessLog = [];
  bool isLoading = false;
  String? error;

  /// Set by AppState while an admin is only previewing.
  bool Function()? writeBlocked;

  int get openReports => reports.where((r) => r.isOpen).length;
  int get pendingVolunteers => volunteers.where((v) => !v.approved).length;

  /// What needs an admin's attention — shown as a badge on the Messages tab.
  int get needsAttention => openReports + pendingVolunteers;

  void clearPrivate() {
    reports = [];
    conversations = [];
    volunteers = [];
    accessLog = [];
    error = null;
    notifyListeners();
  }

  Future<void> refreshSummary() async {
    try {
      final results = await Future.wait([ApiClient.shared.fetchReports(), ApiClient.shared.fetchVolunteers()]);
      reports = results[0] as List<SafetyReport>;
      volunteers = results[1] as List<VolunteerInfo>;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshAll() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiClient.shared.fetchReports(),
        ApiClient.shared.fetchVolunteers(),
        ApiClient.shared.fetchAdminConversations(),
        ApiClient.shared.fetchAccessLog(),
      ]);
      reports = results[0] as List<SafetyReport>;
      volunteers = results[1] as List<VolunteerInfo>;
      conversations = results[2] as List<AdminConversation>;
      accessLog = results[3] as List<AccessLogEntry>;
    } catch (e) {
      error = e is GgcException ? e.message : "Couldn't load the safety review.";
    }
    isLoading = false;
    notifyListeners();
  }

  Future<String?> _act(Future<void> Function() call) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await call();
      await refreshAll();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't do that just now.";
    }
  }

  Future<String?> resolve(String reportId) => _act(() => ApiClient.shared.resolveReport(reportId));
  Future<String?> volunteerAction(String id, String action) => _act(() => ApiClient.shared.volunteerAction(id, action));

  /// Opens a conversation. The server records that this admin looked.
  Future<List<AdminMessage>> read(String a, String b) async {
    final messages = await ApiClient.shared.readAdminConversation(a, b);
    try {
      accessLog = await ApiClient.shared.fetchAccessLog();
      notifyListeners();
    } catch (_) {}
    return messages;
  }
}
