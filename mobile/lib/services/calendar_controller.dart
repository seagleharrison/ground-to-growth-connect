import 'package:flutter/foundation.dart';

import '../data/calendar_content.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Backs the participant Calendar tab: shelter/program events (server
/// content, same offline-cache pattern as Resources) plus the person's own
/// private appointments (server-synced, encrypted, never visible to staff).
class CalendarController extends ChangeNotifier {
  /// Set by AppState: true (and tells the person why) while an admin is only
  /// previewing, so nothing is changed from a preview.
  bool Function()? writeBlocked;
  CalendarEventsContent? content;
  bool isRefreshingEvents = false;
  bool eventsOffline = false;
  DateTime? eventsLastCheckedAt;
  String? _etag;
  Future<void>? _loadingEvents;

  List<Appointment> appointments = [];
  bool isLoadingAppointments = false;
  String? appointmentsError;

  static const staleAfter = Duration(minutes: 15);

  /// Tests use this to start from known content without reading assets from disk.
  @visibleForTesting
  void debugPreloadEvents(CalendarEventsContent preloaded) {
    content = preloaded;
    _loadingEvents = Future.value();
  }

  Future<void> ensureEventsLoaded() => _loadingEvents ??= _loadLocalEvents();

  Future<void> _loadLocalEvents() async {
    try {
      final cached = await SecureStorageService.loadEventsCache();
      if (cached != null) {
        content = CalendarEventsContent.fromRaw(cached.json);
        _etag = cached.etag;
      }
    } catch (_) {
      content = null;
      _etag = null;
    }
    if (content == null) {
      try {
        content = await CalendarEventsContent.loadBundled();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> refreshEvents() async {
    if (isRefreshingEvents) return;
    isRefreshingEvents = true;
    notifyListeners();
    try {
      await ensureEventsLoaded();
      final result = await ApiClient.shared.fetchEvents(etag: _etag);
      if (result.status == 200 && result.body != null) {
        // Parse before keeping it: a bad response must never replace good content.
        final fresh = CalendarEventsContent.fromRaw(result.body!);
        content = fresh;
        _etag = result.etag;
        await SecureStorageService.saveEventsCache(json: result.body!, etag: result.etag);
        eventsOffline = false;
        eventsLastCheckedAt = DateTime.now();
      } else if (result.status == 304) {
        eventsOffline = false;
        eventsLastCheckedAt = DateTime.now();
      } else {
        eventsOffline = true;
      }
    } catch (_) {
      eventsOffline = true;
    }
    isRefreshingEvents = false;
    notifyListeners();
  }

  /// Called when the app comes back to the front: re-check if it's been a while.
  Future<void> refreshEventsIfStale() async {
    final last = eventsLastCheckedAt;
    if (last == null || DateTime.now().difference(last) > staleAfter) await refreshEvents();
  }

  /// Called on sign-out so the next person on this phone never sees these.
  void clearPrivate() {
    appointments = [];
    appointmentsError = null;
    notifyListeners();
  }

  Future<void> refreshAppointments() async {
    isLoadingAppointments = true;
    appointmentsError = null;
    notifyListeners();
    try {
      appointments = await ApiClient.shared.fetchAppointments();
    } catch (e) {
      appointmentsError = e is GgcException ? e.message : "Couldn't load your appointments.";
    }
    isLoadingAppointments = false;
    notifyListeners();
  }

  void _replaceAndSort(Appointment updated) {
    final without = appointments.where((a) => a.id != updated.id);
    appointments = [...without, updated]..sort((a, b) => a.startsAtLocal.compareTo(b.startsAtLocal));
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> addAppointment({
    required String title,
    String? notes,
    String? location,
    required DateTime startsAt,
    DateTime? endsAt,
    bool allDay = false,
    String kind = 'appointment',
    bool needsRide = false,
  }) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final created = await ApiClient.shared.createAppointment(
        title: title,
        notes: notes,
        location: location,
        startsAt: startsAt.toUtc().toIso8601String(),
        endsAt: endsAt?.toUtc().toIso8601String(),
        allDay: allDay,
        kind: kind,
        needsRide: needsRide,
      );
      _replaceAndSort(created);
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't save that appointment.";
    }
  }

  Future<String?> editAppointment(
    String id, {
    String? title,
    String? notes,
    String? location,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearEnd = false,
    bool? allDay,
    String? kind,
    bool? needsRide,
  }) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final updated = await ApiClient.shared.updateAppointment(
        id,
        title: title,
        notes: notes,
        location: location,
        startsAt: startsAt?.toUtc().toIso8601String(),
        endsAt: clearEnd ? '' : endsAt?.toUtc().toIso8601String(),
        allDay: allDay,
        kind: kind,
        needsRide: needsRide,
      );
      _replaceAndSort(updated);
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't save that change.";
    }
  }

  Future<String?> removeAppointment(String id) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await ApiClient.shared.deleteAppointment(id);
      appointments = appointments.where((a) => a.id != id).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't delete that appointment.";
    }
  }
}
