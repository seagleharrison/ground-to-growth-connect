import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models/models.dart';
import 'services/api_client.dart';
import 'services/location_tracker.dart';
import 'services/resources_controller.dart';
import 'services/secure_storage_service.dart';

/// Direct equivalent of the native app's AppState.swift: a ChangeNotifier
/// instead of an ObservableObject, same fields, same method names.
class AppState extends ChangeNotifier {
  final locationTracker = LocationTracker();

  /// The Resources tab's content and "near you" logic. Its changes are passed
  /// on so any screen watching AppState updates too.
  final resources = ResourcesController();

  AppState() {
    resources.addListener(notifyListeners);
  }

  @override
  void dispose() {
    resources.removeListener(notifyListeners);
    resources.dispose();
    super.dispose();
  }

  User? user;

  /// The signed-in user's own profile picture, once loaded.
  Uint8List? profilePictureBytes;
  bool isSavingProfile = false;

  ConsentStatus? consent;
  DisclosureResponse? disclosure;
  List<ConsentRecord> consentHistory = [];
  List<UserLocation> locations = [];
  bool isLoading = false;
  String? errorMessage;
  String apiBaseUrl = SecureStorageService.defaultApiBaseUrl;

  ConsentStatus? documentConsent;
  DisclosureResponse? documentDisclosure;
  List<DocumentMeta> documents = [];
  bool isUploadingDocument = false;

  /// A participant's own location history — never other participants',
  /// which is what keeps this distinct from [locations] (the staff-only
  /// everyone view).
  List<MyLocationReport> myLocations = [];

  /// Gates the whole signed-in app behind Face ID/biometric+passcode lock.
  /// Starts locked on cold launch for a returning session; set true directly
  /// after a fresh in-session registration since the person just proved
  /// presence by typing on the device.
  bool isUnlocked = false;

  /// An admin looking at the app the way volunteers or participants see it. Only
  /// changes what's shown: the account and what the server allows stay the same.
  AppView? previewView;

  /// Set when a preview blocks something that would really change data (turning
  /// on location sharing, uploading a document); the screen shows it once.
  String? previewNotice;

  AppView get ownView => user?.isAdmin == true
      ? AppView.admin
      : user?.isStaff == true
          ? AppView.volunteer
          : AppView.participant;

  /// What's on screen right now: the admin's chosen preview, or their own view.
  AppView get currentView => (user?.isAdmin == true ? previewView : null) ?? ownView;

  bool get isPreviewing => currentView != ownView;

  /// Admins only. Choosing Admin goes back to their own view.
  void viewAs(AppView view) {
    if (user?.isAdmin != true) return;
    previewView = view == AppView.admin ? null : view;
    previewNotice = null;
    notifyListeners();
  }

  void clearPreviewNotice() => previewNotice = null;

  /// While previewing, actions that would change real data are switched off.
  bool _blockedByPreview() {
    if (!isPreviewing) return false;
    previewNotice = "You're previewing the app, so this is switched off. Switch back to Admin to use it.";
    notifyListeners();
    return true;
  }

  /// True right after creating an account, until the person dismisses the
  /// welcome card on Home.
  bool showWelcome = false;

  /// True while the stored session is still being read from secure storage
  /// on cold launch — the root widget shows a splash until this clears.
  bool isInitializing = true;

  bool get isSignedIn => user != null;

  Future<void> init() async {
    user = await SecureStorageService.loadUser();
    if (user != null) hiddenDocuments = await SecureStorageService.loadHiddenDocuments(user!.id);
    apiBaseUrl = await SecureStorageService.loadApiBaseUrl();
    isInitializing = false;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    try {
      disclosure = await ApiClient.shared.fetchDisclosure();
    } catch (e) {
      errorMessage = '$e';
    }

    if (isSignedIn) {
      await refreshSession();
    }
    notifyListeners();
  }

