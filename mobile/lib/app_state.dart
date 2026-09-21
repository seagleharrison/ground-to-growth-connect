import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models/models.dart';
import 'services/api_client.dart';
import 'services/location_tracker.dart';
import 'services/secure_storage_service.dart';

/// Direct equivalent of the native app's AppState.swift: a ChangeNotifier
/// instead of an ObservableObject, same fields, same method names.
class AppState extends ChangeNotifier {
  final locationTracker = LocationTracker();

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

  /// True while the stored session is still being read from secure storage
  /// on cold launch — the root widget shows a splash until this clears.
  bool isInitializing = true;

  bool get isSignedIn => user != null;

  Future<void> init() async {
    user = await SecureStorageService.loadUser();
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
      isUnlocked = true; // they just proved presence by registering on this device
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

  Future<void> grantConsent() => _updateConsent(granted: true);

  Future<void> revokeConsent() => _updateConsent(granted: false);

  Future<void> _updateConsent({required bool granted}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      await ApiClient.shared.setConsent(granted: granted);
      consent = await ApiClient.shared.fetchConsentStatus();
      consentHistory = await ApiClient.shared.fetchConsentHistory();
      await locationTracker.updateConsent(granted: granted);
    } catch (e) {
      errorMessage = '$e';
    }
    isLoading = false;
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
    await locationTracker.updateConsent(granted: false);
    await SecureStorageService.clearSession();
    user = null;
    profilePictureBytes = null;
    consent = null;
    consentHistory = [];
    locations = [];
    documentsOnFile = {};
    myLocations = [];
    documentConsent = null;
    documentDisclosure = null;
    documents = [];
    isUnlocked = false;
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

  void setUnlocked(bool value) {
    isUnlocked = value;
    notifyListeners();
  }
}
