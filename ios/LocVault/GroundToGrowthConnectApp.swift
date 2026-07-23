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

    var body: some View {
        Group {
            if appState.isSignedIn {
                MainTabView()
            } else {
                RegisterView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
