import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiURL = KeychainService.loadAPIBaseURL()
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = appState.user {
                    Section("Profile") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Account type", value: personTypeLabel(user.personType))
                        if let email = user.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                        if let phone = user.phone, !phone.isEmpty {
                            LabeledContent("Phone", value: phone)
                        }
                        if let gender = user.gender, !gender.isEmpty {
                            LabeledContent("Gender", value: genderLabel(gender))
                        }
                    }
                }

                Section("Server") {
                    TextField("API base URL", text: $apiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Save API URL") { appState.saveAPIBaseURL(apiURL) }
                    Text("Simulator: http://127.0.0.1:3001\nDevice: http://YOUR_MAC_IP:3001")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Security & privacy") {
                    Label("Access token stored in Keychain", systemImage: "lock.shield")
                    Label("Personal details encrypted at rest", systemImage: "lock.fill")
                    Label("Location snapped to a ~200m grid", systemImage: "grid")
                }

                Section {
                    Button("Sign out") { appState.signOut() }
                    Button("Delete my data", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } footer: {
                    Text("Deleting your data permanently removes your account, consent records, and all location history from Ground to Growth Initiative's server.")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete your data?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete everything", role: .destructive) {
                    Task { await appState.deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your account and all stored location history. This cannot be undone.")
            }
        }
    }

    private func personTypeLabel(_ raw: String) -> String {
        PersonType(rawValue: raw)?.label ?? raw.capitalized
    }

    private func genderLabel(_ raw: String) -> String {
        Gender(rawValue: raw)?.label ?? raw.capitalized
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            if appState.user?.isStaff == true {
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map") }
            } else {
                ConsentView()
                    .tabItem { Label("Share", systemImage: "location.fill") }

                MyMapTabView()
                    .tabItem { Label("Map", systemImage: "map") }

                DocumentsView()
                    .tabItem { Label("Documents", systemImage: "lock.doc") }
            }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
