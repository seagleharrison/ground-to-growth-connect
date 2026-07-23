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
    }
}
