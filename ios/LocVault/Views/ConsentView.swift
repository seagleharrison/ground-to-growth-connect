import CoreLocation
import SwiftUI

struct ConsentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showPermissionInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    disclosureCard
                    actionButtons
                    auditLog
                }
                .padding()
            }
            .navigationTitle("Consent")
            .refreshable {
                await appState.refreshSession()
            }
            .sheet(isPresented: $showPermissionInfo) {
                PermissionInfoSheet {
                    showPermissionInfo = false
                    Task { await appState.grantConsent() }
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracking status")
                    .font(.headline)
                Spacer()
                StatusBadge(active: appState.consent?.granted == true)
            }

            if let user = appState.user {
                Text("Signed in as \(user.name)")
                    .foregroundStyle(.secondary)
            }

            if appState.locationTracker.isTracking {
                Label("Reporting every 15 minutes", systemImage: "location.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            if let lastReport = appState.locationTracker.lastReportAt {
                Text("Last report: \(lastReport.formatted(date: .abbreviated, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = appState.locationTracker.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            locationAuthHint
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var locationAuthHint: some View {
        switch appState.locationTracker.authorizationStatus {
        case .notDetermined:
            Text("Location permission will be requested when you grant consent.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .authorizedWhenInUse:
            Text("Tip: Allow “Always” location access in Settings for background 15-minute reports.")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .denied, .restricted:
            Text("Location access denied. Open Settings to enable location for Ground to Growth Connect.")
                .font(.footnote)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disclosure = appState.disclosure {
                Text("Disclosure · v\(disclosure.version)")
                    .font(.headline)
                ScrollView {
                    Text(disclosure.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            } else {
                ProgressView("Loading disclosure…")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                if appState.locationTracker.authorizationStatus == .notDetermined {
                    showPermissionInfo = true
                } else {
                    Task { await appState.grantConsent() }
                }
            } label: {
                Text("Grant consent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.consent?.granted == true || appState.isLoading)

            Button(role: .destructive) {
                Task { await appState.revokeConsent() }
            } label: {
                Text("Revoke consent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(appState.consent?.granted != true || appState.isLoading)
        }
    }

    @ViewBuilder
    private var auditLog: some View {
        if !appState.consentHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Consent audit log")
                    .font(.headline)
                ForEach(appState.consentHistory) { record in
                    HStack {
                        Text(record.granted ? "Granted" : "Revoked")
                            .fontWeight(.medium)
                        Spacer()
                        Text(record.createdAt.prefix(19).replacingOccurrences(of: "T", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct PermissionInfoSheet: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    Text("iOS will ask you twice")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("To send location reports every 15 minutes — even in the background — iOS requires two steps. This is normal.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        stepRow(number: "1", title: "First prompt",
                                detail: "Tap “Allow While Using App.” (There is no “Always” option on the first prompt — Apple doesn’t allow it.)")
                        stepRow(number: "2", title: "Second prompt",
                                detail: "A moment later, tap “Change to Always Allow” so reports keep working in the background.")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("You can change this anytime in Settings, and revoke consent to stop tracking immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: onContinue) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not now") { dismiss() }
                        .buttonStyle(.borderless)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Location access")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusBadge: View {
    let active: Bool

    var body: some View {
        Text(active ? "Active" : "Off")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
            .foregroundStyle(active ? .green : .red)
            .clipShape(Capsule())
    }
}