  Future<void> refreshSession() async {
    if (!isSignedIn) return;
    isLoading = true;
    notifyListeners();

    try {
      await _refreshProfile();
      if (user?.isStaff == true) {
        // Staff view the participant map and don't share their own location.
        locations = await ApiClient.shared.fetchLatestLocations();
      } else {
        consent = await ApiClient.shared.fetchConsentStatus();
        consentHistory = await ApiClient.shared.fetchConsentHistory();
        await locationTracker.updateConsent(granted: consent?.granted == true);
      }
    } on GgcException catch (e) {
      if (e.message.contains('Session expired')) {
        await signOut();
      }
      errorMessage = e.message;
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Re-reads the profile from the server (so edits made on another device
  /// show up) and loads the picture if there is one.
  Future<void> _refreshProfile() async {
    final fresh = await ApiClient.shared.fetchMe();
    user = fresh;
    await SecureStorageService.saveUser(fresh);
    await _loadProfilePicture();
  }

  Future<void> _loadProfilePicture() async {
    if (user?.hasProfilePicture != true) {
      profilePictureBytes = null;
      return;
    }
    try {
      profilePictureBytes = base64Decode(await ApiClient.shared.fetchProfilePictureBase64());
    } catch (_) {
      // A missing or unreadable picture shouldn't get in the way of signing
      // in — fall back to the initials avatar.
      profilePictureBytes = null;
    }
  }

  /// Saves name/email/phone/gender. An empty string clears an optional
  /// field. Returns true on success; on failure see [errorMessage].
  Future<bool> updateProfile({
    required String name,
    required String email,
    required String phone,
    required String gender,
  }) async {
    isSavingProfile = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await ApiClient.shared.updateProfile(
        name: name,
        email: email,
        phone: phone,
        gender: gender,
      );
      user = updated;
      await SecureStorageService.saveUser(updated);
      return true;
    } catch (e) {
      errorMessage = '$e';
      return false;
    } finally {
      isSavingProfile = false;
      notifyListeners();
    }
  }

  /// Switches between a participant account and a staff role. Moving into a
  /// staff role needs the staff invite code. Returns null on success, or a
  /// message that can be shown to the person.
  Future<String?> changeAccountType(PersonType type, {String? staffCode}) async {
    isSavingProfile = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await ApiClient.shared.updateProfile(
        personType: type.name,
        staffCode: type.isStaff ? staffCode : null,
      );
      user = updated;
      await SecureStorageService.saveUser(updated);
      if (!updated.isAdmin) {
        previewView = null;
        analytics = null;
        sourceReport = null;
      }
      if (updated.isStaff) {
        // Staff don't share their own location; the server has also ended any sharing.
        await locationTracker.updateConsent(granted: false);
        consent = null;
        consentHistory = [];
        documents = [];
        documentConsent = null;
      } else {
        locations = [];
      }
      await refreshSession();
      HapticFeedback.mediumImpact();
      return null;
    } catch (e) {
      return '$e';
    } finally {
      isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> setProfilePicture(Uint8List bytes, String mimeType) async {
    isSavingProfile = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await ApiClient.shared.putProfilePicture(
        mimeType: mimeType,
        fileBase64: base64Encode(bytes),
      );
      user = updated;
      await SecureStorageService.saveUser(updated);
      profilePictureBytes = bytes;
      return true;
    } catch (e) {
      errorMessage = '$e';
      return false;
    } finally {
      isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> removeProfilePicture() async {
    isSavingProfile = true;
    errorMessage = null;
    notifyListeners();
    try {
      final updated = await ApiClient.shared.deleteProfilePicture();
      user = updated;
      await SecureStorageService.saveUser(updated);
      profilePictureBytes = null;
      return true;
    } catch (e) {
      errorMessage = '$e';
      return false;
    } finally {
      isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<void> register(RegisterRequest payload) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await ApiClient.shared.register(payload);
      await SecureStorageService.saveToken(response.token);
      await SecureStorageService.saveUser(response.user);
      user = response.user;
      hiddenDocuments = {};
      isUnlocked = true; // they just proved presence by registering on this device
      showWelcome = true;
      HapticFeedback.mediumImpact();
      await refreshSession();
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await ApiClient.shared.deleteAccount();
      await signOut();
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// "I don't have this": takes a document off the checklist. Only for
  /// documents that aren't on file.
  Future<void> hideDocument(DocumentType type) async {
    final id = user?.id;
    if (id == null || type == DocumentType.other || documents.any((d) => d.type == type)) return;
    if (_blockedByPreview()) return;
    hiddenDocuments = {...hiddenDocuments, type};
    notifyListeners();
    await SecureStorageService.saveHiddenDocuments(id, hiddenDocuments);
  }

  Future<void> unhideDocument(DocumentType type) async {
    final id = user?.id;
    if (id == null) return;
    hiddenDocuments = {...hiddenDocuments}..remove(type);
    notifyListeners();
    await SecureStorageService.saveHiddenDocuments(id, hiddenDocuments);
  }

  Future<void> grantConsent() => _updateConsent(granted: true);

  Future<void> revokeConsent() => _updateConsent(granted: false);

  Future<void> _updateConsent({required bool granted}) async {
    if (granted && _blockedByPreview()) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await ApiClient.shared.setConsent(granted: granted);
      consent = await ApiClient.shared.fetchConsentStatus();
      consentHistory = await ApiClient.shared.fetchConsentHistory();
      await locationTracker.updateConsent(granted: granted);
      if (granted) HapticFeedback.mediumImpact();
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAnalytics() async {
    if (user?.isAdmin != true) return;
    isLoadingAnalytics = true;
    analyticsError = null;
    notifyListeners();
    try {
      analytics = await ApiClient.shared.fetchAnalytics();
      try {
        sourceReport = await ApiClient.shared.fetchSourceReport();
      } catch (_) {
        // The numbers matter more than the page-watch list; show what we have.
      }
    } catch (e) {
      analyticsError = '$e';
    }
    isLoadingAnalytics = false;
    notifyListeners();
  }

  /// Admin: "I checked that page; our guide is still right."
  Future<void> markSourceReviewed(String url) async {
    try {
      sourceReport = await ApiClient.shared.markSourceReviewed(url);
    } catch (e) {
      analyticsError = '$e';
    }
    notifyListeners();
  }

  Future<void> refreshLocations() async {
    if (!isSignedIn) return;
    try {
      locations = await ApiClient.shared.fetchLatestLocations();
      notifyListeners();
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  /// Staff only: which document types each participant has on file.
  Map<String, Set<DocumentType>> documentsOnFile = {};

  /// Core documents the person said they don't have. They're left off the
  /// checklist and don't count against progress; shown again with [unhideDocument].
  Set<DocumentType> hiddenDocuments = {};

  /// The core documents this person is being asked for: everything except what
  /// they hid — unless they've since added one anyway, which always shows.
  List<DocumentType> get documentChecklist => [
        for (final t in DocumentType.coreChecklist)
          if (!hiddenDocuments.contains(t) || documents.any((d) => d.type == t)) t,
      ];

  /// Admin-only totals; null until loaded.
  Analytics? analytics;
  SourceReport? sourceReport;
  bool isLoadingAnalytics = false;
  String? analyticsError;

  Future<void> refreshPeople() async {
    if (!isSignedIn || user?.isStaff != true) return;
    try {
      final results = await Future.wait([
        ApiClient.shared.fetchLatestLocations(),
        ApiClient.shared.fetchDocumentsOnFile(),
      ]);
      locations = results[0] as List<UserLocation>;
      documentsOnFile = results[1] as Map<String, Set<DocumentType>>;
      notifyListeners();
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> refreshMyLocations() async {
    if (!isSignedIn) return;
    try {
      myLocations = await ApiClient.shared.fetchMyLocations();
      notifyListeners();
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  // MARK: - Document storage

  Future<void> refreshDocumentConsent() async {
    if (!isSignedIn) return;
    try {
      documentDisclosure = await ApiClient.shared.fetchDocumentDisclosure();
      documentConsent = await ApiClient.shared.fetchDocumentConsentStatus();
      if (documentConsent?.granted == true) {
        documents = await ApiClient.shared.fetchDocuments();
      }
      notifyListeners();
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> grantDocumentConsent() => _updateDocumentConsent(granted: true);

  Future<void> revokeDocumentConsent() => _updateDocumentConsent(granted: false);

  Future<void> _updateDocumentConsent({required bool granted}) async {
    if (granted && _blockedByPreview()) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await ApiClient.shared.setDocumentConsent(granted: granted);
      documentConsent = await ApiClient.shared.fetchDocumentConsentStatus();
      documents = granted ? await ApiClient.shared.fetchDocuments() : [];
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Returns the saved document's metadata on success, null on failure (see
  /// [errorMessage]). [mimeType] must be one the backend accepts (JPEG, PNG
  /// or PDF).
  Future<DocumentMeta?> uploadDocument({
    required DocumentType type,
    String? label,
    required List<int> imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    if (_blockedByPreview()) return null;
    isUploadingDocument = true;
    errorMessage = null;
    notifyListeners();

    try {
      final meta = await ApiClient.shared.uploadDocument(
        documentType: type.wireValue,
        label: label,
        mimeType: mimeType,
        fileBase64: base64Encode(imageBytes),
      );
      documents.insert(0, meta);
      HapticFeedback.mediumImpact();
      return meta;
    } catch (e) {
      errorMessage = '$e';
      return null;
    } finally {
      isUploadingDocument = false;
      notifyListeners();
    }
  }

  Future<void> deleteDocument(String id) async {
    errorMessage = null;
    try {
      await ApiClient.shared.deleteDocument(id);
      documents.removeWhere((d) => d.id == id);
      notifyListeners();
    } catch (e) {
      errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> saveApiBaseUrl(String url) async {
    final trimmed = url.trim();
    apiBaseUrl = trimmed;
    await SecureStorageService.saveApiBaseUrl(trimmed);
    notifyListeners();
  }

  Future<void> signOut() async {
    final id = user?.id;
    if (id != null) await SecureStorageService.deleteHiddenDocuments(id);
    hiddenDocuments = {};
    previewView = null;
    previewNotice = null;
    await locationTracker.updateConsent(granted: false);
    await SecureStorageService.clearSession();
    user = null;
    profilePictureBytes = null;
    consent = null;
    consentHistory = [];
    locations = [];
    documentsOnFile = {};
    analytics = null;
    sourceReport = null;
    analyticsError = null;
    myLocations = [];
    documentConsent = null;
    documentDisclosure = null;
    documents = [];
    isUnlocked = false;
    showWelcome = false;
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void reportError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  void dismissWelcome() {
    if (!showWelcome) return;
    showWelcome = false;
    notifyListeners();
  }

  void setUnlocked(bool value) {
    isUnlocked = value;
    notifyListeners();
  }
}
