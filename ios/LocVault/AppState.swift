import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var consent: ConsentStatus?
    @Published var disclosure: DisclosureResponse?
    @Published var consentHistory: [ConsentRecord] = []
    @Published var locations: [UserLocation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var apiBaseURL: String = KeychainService.loadAPIBaseURL()

    @Published var documentConsent: ConsentStatus?
    @Published var documentDisclosure: DisclosureResponse?
    @Published var documents: [DocumentMeta] = []
    @Published var isUploadingDocument = false

    /// A participant's own location history — never other participants',
    /// which is what keeps this distinct from `locations` (the staff-only
    /// everyone view).
    @Published var myLocations: [MyLocationReport] = []

    /// Gates the whole signed-in app behind Face ID/passcode. Starts locked
    /// on cold launch for a returning session; set true directly after a
    /// fresh in-session registration (see register()) since the person just
    /// proved presence by typing on the device.
    @Published var isUnlocked = false

    let locationTracker = LocationTracker()

    var isSignedIn: Bool { user != nil }

    init() {
        user = KeychainService.loadUser()
    }

    func bootstrap() async {
        do {
            disclosure = try await APIClient.shared.fetchDisclosure()
        } catch {
            errorMessage = error.localizedDescription
        }

        if isSignedIn {
            await refreshSession()
        }
    }

    func refreshSession() async {
        guard isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if user?.isStaff == true {
                // Staff view the participant map and don't share their own location.
                locations = try await APIClient.shared.fetchLatestLocations()
            } else {
                consent = try await APIClient.shared.fetchConsentStatus()
                consentHistory = try await APIClient.shared.fetchConsentHistory()
                locationTracker.updateConsent(granted: consent?.granted == true)
            }
        } catch let error as LocVaultError where error.localizedDescription.contains("Session expired") {
            signOut()
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(_ payload: RegisterRequest) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.register(payload)
            try KeychainService.saveToken(response.token)
            try KeychainService.saveUser(response.user)
            user = response.user
            isUnlocked = true // they just proved presence by registering on this device
            await refreshSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await APIClient.shared.deleteAccount()
            signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func grantConsent() async {
        await updateConsent(granted: true)
        // The tracker requests When-In-Use first, then escalates to "Always"
        // once granted (required for background 15-minute reports).
    }

    func revokeConsent() async {
        await updateConsent(granted: false)
    }

    private func updateConsent(granted: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await APIClient.shared.setConsent(granted: granted)
            consent = try await APIClient.shared.fetchConsentStatus()
            consentHistory = try await APIClient.shared.fetchConsentHistory()
            locationTracker.updateConsent(granted: granted)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshLocations() async {
        guard isSignedIn else { return }
        do {
            locations = try await APIClient.shared.fetchLatestLocations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMyLocations() async {
        guard isSignedIn else { return }
        do {
            myLocations = try await APIClient.shared.fetchMyLocations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Document storage

    func refreshDocumentConsent() async {
        guard isSignedIn else { return }
        do {
            documentDisclosure = try await APIClient.shared.fetchDocumentDisclosure()
            documentConsent = try await APIClient.shared.fetchDocumentConsentStatus()
            if documentConsent?.granted == true {
                documents = try await APIClient.shared.fetchDocuments()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func grantDocumentConsent() async {
        await updateDocumentConsent(granted: true)
    }

    func revokeDocumentConsent() async {
        await updateDocumentConsent(granted: false)
    }

    private func updateDocumentConsent(granted: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await APIClient.shared.setDocumentConsent(granted: granted)
            documentConsent = try await APIClient.shared.fetchDocumentConsentStatus()
            documents = granted ? try await APIClient.shared.fetchDocuments() : []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the saved document's metadata on success, nil on failure
    /// (see errorMessage). imageData should already be JPEG-encoded.
    func uploadDocument(type: DocumentType, label: String?, imageData: Data) async -> DocumentMeta? {
        isUploadingDocument = true
        errorMessage = nil
        defer { isUploadingDocument = false }

        do {
            let payload = UploadDocumentRequest(
                documentType: type.rawValue,
                label: label,
                mimeType: "image/jpeg",
                fileBase64: imageData.base64EncodedString()
            )
            let meta = try await APIClient.shared.uploadDocument(payload)
            documents.insert(meta, at: 0)
            return meta
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteDocument(_ id: String) async {
        errorMessage = nil
        do {
            try await APIClient.shared.deleteDocument(id: id)
            documents.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAPIBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        apiBaseURL = trimmed
        try? KeychainService.saveAPIBaseURL(trimmed)
    }

    func signOut() {
        locationTracker.updateConsent(granted: false)
        KeychainService.clearSession()
        user = nil
        consent = nil
        consentHistory = []
        locations = []
        myLocations = []
        documentConsent = nil
        documentDisclosure = nil
        documents = []
        isUnlocked = false
    }
}
