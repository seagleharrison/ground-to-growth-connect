import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Help requests, from both sides: what the signed-in person has asked for,
/// and (for volunteers and admins) the board of everything people need.
class HelpController extends ChangeNotifier {
  /// Set by AppState: true (and tells the person why) while an admin is only
  /// previewing, so nothing is changed from a preview.
  bool Function()? writeBlocked;
  List<HelpRequest> mine = [];
  List<HelpRequest> board = [];
  bool isLoadingMine = false;
  bool isLoadingBoard = false;
  String? mineError;
  String? boardError;

  /// Open and being-helped requests, not the ones already closed.
  List<HelpRequest> get myActive => [for (final r in mine) if (!r.isDone) r];

  /// A volunteer's first name for an appointment they're taking someone to.
  String? helperForAppointment(String appointmentId) {
    for (final r in mine) {
      if (r.isClaimed && r.appointment?.id == appointmentId) return r.helperName;
    }
    return null;
  }

  /// Called on sign-out so the next person on this phone never sees these.
  void clearPrivate() {
    mine = [];
    board = [];
    mineError = null;
    boardError = null;
    notifyListeners();
  }

  Future<void> refreshMine() async {
    isLoadingMine = true;
    mineError = null;
    notifyListeners();
    try {
      mine = await ApiClient.shared.fetchMyHelpRequests();
    } catch (e) {
      mineError = e is GgcException ? e.message : "Couldn't load your requests.";
    }
    isLoadingMine = false;
    notifyListeners();
  }

  Future<void> refreshBoard() async {
    isLoadingBoard = true;
    boardError = null;
    notifyListeners();
    try {
      board = await ApiClient.shared.fetchHelpBoard();
    } catch (e) {
      boardError = e is GgcException ? e.message : "Couldn't load the help board.";
    }
    isLoadingBoard = false;
    notifyListeners();
  }

  /// Each returns an error message, or null on success.
  Future<String?> ask({required HelpCategory category, String? note, String? appointmentId}) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final created = await ApiClient.shared.createHelpRequest(category: category, note: note, appointmentId: appointmentId);
      mine = [created, ...mine];
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't send that request.";
    }
  }

  Future<String?> markDone(String id) => _mine(id, ApiClient.shared.completeHelpRequest);

  Future<String?> _mine(String id, Future<HelpRequest> Function(String) call) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final updated = await call(id);
      mine = [for (final r in mine) if (r.id == id) updated else r];
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't update that request.";
    }
  }

  Future<String?> cancel(String id) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await ApiClient.shared.deleteHelpRequest(id);
      mine = mine.where((r) => r.id != id).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't remove that request.";
    }
  }

  /// "I can help": for a volunteer this is an offer an admin must confirm.
  Future<String?> claim(String id) => _board(id, ApiClient.shared.claimHelpRequest);

  Future<String?> approveOffer(String offerId) => _guard(() async {
        final updated = await ApiClient.shared.approveHelpOffer(offerId);
        board = [for (final r in board) if (r.id == updated.id) updated else r];
      });

  Future<String?> declineOffer(String offerId) => _guard(() async {
        final updated = await ApiClient.shared.declineHelpOffer(offerId);
        board = [for (final r in board) if (r.id == updated.id) updated else r];
      });

  Future<String?> withdrawOffer(String requestId, String offerId) => _guard(() async {
        await ApiClient.shared.withdrawHelpOffer(offerId);
        await refreshBoard();
      });

  /// A volunteer's tap: on_my_way, arrived, running_late, cant_make_it, unsafe.
  Future<String?> progress(String requestId, String kind, {int? minutes}) => _guard(() async {
        final updated = await ApiClient.shared.sendHelpProgress(requestId, kind, minutes: minutes);
        board = [for (final r in board) if (r.id == requestId) updated else r];
        // Ending a match (can't make it, unsafe) changes what the board shows.
        if (kind == 'cant_make_it' || kind == 'unsafe') await refreshBoard();
      });

  /// The person's tap: "I don't feel safe". Ends the match.
  Future<String?> reportUnsafe(String requestId) => _guard(() async {
        final updated = await ApiClient.shared.sendHelpProgress(requestId, 'unsafe');
        mine = [for (final r in mine) if (r.id == requestId) updated else r];
      });

  /// Thumbs up (1) or down (-1) once it's done.
  Future<String?> rate(String requestId, int value) => _guard(() async {
        final updated = await ApiClient.shared.rateHelpRequest(requestId, value);
        mine = [for (final r in mine) if (r.id == requestId) updated else r];
      });

  Future<String?> _guard(Future<void> Function() action) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await action();
      notifyListeners();
      return null;
    } catch (e) {
      refreshBoard();
      return e is GgcException ? e.message : "Couldn't update that.";
    }
  }
  Future<String?> release(String id) => _board(id, ApiClient.shared.releaseHelpRequest);
  Future<String?> finish(String id) => _board(id, ApiClient.shared.completeHelpRequest, drop: true);

  Future<String?> _board(String id, Future<HelpRequest> Function(String) call, {bool drop = false}) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final updated = await call(id);
      board = drop ? board.where((r) => r.id != id).toList() : [for (final r in board) if (r.id == id) updated else r];
      notifyListeners();
      return null;
    } catch (e) {
      // Someone else may have claimed it first: show the real picture.
      refreshBoard();
      return e is GgcException ? e.message : "Couldn't update that request.";
    }
  }
}
