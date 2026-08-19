import SwiftUI

@main
struct GroundToGrowthConnectApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await appState.bootstrap()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if appState.isSignedIn {
                if appState.isUnlocked {
                    MainTabView()
                } else {
                    LockedView()
                }
            } else {
                RegisterView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            // Re-lock whenever the app leaves the foreground, so returning
            // to it (even briefly backgrounded) requires Face ID again.
            if newPhase == .background {
                appState.isUnlocked = false
            }
        }
    }
}

struct LockedView: View {
    @EnvironmentObject private var appState: AppState
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Ground to Growth Connect is locked")
                .font(.headline)

            if let authError {
                Text(authError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Unlock") {
                Task { await unlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await unlock()
        }
    }

    private func unlock() async {
        authError = nil
        let ok = await BiometricAuth.authenticate(reason: "Unlock Ground to Growth Connect")
        if ok {
            appState.isUnlocked = true
        } else {
            authError = "Authentication failed. Try again."
        }
    }
}
